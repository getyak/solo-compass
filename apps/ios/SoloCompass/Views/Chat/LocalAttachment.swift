import UIKit

/// A draft attachment held by the input bar before the message is sent.
///
/// Distinct from `ChatAttachment` (the persisted, uploaded metadata): a
/// `LocalAttachment` still carries the raw `data` (and, for images, a decoded
/// `image` thumbnail) so the UI can preview it and the upload service can push
/// the bytes to storage. Once uploaded it is replaced by a `ChatAttachment`.
///
/// Reuses `ChatAttachment.Kind` (see `Models/ChatMessage.swift`) so the draft
/// and persisted layers share one discriminator. Equatable by `id` only — two
/// drafts are the same iff they are literally the same picked item.
public struct LocalAttachment: Identifiable, Equatable {
    public let id: UUID
    public let kind: ChatAttachment.Kind
    public let fileName: String
    public let mimeType: String
    public let data: Data
    /// Decoded preview thumbnail, present for `.image` kind. Nil for files.
    public let image: UIImage?

    public init(
        id: UUID = UUID(),
        kind: ChatAttachment.Kind,
        fileName: String,
        mimeType: String,
        data: Data,
        image: UIImage? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.image = image
    }

    /// Identity equality — `UIImage`/`Data` are intentionally excluded so the
    /// strip can diff drafts cheaply by their stable id.
    public static func == (lhs: LocalAttachment, rhs: LocalAttachment) -> Bool {
        lhs.id == rhs.id
    }

    /// Human-readable byte count for chip subtitles ("12 KB", "1.4 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}
