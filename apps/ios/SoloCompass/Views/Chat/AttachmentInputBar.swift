import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Instagram-DM-style input bar for **human-to-human** chat (Companion DM).
///
/// Structurally mirrors the Voice-Agent `ChatInputBar` — a "+" attachment menu
/// (Photo Library / Camera / Files), a rounded growing text field, and an inline
/// send button — but deliberately drops the mic affordance: voice is a Voice-Agent
/// concern only. Keeping the picker plumbing here (rather than duplicating it into
/// `ChatView`) means both bars share one well-tested attachment ingestion path.
///
/// Camera capture reuses the existing internal `CameraPicker`
/// (`Views/Experience/CreateExperienceSheet.swift`) so no camera type is
/// redeclared (avoids colliding with `ChatCameraPicker` in `ChatInputBar.swift`).
@MainActor
struct AttachmentInputBar: View {
    @Binding var draftText: String
    /// Draft attachments staged for the next send. The parent owns the array;
    /// this bar appends on pick and clears it after `onSend` runs.
    @Binding var attachments: [LocalAttachment]
    /// True while a send is in flight — disables the send button.
    var isSending: Bool

    /// Fires when the user taps send (or hits return) with a non-empty draft OR
    /// at least one staged attachment. The trimmed text is passed in; the parent
    /// reads `attachments` (still bound) inside the closure, then this bar clears
    /// both `draftText` and `attachments`.
    let onSend: (String) -> Void

    let placeholder: String

    @Environment(\.colorScheme) private var colorScheme

    // Attachment-picker presentation state.
    @State private var showAttachmentDialog = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false

    init(
        draftText: Binding<String>,
        attachments: Binding<[LocalAttachment]>,
        isSending: Bool = false,
        placeholder: String,
        onSend: @escaping (String) -> Void
    ) {
        self._draftText = draftText
        self._attachments = attachments
        self.isSending = isSending
        self.placeholder = placeholder
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                AttachmentDraftStrip(attachments: attachments) { id in
                    attachments.removeAll { $0.id == id }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 8) {
                plusButton
                textField
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            // Hairline top divider + opaque surface, matching ChatInputBar.
            ZStack(alignment: .top) {
                Color(.systemBackground)
                Rectangle()
                    .fill(CT.borderDefault)
                    .frame(height: 0.5)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: attachments)
        .confirmationDialog(
            NSLocalizedString("chat.attachment.add.title", comment: "Add attachment"),
            isPresented: $showAttachmentDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("chat.attachment.source.photos", comment: "Photo Library")) {
                showPhotosPicker = true
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(NSLocalizedString("chat.attachment.source.camera", comment: "Camera")) {
                    showCamera = true
                }
            }
            Button(NSLocalizedString("chat.attachment.source.files", comment: "Files")) {
                showFileImporter = true
            }
            Button(NSLocalizedString("chat.attachment.source.cancel", comment: "Cancel"), role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoSelections,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: photoSelections) { _, items in
            Task { await ingest(photoItems: items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let image { appendCameraImage(image) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { await ingest(fileResult: result) }
        }
    }

    // MARK: - Subviews

    private var inputFieldFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : CT.chatInputBg
    }

    private var inputBorder: Color {
        colorScheme == .dark ? Color(.separator) : CT.borderSubtle
    }

    /// Instagram-style "+" entry that surfaces the photo/camera/files menu.
    private var plusButton: some View {
        Button {
            showAttachmentDialog = true
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(CT.accent)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CT.borderSubtle, lineWidth: 0.5)
                )
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.88))
        .accessibilityLabel(Text(NSLocalizedString("chat.attachment.add.a11y", comment: "Add attachment")))
    }

    private var textField: some View {
        TextField(placeholder, text: $draftText, axis: .vertical)
            .lineLimit(1...4)  // matches ChatInputBar (Voice Agent) growth
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(inputFieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(inputBorder, lineWidth: 0.5)
            )
            .submitLabel(.send)
            .onSubmit(submitDraft)
            .accessibilityLabel(Text(placeholder))
    }

