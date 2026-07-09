import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The personal hub's Friends screen (pushed from `MeSheet`).
///
/// Redesigned per the "fewer steps, more elegant" brief: instead of an empty
/// state whose only action opens a separate `AddFriendSheet`, the add-by-code
/// search bar is **inlined at the top of the page**. Type (or scan) a friend
/// code and the lookup fires inline → a profile card slides up to confirm. The
/// user's own shareable code lives in a collapsible row below, so both halves
/// of the flow are reachable without ever presenting a sheet.
///
/// The backend only supports friend-code add (`redeemFriendCode`), not free-text
/// user search, so the "search bar" is a code field — the most direct shape the
/// data layer allows.
struct FriendsHubView: View {
    @State private var service: FriendService

    // Inline add-by-code state (lifted from the old AddFriendSheet).
    @State private var typedCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var resolvedProfile: FriendProfileData?
    @State private var isScanning = false
    @State private var isSending = false
    @State private var didSend = false

    // My shareable code (collapsible).
    @State private var showMyCode = false
    @State private var myCode: FriendCode?
    @State private var isLoadingMyCode = false
    @State private var didCopy = false

    @Environment(\.colorScheme) private var colorScheme

    init(service: FriendService = .shared) {
        _service = State(initialValue: service)
    }

    private var normalisedTyped: String {
        typedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var canRedeem: Bool {
        FriendCode.isValidFormat(normalisedTyped) && !isRedeeming
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                searchBar
                myCodeSection

                if !service.incomingRequests.isEmpty || !service.friends.isEmpty {
                    relationships
                } else {
                    emptyHint
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(pageBg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(NSLocalizedString("me.friends", comment: "Friends"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.refresh() }
        .animation(.easeInOut(duration: 0.2), value: redeemError)
        .animation(.easeInOut(duration: 0.25), value: showMyCode)
        .sheet(isPresented: $isScanning) { scannerSheet }
        .sheet(item: $resolvedProfile) { profile in previewSheet(profile: profile) }
    }

    // MARK: - Dark mode adaptive colors

    private var pageBg: Color { colorScheme == .dark ? CT.warmSheetDark : CT.bgWarm }
    private var cardBg: Color { colorScheme == .dark ? CT.warmCardDark : CT.surfaceWhite }
    private var cardBorder: Color { colorScheme == .dark ? CT.warmBorderDark : CT.borderSubtle }
    private var titleColor: Color { colorScheme == .dark ? CT.fgPrimaryDark : CT.fgPrimary }
    private var subtleColor: Color { colorScheme == .dark ? CT.fgMutedDark : CT.fgSubtle }

    // MARK: - Inline search bar (friend code + scan)

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subtleColor)

                TextField(
                    NSLocalizedString("friends.inline.search.placeholder", comment: "Friend code search placeholder"),
                    text: $typedCode
                )
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: typedCode) { _, newValue in
                    let upper = newValue.uppercased()
                    if upper != newValue { typedCode = upper }
                    redeemError = nil
                }
                .onSubmit { if canRedeem { Task { await redeem() } } }

                if isRedeeming {
                    ProgressView().controlSize(.small)
                } else if canRedeem {
                    Button {
                        Task { await redeem() }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(CT.accent)
                    }
                    .accessibilityLabel(Text(NSLocalizedString("friends.inline.lookup.a11y", comment: "Look up friend")))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )
            )

            Button {
                Haptics.impact(.light)
                isScanning = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(CT.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(colorScheme == .dark ? CT.warmSunkenDark : CT.accentSoft)
                    )
            }
            .accessibilityLabel(Text(NSLocalizedString("friends.inline.scan.a11y", comment: "Scan friend QR")))
        }
        .animation(.easeInOut(duration: 0.15), value: canRedeem)
        .overlay(alignment: .bottomLeading) {
            if let redeemError {
                Text(redeemError)
                    .font(.caption)
                    .foregroundStyle(CT.bannerError)
                    .padding(.top, 4)
                    .offset(y: 26)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - My friend code (collapsible)

    private var myCodeSection: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                showMyCode.toggle()
                if showMyCode, myCode == nil { Task { await loadMyCode() } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CT.accent)
                        .frame(width: 28)
                    Text(
                        showMyCode
                            ? NSLocalizedString("friends.inline.myCode.hide", comment: "Hide my code")
                            : NSLocalizedString("friends.inline.myCode.show", comment: "Show my code")
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(titleColor)
                    Spacer()
                    if let myCode, !showMyCode {
                        Text(myCode.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(subtleColor)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subtleColor)
                        .rotationEffect(.degrees(showMyCode ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showMyCode {
                Divider().overlay(cardBorder)
                myCodeExpanded
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var myCodeExpanded: some View {
        VStack(spacing: 16) {
            if isLoadingMyCode {
                ProgressView().frame(height: 200)
            } else if let myCode {
                qrImage(for: myCode.rawValue)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(cardBorder, lineWidth: 1)
                    )
                    .accessibilityLabel(NSLocalizedString("friends.add.qr.a11y", comment: "QR a11y"))

                VStack(spacing: 4) {
                    Text(myCode.rawValue)
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                        .tracking(2)
                        .foregroundStyle(titleColor)
                        .textSelection(.enabled)
                    Text(
                        didCopy
                            ? NSLocalizedString("friends.add.copied", comment: "Copied")
                            : NSLocalizedString("friends.add.copy.hint", comment: "Copy hint")
                    )
                    .font(.caption)
                    .foregroundStyle(didCopy ? CT.verifiedGreen : subtleColor)
                    .contentTransition(.opacity)
                }

                HStack(spacing: 10) {
                    ShareLink(item: myCode.rawValue) {
                        Label(
                            NSLocalizedString("friends.add.share", comment: "Share"),
                            systemImage: "square.and.arrow.up"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CT.accent)

                    Button {
                        copy(myCode)
                    } label: {
                        Label(
                            NSLocalizedString("friends.add.copy", comment: "Copy"),
                            systemImage: "doc.on.doc"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(CT.accent)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Relationships (requests + friends)

    private var relationships: some View {
        VStack(spacing: 16) {
            if !service.incomingRequests.isEmpty {
                section(title: NSLocalizedString("me.friends.incoming", comment: "Incoming requests")) {
                    ForEach(service.incomingRequests, id: \.id) { req in
                        friendRow(label: req.requesterId)
                    }
                }
            }
            if !service.friends.isEmpty {
                section(title: NSLocalizedString("me.friends.list", comment: "Friends list")) {
                    ForEach(service.friends, id: \.id) { friendship in
                        friendRow(label: friendship.userHighId)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(subtleColor)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(cardBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(cardBorder, lineWidth: 1)
                        )
                )
        }
    }

    private func friendRow(label: String) -> some View {
        HStack(spacing: 12) {
            Text("🧭")
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Circle().fill(CT.accentSoft))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(subtleColor)
            Text(NSLocalizedString("me.friends.empty.title", comment: "Empty title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(titleColor)
            Text(NSLocalizedString("me.friends.empty.description", comment: "Empty description"))
                .font(.caption)
                .foregroundStyle(subtleColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Scanner + preview sheets

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
                    Button(NSLocalizedString("action.cancel", comment: "Cancel")) { resolvedProfile = nil }
                }
            }
            .overlay(alignment: .bottom) {
                if didSend {
                    Text(NSLocalizedString("friends.redeem.sent", comment: "Sent"))
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
        return Image(systemName: "qrcode")
    }

    // MARK: - Actions

    private func handleScanned(_ raw: String) {
        let upper = raw.uppercased()
        let extracted = extractCode(from: upper) ?? upper
        typedCode = extracted
        Task { await redeem() }
    }

    private func extractCode(from text: String) -> String? {
        let allowed = Set("SOLO-" + String(FriendCode.unambiguousAlphabet))
        let cleaned = String(text.filter { allowed.contains($0) })
        for start in cleaned.indices {
            let end = cleaned.index(start, offsetBy: 14, limitedBy: cleaned.endIndex)
            guard let end else { break }
            let candidate = String(cleaned[start..<end])
            if FriendCode.isValidFormat(candidate) { return candidate }
        }
        return nil
    }

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

    private func sendRequest(to userId: String) async {
        guard !isSending else { return }
        isSending = true
        let result = await service.sendRequest(to: userId, source: .friendCode)
        isSending = false
        switch result {
        case .success:
            withAnimation { didSend = true }
            Haptics.notify(.success)
            typedCode = ""
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

    private func loadMyCode() async {
        isLoadingMyCode = true
        let result = await service.loadOrCreateFriendCode()
        isLoadingMyCode = false
        if case .success(let value) = result { myCode = value }
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
}

// MARK: - Preview

#Preview("Friends hub (empty)") {
    NavigationStack {
        FriendsHubView(service: FriendService())
    }
}
