import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// US-013: A sheet showing the current user's shareable friend code as text
/// (`SOLO-XXXX-XXXX`) plus a CoreImage-rendered QR encoding the same code, so
/// another traveler can add them by scanning or typing.
///
/// Affordances:
/// - Long-press the code → copy to the pasteboard.
/// - `ShareLink` → system share sheet with the code string.
/// - [Rotate] → revoke the old code and mint a new one (`FriendService`).
///
/// All code I/O defers to `FriendService` (the persistent relationship layer);
/// this view is presentational + dispatch. The code is lazily generated on
/// first open via `loadOrCreateFriendCode()`.
public struct AddFriendSheet: View {
    @State private var service: FriendService
    @Environment(\.dismiss) private var dismiss

    @State private var code: FriendCode?
    @State private var isLoading = true
    @State private var isRotating = false
    @State private var didCopy = false
    @State private var errorMessage: String?

    public init(service: FriendService = .shared) {
        _service = State(initialValue: service)
    }

    /// What we hand out when sharing — the bare code is enough to add someone.
    private var shareText: String {
        code.map { $0.rawValue } ?? ""
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let code {
                    content(code: code)
                } else {
                    errorState
                }
            }
            .navigationTitle(NSLocalizedString("friends.add.title", comment: "Add friend sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("action.done", comment: "Done")) { dismiss() }
                }
            }
        }
        .task { await load() }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: errorMessage)
    }

    // MARK: - Content

    private func content(code: FriendCode) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(NSLocalizedString("friends.add.subtitle", comment: "Add friend sheet subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // QR code.
                qrImage(for: code.rawValue)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel(NSLocalizedString("friends.add.qr.a11y", comment: "QR code accessibility"))

                // Code text — long-press to copy.
                VStack(spacing: 6) {
                    Text(code.rawValue)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .tracking(2)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                copy(code)
                            } label: {
                                Label(
                                    NSLocalizedString("friends.add.copy", comment: "Copy code"),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }
                    Text(
                        didCopy
                            ? NSLocalizedString("friends.add.copied", comment: "Copied confirmation")
                            : NSLocalizedString("friends.add.copy.hint", comment: "Long-press to copy hint")
                    )
                    .font(.caption)
                    .foregroundStyle(didCopy ? Color.green : .secondary)
                    .contentTransition(.opacity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(format: NSLocalizedString("friends.add.code.a11y", comment: "Friend code value"), code.rawValue))

                // Share + Rotate actions.
                VStack(spacing: 12) {
                    ShareLink(item: shareText) {
                        Label(
                            NSLocalizedString("friends.add.share", comment: "Share code"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await rotate() }
                    } label: {
                        HStack {
                            if isRotating {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(NSLocalizedString("friends.add.rotate", comment: "Rotate code"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRotating)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
        }
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label(
                NSLocalizedString("friends.add.error.title", comment: "Code load error"),
                systemImage: "qrcode"
            )
        } description: {
            Text(NSLocalizedString("friends.add.error.description", comment: "Code load error detail"))
        } actions: {
            Button(NSLocalizedString("friends.list.error.retry", comment: "Retry")) {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - QR generation (CoreImage)

    /// Render `string` into a crisp QR `Image` via `CIQRCodeGenerator`. The raw
    /// CI output is tiny (≈25pt); a scale transform keeps edges sharp, and
    /// `.interpolation(.none)` at the call site avoids blurring on upscale.
    private func qrImage(for string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        if let output = filter.outputImage {
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
                return Image(decorative: cgImage, scale: 1, orientation: .up)
            }
        }
        // Fallback: a plain symbol so the sheet never renders blank.
        return Image(systemName: "qrcode")
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        let result = await service.loadOrCreateFriendCode()
        isLoading = false
        switch result {
        case .success(let value):
            code = value
        case .failure(let err):
            code = nil
            errorMessage = err.localizedDescription
        }
    }

    private func rotate() async {
        guard !isRotating else { return }
        isRotating = true
        didCopy = false
        let result = await service.rotateFriendCode()
        isRotating = false
        switch result {
        case .success(let value):
            code = value
            Haptics.notify(.success)
        case .failure(let err):
            errorMessage = err.localizedDescription
            Haptics.notify(.error)
            scheduleErrorClear()
        }
    }

    private func copy(_ code: FriendCode) {
        UIPasteboard.general.string = code.rawValue
        Haptics.impact(.light)
        withAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { didCopy = false }
        }
    }

    private func scheduleErrorClear() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            errorMessage = nil
        }
    }
}

// MARK: - Preview

#Preview("Add Friend") {
    let service = FriendService()
    service.myFriendCode = FriendCode(rawValue: "SOLO-7K2F-9XQR")
    return AddFriendSheet(service: service)
}