    private var sendButton: some View {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Enabled when there's text OR at least one staged attachment.
        let canSend = (!trimmed.isEmpty || !attachments.isEmpty) && !isSending
        return Button(action: submitDraft) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(canSend ? CT.accent : Color.secondary.opacity(0.5))
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.88))
        .disabled(!canSend)
        .accessibilityLabel(Text(NSLocalizedString("chat.input.send.a11y", comment: "Send")))
    }

    private func submitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty) && !isSending else { return }
        // Caller reads `attachments` (still bound) inside onSend, then we clear.
        onSend(trimmed)
        draftText = ""
        attachments = []
    }

    // MARK: - Attachment ingestion

    /// Decode picked photo-library items into image drafts.
    ///
    /// A full-resolution `UIImage(data:)` decode of a modern phone photo (often
    /// 10–50 MB) can block for tens to hundreds of ms. Running it on the main
    /// actor froze the picker's dismiss animation the instant you tapped "add".
    /// We now decode + pre-render off the main actor and only hop back to append
    /// the finished, immutable draft — the UI stays live while the bytes land.
    private func ingest(photoItems: [PhotosPickerItem]) async {
        var picked: [LocalAttachment] = []
        for item in photoItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let draft = await ChatAttachmentDecoder.imageDraft(
                data: data,
                fileName: "image-\(UUID().uuidString.prefix(8)).\(ext)",
                mimeType: mime
            )
            picked.append(draft)
        }
        if !picked.isEmpty {
            attachments.append(contentsOf: picked)
        }
        photoSelections = []
    }

    /// Wrap a freshly captured camera photo as a JPEG image draft.
    private func appendCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        attachments.append(
            LocalAttachment(
                kind: .image,
                fileName: "camera-\(UUID().uuidString.prefix(8)).jpg",
                mimeType: "image/jpeg",
                data: data,
                image: image
            )
        )
    }

    /// Read security-scoped files chosen via the document picker into drafts.
    ///
    /// `Data(contentsOf:)` and image decode both block, and picked files can be
    /// large (a PDF, a video). Read + decode each off the main actor and hop
    /// back only to append; the picker dismiss stays smooth. The security scope
    /// must be opened/closed on the same actor that reads, so the whole
    /// per-URL read runs inside one detached task.
    private func ingest(fileResult: Result<[URL], Error>) async {
        guard case let .success(urls) = fileResult else { return }
        var picked: [LocalAttachment] = []
        for url in urls {
            if let draft = await ChatAttachmentDecoder.fileDraft(url) {
                picked.append(draft)
            }
        }
        if !picked.isEmpty {
            attachments.append(contentsOf: picked)
        }
    }
}

#Preview("Empty") {
    StatefulAttachmentBarPreview(initial: "")
}

#Preview("With attachments") {
    StatefulAttachmentBarPreview(
        initial: "Check these out",
        attachments: [
            LocalAttachment(
                kind: .image,
                fileName: "photo.jpg",
                mimeType: "image/jpeg",
                data: Data(count: 120_000),
                image: UIImage(systemName: "photo.fill")
            ),
            LocalAttachment(
                kind: .file,
                fileName: "notes.pdf",
                mimeType: "application/pdf",
                data: Data(count: 900_000),
                image: nil
            )
        ]
    )
}

/// Small helper so the previews can mutate `draftText` like the real parent.
private struct StatefulAttachmentBarPreview: View {
    @State private var text: String
    @State private var attachments: [LocalAttachment]

    init(initial: String, attachments: [LocalAttachment] = []) {
        self._text = State(initialValue: initial)
        self._attachments = State(initialValue: attachments)
    }

    var body: some View {
        VStack {
            Spacer()
            AttachmentInputBar(
                draftText: $text,
                attachments: $attachments,
                placeholder: "Message…",
                onSend: { _ in }
            )
        }
    }
}
