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
    /// When the chat is anchored to a place (opened from a detail's "Ask Solo"),
    /// this carries the place name. A dismissable context pill floats above the
    /// composer and the field placeholder shifts to "Ask about <name>…". Nil for
    /// the global chat. Mirrors the handoff `.ai-ctx-chip`.
    public let placeContextName: String?
    /// Category accent of the anchored place. Drives a small filled dot at the
    /// head of the context pill so the anchor carries the place's own color (not
    /// a generic pin) — a quiet step beyond the flat handoff `.ai-ctx-chip`.
    /// Nil falls back to the brand accent.
    public let placeContextColor: Color?
    /// Tapping the context pill's `×`. Nil hides the dismiss affordance.
    public let onClearContext: (() -> Void)?

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
    /// Elapsed seconds while the amber recording bar is up. Driven by a local
    /// timer that starts when `micState` enters `.listening` and resets on exit.
    @State private var recordElapsed: TimeInterval = 0
    @State private var recordTimer: Timer?
    /// Whether the text field holds focus — drives a soft amber glow on the
    /// field so it lifts when the user is composing.
    @FocusState private var fieldFocused: Bool

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
        placeContextName: String? = nil,
        placeContextColor: Color? = nil,
        onSend: @escaping (String) -> Void,
        onMicToggle: @escaping (Bool) -> Void,
        onMicPress: @escaping (Bool) -> Void,
        onRetry: @escaping () -> Void,
        onClearContext: (() -> Void)? = nil
    ) {
        self._draftText = draftText
        self._attachments = attachments
        self.micState = micState
        self.errorMessage = errorMessage
        self.placeContextName = placeContextName
        self.placeContextColor = placeContextColor
        self.onSend = onSend
        self.onMicToggle = onMicToggle
        self.onMicPress = onMicPress
        self.onRetry = onRetry
        self.onClearContext = onClearContext
    }

    /// Backward-compatible initializer for callers that don't (yet) stage
    /// attachments. Binds `attachments` to a constant empty array.
    public init(
        draftText: Binding<String>,
        micState: MicState,
        errorMessage: String?,
        placeContextName: String? = nil,
        placeContextColor: Color? = nil,
        onSend: @escaping (String) -> Void,
        onMicToggle: @escaping (Bool) -> Void,
        onMicPress: @escaping (Bool) -> Void,
        onRetry: @escaping () -> Void,
        onClearContext: (() -> Void)? = nil
    ) {
        self.init(
            draftText: draftText,
            attachments: .constant([]),
            micState: micState,
            errorMessage: errorMessage,
            placeContextName: placeContextName,
            placeContextColor: placeContextColor,
            onSend: onSend,
            onMicToggle: onMicToggle,
            onMicPress: onMicPress,
            onRetry: onRetry,
            onClearContext: onClearContext
        )
    }

    public var body: some View {
        Group {
            if micState == .listening {
                // While push-to-talk is live the composer is irrelevant — the
                // whole bar becomes the amber waveform strip (design `.ai-recording`).
                recordingBar
                    .transition(.opacity)
            } else {
                composer
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: micState == .listening)
        .onChange(of: micState) { _, new in
            if new == .listening { startRecordTimer() } else { stopRecordTimer() }
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
            Task { await ingest(fileResult: result) }
        }
    }

    // MARK: - Composer

    /// The normal typing surface: error banner, optional state label, attachment
    /// strip, and the plus · field · trailing row. The anchored place surfaces
    /// through the field placeholder rather than a separate banner.
    private var composer: some View {
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

            // The standalone "正在问 <place>" banner is gone — it read as a
            // horizontal chrome strip bolted above the composer. The anchored
            // place now lives only in the field placeholder ("问问 <place>…"),
            // keeping the surface all-chat while the orchestrator still injects
            // the place into every turn's context (see prependContextRefresh).

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
    }

    // MARK: - Recording bar (hold-to-talk)

    /// Full-width amber waveform strip shown while listening. Mirrors the handoff
    /// `.ai-recording`: blinking dot · animated bars · mono timer · "Release to
    /// send". Releasing the mic (handled by the parent's gesture on the same
    /// surface) stops listening; tapping anywhere on the strip also ends it.
    private var recordingBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .opacity(listeningPulse ? 0.25 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                    value: listeningPulse
                )

            RecordingWaveform(active: !reduceMotion)
                .frame(height: 26)
                .frame(maxWidth: .infinity)

            Text(recordTimerLabel)
                .font(.system(size: 12, design: .monospaced))
                .tracking(0.6)
                .frame(minWidth: 34, alignment: .trailing)

            Text(NSLocalizedString("chat.record.releaseToSend", comment: "Release to send"))
                .font(.system(size: 11.5))
                .opacity(0.85)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(CT.accent)
        .contentShape(Rectangle())
        .onTapGesture { onMicToggle(false) }
        .onAppear { if !reduceMotion { listeningPulse = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: NSLocalizedString("chat.record.timer.a11y", comment: "Recording — %@ elapsed"),
            recordTimerLabel
        )))
    }

    private var recordTimerLabel: String {
        let total = Int(recordElapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startRecordTimer() {
        recordElapsed = 0
        recordTimer?.invalidate()
        recordTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in recordElapsed += 0.1 }
        }
    }

    private func stopRecordTimer() {
        recordTimer?.invalidate()
        recordTimer = nil
        recordElapsed = 0
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
            // Single source of truth: the message-list `AgentStatusLine` shows
            // the live thinking step. A duplicate label here read as two
            // competing loaders.
            EmptyView()
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

    /// Placeholder shifts to the place name when the chat is anchored.
    private var fieldPlaceholder: String {
        if let placeContextName {
            return String(
                format: NSLocalizedString("chat.input.placeholder.place", comment: "Ask about %@…"),
                placeContextName
            )
        }
        return NSLocalizedString("chat.input.placeholder", comment: "Type a message…")
    }

    private var textField: some View {
        // Multi-line growth comes free with `axis: .vertical` + lineLimit range.
        TextField(
            fieldPlaceholder,
            text: $draftText,
            axis: .vertical
        )
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .focused($fieldFocused)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(fieldFocused ? CT.surfaceWhite : inputFieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(fieldFocused ? CT.accentBorder : inputBorder, lineWidth: fieldFocused ? 1 : 0.5)
        )
        .overlay {
            thinkingShimmer(active: micState == .thinking)
        }
        .shadow(color: fieldFocused ? CT.accent.opacity(0.1) : .clear, radius: 6, y: 1)
        .animation(.easeOut(duration: 0.18), value: fieldFocused)
        .animation(.easeOut(duration: 0.25), value: micState)
        .submitLabel(.send)
        .onSubmit(submitDraft)
        .accessibilityLabel(Text(fieldPlaceholder))
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

    /// Animated 1.4s sweep that traces the input field border while the agent
    /// is thinking — a calm GPT-5-style cue that the composer is "busy" without
    /// adding a second label. Static (no animation) when reduceMotion is on.
    @ViewBuilder
    private func thinkingShimmer(active: Bool) -> some View {
        if active {
            ThinkingBorderShimmer()
                .allowsHitTesting(false)
                .transition(.opacity)
        }
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

    /// Decode picked photo-library items into image drafts. Full-resolution
    /// photo decode (10–50 MB) blocks for tens–hundreds of ms; run it off the
    /// main actor so the picker dismiss stays smooth, then hop back to append.
    private func ingest(photoItems: [PhotosPickerItem]) async {
        var picked: [LocalAttachment] = []
        for item in photoItems {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = (item.supportedContentTypes.first?.preferredFilenameExtension) ?? "jpg"
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
    /// Reads + decodes each file off the main actor (files can be large PDFs /
    /// videos) so the picker dismiss stays smooth; hops back only to append.
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

/// Shared off-main-actor decoders for chat attachment drafts. Both the Voice
/// Agent composer (`ChatInputBar`) and the companion composer (`AttachmentInputBar`)
/// pick photos/files; decoding a full-resolution image or reading a large file
/// blocks, so every path funnels through here to keep it off the main actor.
enum ChatAttachmentDecoder {
    /// Decode image bytes into a preview-ready draft off the main actor.
    /// `preparingForDisplay()` forces the decode now instead of lazily on the
    /// render thread at first draw.
    static func imageDraft(data: Data, fileName: String, mimeType: String) async -> LocalAttachment {
        let prepared: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(data: data) else { return nil }
            return raw.preparingForDisplay() ?? raw
        }.value
        return LocalAttachment(
            kind: .image,
            fileName: fileName,
            mimeType: mimeType,
            data: data,
            image: prepared
        )
    }

    /// Read one picked file off the main actor: opens its security scope, reads
    /// the bytes, and (for images) decodes a preview. Returns nil on read failure.
    static func fileDraft(_ url: URL) async -> LocalAttachment? {
        await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let type = UTType(filenameExtension: url.pathExtension)
            let isImage = type?.conforms(to: .image) ?? false
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let image = isImage ? UIImage(data: data)?.preparingForDisplay() : nil
            return LocalAttachment(
                kind: isImage ? .image : .file,
                fileName: url.lastPathComponent,
                mimeType: mime,
                data: data,
                image: image
            )
        }.value
    }
}

// MARK: - Recording waveform

/// 24 thin bars pulsing out of phase — the design `.ai-recording .wave`. Pure
/// decoration: it reads as "I'm listening" without claiming to mirror real
/// amplitude (the bars are evenly staggered, not audio-driven).
private struct RecordingWaveform: View {
    let active: Bool
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<24, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(maxWidth: 4, maxHeight: .infinity)
                    .scaleEffect(y: animating ? 1.0 : 0.18, anchor: .center)
                    .animation(
                        active
                            ? .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i % 6) * 0.12)
                            : nil,
                        value: animating
                    )
            }
        }
        .onAppear { if active { animating = true } }
        .accessibilityHidden(true)
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

#Preview("Place context") {
    StatefulPreviewWrapper(initial: "", micState: .idle, error: nil, placeContextName: "X10Kup Cafe")
}

#Preview("Listening (recording bar)") {
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
    @State private var text: String
    @State private var attachments: [LocalAttachment]
    let micState: ChatInputBar.MicState
    let error: String?
    let placeContextName: String?

    init(
        initial: String,
        micState: ChatInputBar.MicState,
        error: String?,
        attachments: [LocalAttachment] = [],
        placeContextName: String? = nil
    ) {
        self._text = State(initialValue: initial)
        self._attachments = State(initialValue: attachments)
        self.micState = micState
        self.error = error
        self.placeContextName = placeContextName
    }

    var body: some View {
        VStack {
            Spacer()
            ChatInputBar(
                draftText: $text,
                attachments: $attachments,
                micState: micState,
                errorMessage: error,
                placeContextName: placeContextName,
                onSend: { _ in },
                onMicToggle: { _ in },
                onMicPress: { _ in },
                onRetry: {},
                onClearContext: placeContextName != nil ? {} : nil
            )
        }
    }
}
