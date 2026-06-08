import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Pinned bottom input bar for `ChatSheet`. Combines:
///  * a multi-line text field (1–4 lines of growth)
///  * a send button
///  * a mic button with two interaction modes:
///     - tap = toggle voice mode (accessibility-friendly path)
///     - press-and-hold = push-to-talk (immediate touch-down feedback)
///  * an error banner pinned above the row when the orchestrator reports
///    a failure, with a Retry button.
///
/// State (listening / thinking / error) is rendered around the mic button
/// itself so the user always knows which mode the chat is in.
@MainActor
public struct ChatInputBar: View {
    /// Visible state of the input bar's mic affordance.
    public enum MicState: Equatable {
        case idle
        case listening
        case thinking
        case error
    }

    @Binding public var draftText: String
    /// Draft attachments staged for the next send, Instagram-DM style. The
    /// parent owns the array; the bar appends on pick and clears on send.
    @Binding public var attachments: [LocalAttachment]
    public let micState: MicState
    public let errorMessage: String?

    /// Fires when the user taps the send button (or hits return) with a
    /// non-empty draft. The trimmed text is passed in; the input bar
    /// clears `draftText` after the closure runs.
    ///
    /// Attachments are delivered via the `attachments` binding: callers read
    /// the staged drafts inside `onSend`; the bar clears them afterwards.
    public let onSend: (String) -> Void

    /// Tap-to-toggle voice mode (accessibility path). `true` requests start,
    /// `false` requests stop.
    public let onMicToggle: (Bool) -> Void

    /// Push-to-talk press change. `true` on touch-down, `false` on release.
    /// Fires synchronously with the touch so the bar can begin streaming
    /// the live transcript immediately.
    public let onMicPress: (Bool) -> Void

    /// Retry the last action that errored. Caller decides what "retry" means
    /// (usually re-running the last user transcript).
    public let onRetry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the soft pulse on the "Listening" status dot.
    @State private var listeningPulse: Bool = false

    // Attachment-picker presentation state.
    @State private var showAttachmentDialog = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false

    /// Primary initializer — includes the draft `attachments` binding.
    public init(
        draftText: Binding<String>,
        attachments: Binding<[LocalAttachment]>,
        micState: MicState,
        errorMessage: String?,
        onSend: @escaping (String) -> Void,
        onMicToggle: @escaping (Bool) -> Void,
        onMicPress: @escaping (Bool) -> Void,
        onRetry: @escaping () -> Void
    ) {
        self._draftText = draftText
        self._attachments = attachments
        self.micState = micState
        self.errorMessage = errorMessage
        self.onSend = onSend
        self.onMicToggle = onMicToggle
        self.onMicPress = onMicPress
        self.onRetry = onRetry
    }

    /// Backward-compatible initializer for callers that don't (yet) stage
    /// attachments. Binds `attachments` to a constant empty array.
    public init(
        draftText: Binding<String>,
        micState: MicState,
        errorMessage: String?,
        onSend: @escaping (String) -> Void,
        onMicToggle: @escaping (Bool) -> Void,
        onMicPress: @escaping (Bool) -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.init(
            draftText: draftText,
            attachments: .constant([]),
            micState: micState,
            errorMessage: errorMessage,
            onSend: onSend,
            onMicToggle: onMicToggle,
            onMicPress: onMicPress,
            onRetry: onRetry
        )
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                InlineBanner(
                    tone: .error,
                    title: errorMessage,
                    ctaLabel: NSLocalizedString("chat.error.retry", comment: "Retry"),
                    onCTA: onRetry
                )
            }

            stateLabel

