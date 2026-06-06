import SwiftUI

/// Renders the attachments carried by a *sent* message inside its bubble.
///
/// - Images: tappable rounded thumbnail; tap opens a full-screen zoom cover.
/// - Files: a card (icon, name, size, open affordance) that opens the resolved
///   URL via the share/quick-look path the host wires up.
///
/// URLs are resolved lazily through `resolveURL` — Phase D supplies real signed
/// URLs from Supabase storage; until then it may return `nil`, in which case we
/// show a spinner / placeholder rather than a broken image.
@MainActor
struct AttachmentBubble: View {
    let attachments: [ChatAttachment]
    /// Resolves a persisted attachment to a loadable URL (e.g. a signed URL).
    /// Returns `nil` when the backend is not ready — UI degrades gracefully.
    let resolveURL: (ChatAttachment) async -> URL?

    /// 18pt continuous corners per contract §1.3.
    private let corner: CGFloat = 18
    private let thumbMax: CGFloat = 200

    @Environment(\.colorScheme) private var colorScheme
    @State private var zoomURL: IdentifiedURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                switch attachment.kind {
                case .image:
                    imageCell(attachment)
                case .file:
                    fileCard(attachment)
                }
            }
        }
        .fullScreenCover(item: $zoomURL) { wrapped in
            ZoomImageView(url: wrapped.url) { zoomURL = nil }
        }
    }

    // MARK: - Image

    private func imageCell(_ attachment: ChatAttachment) -> some View {
        ResolvedThumbnail(
            attachment: attachment,
            resolveURL: resolveURL,
            corner: corner,
            maxSide: thumbMax,
            borderColor: borderColor
        ) { url in
            zoomURL = IdentifiedURL(url: url)
        }
    }

    // MARK: - File

    private func fileCard(_ attachment: ChatAttachment) -> some View {
        FileCard(
            attachment: attachment,
            resolveURL: resolveURL,
            corner: corner,
            fill: cardFill,
            borderColor: borderColor
        )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.surfaceWhite
    }
}

// MARK: - Resolved image thumbnail

/// Resolves and loads an image attachment, showing a spinner until the URL and
/// bytes arrive. Tappable to zoom once loaded.
@MainActor
private struct ResolvedThumbnail: View {
    let attachment: ChatAttachment
    let resolveURL: (ChatAttachment) async -> URL?
    let corner: CGFloat
    let maxSide: CGFloat
    let borderColor: Color
    let onTap: (URL) -> Void

    @State private var url: URL?
    @State private var resolving = true

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: maxSide, maxHeight: maxSide)
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                            .onTapGesture { onTap(url) }
                    case .failure:
                        placeholder(systemImage: "exclamationmark.triangle")
                    case .empty:
                        loading
                    @unknown default:
                        loading
                    }
                }
            } else if resolving {
                loading
            } else {
                // Unresolved (backend not ready / transient failure): a tappable
                // retry placeholder rather than a permanent broken thumbnail.
                placeholder(systemImage: "arrow.clockwise")
                    .contentShape(Rectangle())
                    .onTapGesture { Task { await resolve() } }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .task { await resolve() }
        .accessibilityLabel(Text(url == nil ? "\(attachment.fileName), tap to retry" : attachment.fileName))
        .accessibilityAddTraits(.isButton)
    }

    private func resolve() async {
        resolving = true
        url = await resolveURL(attachment)
        resolving = false
    }

    private var loading: some View {
        ZStack {
            Color(.tertiarySystemBackground)
            ProgressView()
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Color(.tertiarySystemBackground)
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - File card

@MainActor
private struct FileCard: View {
    let attachment: ChatAttachment
    let resolveURL: (ChatAttachment) async -> URL?
    let corner: CGFloat
    let fill: Color
    let borderColor: Color

    @State private var url: URL?
    @State private var resolving = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            // Resolved → open the file. Unresolved (backend not ready / transient
            // failure) → re-attempt resolution so the user isn't stuck.
            if let url {
                openURL(url)
            } else if !resolving {
                Task { await resolve() }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(CT.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    Text(formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if resolving {
                    ProgressView().scaleEffect(0.7)
                } else {
                    // Resolved → open affordance; unresolved → a retry affordance
                    // (NOT a download icon on a dead button, which reads as broken).
                    Image(systemName: url == nil ? "arrow.clockwise.circle" : "arrow.up.right.square")
                        .font(.body)
                        .foregroundStyle(url == nil ? Color.secondary : CT.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 260, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        // Intentionally NOT .disabled when url == nil — the button doubles as a
        // retry trigger so a transient resolve failure isn't a dead end.
        .task { await resolve() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(url == nil
            ? "\(attachment.fileName), \(formattedSize), tap to retry"
            : "\(attachment.fileName), \(formattedSize)"))
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(attachment.fileSizeBytes), countStyle: .file)
    }

    private func resolve() async {
        resolving = true
        url = await resolveURL(attachment)
        resolving = false
    }
}

// MARK: - Full-screen zoom

@MainActor
private struct ZoomImageView: View {
    let url: URL
    let onClose: () -> Void

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = max(1, $0) }
                                .onEnded { _ in withAnimation(.spring) { scale = 1 } }
                        )
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView().tint(.white)
                @unknown default:
                    ProgressView().tint(.white)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.white.opacity(0.25))
                    .padding()
            }
            .accessibilityLabel(Text(NSLocalizedString("chat.attachment.close.a11y", comment: "Close")))
        }
    }
}

/// Wraps a `URL` so it can drive an item-based `.fullScreenCover`.
private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview("Sent attachments") {
    let image = ChatAttachment(
        id: "att_img_1",
        kind: .image,
        fileName: "harbor-view.jpg",
        mimeType: "image/jpeg",
        fileSizeBytes: 482_000,
        storagePath: "conv/msg/att_img_1-harbor-view.jpg",
        width: 1200,
        height: 800
    )
    let file = ChatAttachment(
        id: "att_file_1",
        kind: .file,
        fileName: "tokyo-7-day-itinerary.pdf",
        mimeType: "application/pdf",
        fileSizeBytes: 1_950_000,
        storagePath: "conv/msg/att_file_1-tokyo-7-day-itinerary.pdf"
    )
    return AttachmentBubble(
        attachments: [image, file],
        // Phase D wires real signed URLs; preview returns nil → spinner/placeholder.
        resolveURL: { _ in nil }
    )
    .padding()
}
