import SwiftUI

/// Horizontal strip of draft attachments shown above the input row, Instagram-DM
/// style: images render as rounded thumbnails, files as compact chips. Each item
/// carries an "X" delete affordance in its top-trailing corner.
///
/// Pure presentation — owns no state. The parent (`ChatInputBar`) holds the
/// `[LocalAttachment]` and supplies `onRemove` keyed by id.
@MainActor
struct AttachmentDraftStrip: View {
    let attachments: [LocalAttachment]
    /// Fires with the id of the draft the user tapped "X" on.
    let onRemove: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// 18pt continuous corners + 0.5pt border per contract §1.3.
    private let corner: CGFloat = 18
    private let thumbSide: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    cell(for: attachment)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(height: thumbSide + 8)
    }

    @ViewBuilder
    private func cell(for attachment: LocalAttachment) -> some View {
        content(for: attachment)
            .overlay(alignment: .topTrailing) {
                deleteButton(for: attachment.id)
                    .offset(x: 6, y: -6)
            }
    }

    @ViewBuilder
    private func content(for attachment: LocalAttachment) -> some View {
        switch attachment.kind {
        case .image:
            imageThumb(attachment)
        case .file:
            fileChip(attachment)
        }
    }

    private func imageThumb(_ attachment: LocalAttachment) -> some View {
        Group {
            if let image = attachment.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemBackground)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: thumbSide, height: thumbSide)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .accessibilityLabel(Text(attachment.fileName))
    }

    private func fileChip(_ attachment: LocalAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.body)
                .foregroundStyle(CT.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.fileName)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Text(attachment.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 180, minHeight: thumbSide, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(attachment.fileName), \(attachment.formattedSize)"))
    }

    private func deleteButton(for id: UUID) -> some View {
        Button {
            onRemove(id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(NSLocalizedString("chat.attachment.remove.a11y", comment: "Remove attachment")))
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }

    private var chipFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.chatInputBg
    }
}

#Preview("Draft strip — image + file") {
    let image = LocalAttachment(
        kind: .image,
        fileName: "sunset.jpg",
        mimeType: "image/jpeg",
        data: Data(count: 240_000),
        image: UIImage(systemName: "photo.fill")
    )
    let file = LocalAttachment(
        kind: .file,
        fileName: "tokyo-itinerary-draft.pdf",
        mimeType: "application/pdf",
        data: Data(count: 1_400_000),
        image: nil
    )
    return AttachmentDraftStrip(
        attachments: [image, file],
        onRemove: { _ in }
    )
    .padding()
}