            if !attachments.isEmpty {
                AttachmentDraftStrip(attachments: attachments) { id in
                    attachments.removeAll { $0.id == id }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(alignment: .bottom, spacing: 8) {
                plusButton
                textField
                // WeChat-style trailing affordance: an empty draft shows the mic;
                // as soon as the user types, it morphs into the send button. No
                // permanently-docked send key sitting low next to the mic.
                trailingButton
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: hasSendableDraft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(alignment: .top) {
            // Hairline top divider + opaque surface (replaces `.bar`).
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
            ChatCameraPicker { image in
                appendCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            ingest(fileResult: result)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateLabel: some View {
        switch micState {
        case .listening:
            HStack(spacing: 6) {
                Circle()
                    .fill(CT.sunGold)
                    .frame(width: 8, height: 8)
                    .scaleEffect(listeningPulse ? 1.35 : 1.0)
                    .opacity(listeningPulse ? 0.5 : 1.0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: listeningPulse
                    )
                Text(NSLocalizedString("chat.state.listening", comment: "Listening — release to send"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CT.sunGoldDeep)
                Spacer()
            }
            .transition(.opacity)
            .onAppear { if !reduceMotion { listeningPulse = true } }
            .onDisappear { listeningPulse = false }
        case .thinking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(NSLocalizedString("chat.state.thinking", comment: "Thinking…"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .transition(.opacity)
        case .idle, .error:
            EmptyView()
        }
    }

    /// Light mode uses the warm input fill; dark mode falls back to a system
    /// semantic surface so the parchment tint doesn't glow on black.
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
        // Multi-line growth comes free with `axis: .vertical` + lineLimit range.
        TextField(
            NSLocalizedString("chat.input.placeholder", comment: "Type a message…"),
            text: $draftText,
            axis: .vertical
        )
        .lineLimit(1...4)
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
        .accessibilityLabel(Text(NSLocalizedString("chat.input.placeholder", comment: "Type a message…")))
    }

    /// True when there is something to send: trimmed text OR a staged attachment.
    private var hasSendableDraft: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    /// WeChat-style single trailing slot: mic when the draft is empty, send when
    /// the user has typed (or staged an attachment). Morphs in place with a
    /// quick scale/opacity so it reads as one control changing mode, not two
    /// buttons swapping.
    @ViewBuilder
    private var trailingButton: some View {
        if hasSendableDraft {
            sendButton
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else {
            micButton
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    /// Filled-circle send key, sized to match the 40×40 plus/mic buttons so the
    /// row stays on one baseline (the old `.title2` glyph sat low). Only shown
    /// when there's a sendable draft, so it's always enabled.
    private var sendButton: some View {
        Button(action: submitDraft) {
            ZStack {
                Circle()
                    .fill(CT.accent)
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 0.88))
        .accessibilityLabel(Text(NSLocalizedString("chat.input.send.a11y", comment: "Send")))
    }

    private var micButton: some View {
        // `onPressingChanged` fires immediately on touch-down, giving us the
        // sub-frame feedback the redesign demands. `perform` is required by
        // the API but we don't use the long-press fire here — the tap
        // gesture below handles toggle mode.
        let micColor: Color = {
            switch micState {
            case .listening: return CT.sunGoldDeep
            case .thinking:  return CT.accent
            case .error:     return CT.bannerError
            case .idle:      return .primary
            }
        }()
        let isListening = micState == .listening
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return ZStack {
            shape
                .fill(isListening ? CT.sunGoldSoft : Color(.tertiarySystemBackground))
                .frame(width: 40, height: 40)
                .overlay(
                    shape.strokeBorder(
                        isListening ? CT.sunGold : CT.borderSubtle,
                        lineWidth: isListening ? 1 : 0.5
                    )
                )
            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(micColor)
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: micState == .listening || micState == .thinking
                )
        }
        .scaleEffect(isListening ? 1.08 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: micState)
        .contentShape(shape)
        .onLongPressGesture(
            minimumDuration: 0.0,
            maximumDistance: .infinity,
            perform: { /* no-op: tap is handled by the simultaneous gesture */ },
            onPressingChanged: { pressing in
                onMicPress(pressing)
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                Haptics.selection()
                let isStarting = micState != .listening
                onMicToggle(isStarting)
            }
        )
        .accessibilityLabel(Text(NSLocalizedString("chat.input.mic.a11y", comment: "Voice")))
        .accessibilityHint(Text(NSLocalizedString("chat.input.mic.hint", comment: "Tap to start or stop voice, hold to push-to-talk")))
        .accessibilityAddTraits(.startsMediaSession)
    }

    private func submitDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow sending an attachment-only message (no text).
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        Haptics.impact(.light)
        // Caller reads `attachments` (still bound) inside onSend, then we clear.
        onSend(trimmed)
        draftText = ""
        attachments = []
    }

    // MARK: - Attachment ingestion

    /// Decode picked photo-library items into image drafts.
    private func ingest(photoItems: [PhotosPickerItem]) async {
        var picked: [LocalAttachment] = []
        for item in photoItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let image = UIImage(data: data)
            let ext = (item.supportedContentTypes.first?.preferredFilenameExtension) ?? "jpg"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            picked.append(
                LocalAttachment(
                    kind: .image,
                    fileName: "image-\(UUID().uuidString.prefix(8)).\(ext)",
                    mimeType: mime,
                    data: data,
                    image: image
                )
            )
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
    private func ingest(fileResult: Result<[URL], Error>) {
        guard case let .success(urls) = fileResult else { return }
        var picked: [LocalAttachment] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)
            let isImage = type?.conforms(to: .image) ?? false
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            picked.append(
                LocalAttachment(
                    kind: isImage ? .image : .file,
                    fileName: url.lastPathComponent,
                    mimeType: mime,
                    data: data,
                    image: isImage ? UIImage(data: data) : nil
                )
            )
        }
        if !picked.isEmpty {
            attachments.append(contentsOf: picked)
        }
    }
}

// MARK: - Camera picker bridge

/// Minimal `UIImagePickerController` wrapper for in-app camera capture.
/// Presented only when `.camera` source is available (guarded by the caller).
private struct ChatCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ChatCameraPicker
        init(_ parent: ChatCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview("Idle") {
    StatefulPreviewWrapper(initial: "", micState: .idle, error: nil)
}

#Preview("Listening") {
    StatefulPreviewWrapper(initial: "", micState: .listening, error: nil)
}

#Preview("Thinking") {
    StatefulPreviewWrapper(initial: "Tell me more about that café", micState: .thinking, error: nil)
}

#Preview("Error") {
    StatefulPreviewWrapper(
        initial: "",
        micState: .idle,
        error: "Connection interrupted — please try again"
    )
}

#Preview("With attachments") {
    StatefulPreviewWrapper(
        initial: "Check these out",
        micState: .idle,
        error: nil,
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
private struct StatefulPreviewWrapper: View {
    @State var text: String
    @State var attachments: [LocalAttachment]
    let micState: ChatInputBar.MicState
    let error: String?

    init(
        initial: String,
        micState: ChatInputBar.MicState,
        error: String?,
        attachments: [LocalAttachment] = []
    ) {
        self._text = State(initialValue: initial)
        self._attachments = State(initialValue: attachments)
        self.micState = micState
        self.error = error
    }

    var body: some View {
        VStack {
            Spacer()
            ChatInputBar(
                draftText: $text,
                attachments: $attachments,
                micState: micState,
                errorMessage: error,
                onSend: { _ in },
                onMicToggle: { _ in },
                onMicPress: { _ in },
                onRetry: {}
            )
        }
    }
}
