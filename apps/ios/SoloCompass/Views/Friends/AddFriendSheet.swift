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
    /// US-014: which half of the sheet is showing — my shareable code, or the
    /// add-by-code (scan / type) flow.
    private enum Mode: Hashable {
        case myCode
        case addFriend
    }

    @State private var service: FriendService
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .myCode

    @State private var code: FriendCode?
    @State private var isLoading = true
    @State private var isRotating = false
    @State private var didCopy = false
    @State private var errorMessage: String?

    // MARK: - US-014: add-by-code state
    @State private var typedCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var resolvedProfile: FriendProfileData?
    @State private var isScanning = false
    @State private var isSending = false
    @State private var didSend = false

    public init(service: FriendService = .shared) {
        _service = State(initialValue: service)
    }

    /// Test/preview seam: open straight onto the add-by-code tab so the
    /// scan/enter flow is renderable without a UI tap (US-014 verify step).
    init(service: FriendService, startInAddFriend: Bool) {
        _service = State(initialValue: service)
        _mode = State(initialValue: startInAddFriend ? .addFriend : .myCode)
    }

    /// A normalised `FriendCode` from the manual-entry field, if well-formed.
    private var normalisedTyped: String {
        typedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var canRedeem: Bool {
        FriendCode.isValidFormat(normalisedTyped) && !isRedeeming
    }

    /// What we hand out when sharing — the bare code is enough to add someone.
    private var shareText: String {
        code.map { $0.rawValue } ?? ""
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text(NSLocalizedString("friends.add.mode.myCode", comment: "My code tab"))
                        .tag(Mode.myCode)
                    Text(NSLocalizedString("friends.add.mode.addFriend", comment: "Add friend tab"))
                        .tag(Mode.addFriend)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                switch mode {
                case .myCode:
                    myCodeBody
                case .addFriend:
                    addFriendBody
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
                    .foregroundStyle(CT.savedRed)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: errorMessage)
    }

    // MARK: - My-code body (US-013)

    @ViewBuilder
    private var myCodeBody: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let code {
            content(code: code)
        } else {
            errorState
        }
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
                    .foregroundStyle(didCopy ? CT.verifiedGreen : .secondary)
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

    // MARK: - Add-friend body (US-014: scan / enter code)

    @ViewBuilder
    private var addFriendBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(NSLocalizedString("friends.redeem.subtitle", comment: "Add by code subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Scan affordance.
                Button {
                    isScanning = true
                } label: {
                    Label(
                        NSLocalizedString("friends.redeem.scan", comment: "Scan QR"),
                        systemImage: "qrcode.viewfinder"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 24)

                // Manual entry.
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("friends.redeem.enter.label", comment: "Enter code label"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("SOLO-XXXX-XXXX", text: $typedCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onChange(of: typedCode) { _, newValue in
                            // Auto-uppercase as the user types; redeem/preview
                            // normalises trim again before the round-trip.
                            let upper = newValue.uppercased()
                            if upper != newValue { typedCode = upper }
                            redeemError = nil
                        }
                        .onSubmit { if canRedeem { Task { await redeem() } } }

                    Button {
                        Task { await redeem() }
                    } label: {
                        HStack {
                            if isRedeeming { ProgressView() }
                            Text(NSLocalizedString("friends.redeem.lookup", comment: "Look up code"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRedeem)
                }
                .padding(.horizontal, 24)

                if let redeemError {
                    Text(redeemError)
                        .font(.subheadline)
                        .foregroundStyle(CT.savedRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 24)
        }
        .animation(.easeInOut, value: redeemError)
        .sheet(isPresented: $isScanning) { scannerSheet }
        .sheet(item: $resolvedProfile) { profile in
            previewSheet(profile: profile)
        }
    }

    // MARK: - Scanner sheet (US-014)

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView(
                onCode: { raw in
                    isScanning = false
                    handleScanned(raw)
                },
                onError: {
                    isScanning = false
                    redeemError = NSLocalizedString("friends.redeem.scan.denied", comment: "Camera unavailable")
                }
            )
            .ignoresSafeArea()
            .navigationTitle(NSLocalizedString("friends.redeem.scan.title", comment: "Scan title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) { isScanning = false }
                }
            }
        }
    }

    // MARK: - Preview sheet (US-014: confirm → send request)

    private func previewSheet(profile: FriendProfileData) -> some View {
        NavigationStack {
            FriendProfileView(
                profile: profile,
                relation: service.relationState(with: profile.userId),
                onAddFriend: { Task { await sendRequest(to: profile.userId) } }
            )
            .navigationTitle(NSLocalizedString("friends.redeem.preview.title", comment: "Preview title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) {
                        resolvedProfile = nil
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if didSend {
                    Text(NSLocalizedString("friends.redeem.sent", comment: "Request sent"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(CT.verifiedGreen, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: didSend)
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

    // MARK: - US-014 actions

    /// Handle a scanned QR payload: a code string (possibly wrapped in a URL or
    /// label) is reduced to the embedded `SOLO-XXXX-XXXX` then redeemed.
    private func handleScanned(_ raw: String) {
        let upper = raw.uppercased()
        // Extract the canonical code substring if the payload wraps it.
        let extracted = extractCode(from: upper) ?? upper
        typedCode = extracted
        Task { await redeem() }
    }

    /// Pull a `SOLO-XXXX-XXXX` token out of an arbitrary scanned string.
    private func extractCode(from text: String) -> String? {
        let allowed = Set("SOLO-" + String(FriendCode.unambiguousAlphabet))
        let cleaned = String(text.filter { allowed.contains($0) })
        // The first well-formed 14-char window wins.
        for start in cleaned.indices {
            let end = cleaned.index(start, offsetBy: 14, limitedBy: cleaned.endIndex)
            guard let end else { break }
            let candidate = String(cleaned[start..<end])
            if FriendCode.isValidFormat(candidate) { return candidate }
        }
        return nil
    }

    /// Resolve the typed/scanned code via the Edge Function, then show preview.
    private func redeem() async {
        guard !isRedeeming else { return }
        isRedeeming = true
        redeemError = nil
        let result = await service.redeemFriendCode(FriendCode(rawValue: normalisedTyped))
        isRedeeming = false
        switch result {
        case .success(let profile):
            didSend = false
            resolvedProfile = profile
            Haptics.impact(.light)
        case .failure(let err):
            redeemError = err.localizedDescription
            Haptics.notify(.error)
        }
    }

    /// Confirm → send a `.friendCode`-sourced request to the previewed user.
    private func sendRequest(to userId: String) async {
        guard !isSending else { return }
        isSending = true
        let result = await service.sendRequest(to: userId, source: .friendCode)
        isSending = false
        switch result {
        case .success:
            withAnimation { didSend = true }
            Haptics.notify(.success)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                resolvedProfile = nil
                didSend = false
            }
        case .failure(let err):
            resolvedProfile = nil
            redeemError = err.localizedDescription
            Haptics.notify(.error)
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
