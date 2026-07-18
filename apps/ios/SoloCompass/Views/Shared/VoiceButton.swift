import SwiftUI

/// Long-press to speak. Releases → fires `onTranscript` with the final text.
public struct VoiceButton: View {
    let voiceService: VoiceService
    let onTranscript: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxRecordingDuration: TimeInterval = 60

    @State private var isRecording = false
    @State private var liveTranscript: String = ""
    @State private var showPermissionAlert = false
    @State private var recognitionError: String? = nil
    @State private var pulse = false
    @State private var ringPulse = false
    @State private var streamTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var timerTask: Task<Void, Never>?
    @State private var didAutoStop = false
    @State private var autoStopMessage: String? = nil
    @State private var didWarnCountdown = false
    @State private var emptyHint: String? = nil
    @State private var emptyHintTask: Task<Void, Never>?

    // Retained generators — prepare() pre-warms the Taptic Engine to eliminate first-fire latency.
    private let recordStartGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let recordStopSuccessGenerator = UINotificationFeedbackGenerator()
    private let recordStopEmptyGenerator = UIImpactFeedbackGenerator(style: .light)
    private let permissionDeniedGenerator = UINotificationFeedbackGenerator()
    private let speechDetectedGenerator = UIImpactFeedbackGenerator(style: .light)

    @State private var didDetectSpeech = false

    /// True while the finger has slid far enough up during a hold that releasing
    /// will DISCARD the recording instead of sending it — the "slide up to
    /// cancel" affordance every voice-note UI has (WeChat, iMessage). Without it
    /// a hold-to-talk button can only ever commit: you say something wrong and
    /// your only exit is to send it. Drives the button's red cancel treatment
    /// and the hint copy.
    @State private var isInCancelZone = false
    /// Upward travel (pt) past which the release cancels rather than sends.
    private let cancelSlideThreshold: CGFloat = 80

    public init(voiceService: VoiceService, onTranscript: @escaping (String) -> Void) {
        self.voiceService = voiceService
        self.onTranscript = onTranscript
    }

    public var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .stroke(CT.savedRed.opacity(0.5), lineWidth: 4)
                    .frame(width: 72, height: 72)
                    .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.2 : 0.95))
                    .opacity(reduceMotion ? 0.7 : (pulse ? 0.0 : 0.8))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: pulse
                    )

                let progress = CGFloat(min(elapsed / maxRecordingDuration, 1.0))
                let nearEnd = elapsed >= 50
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        nearEnd ? CT.warningText : CT.savedRed.opacity(0.6),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(nearEnd && !reduceMotion ? (ringPulse ? 1.06 : 1.0) : 1.0)
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: nearEnd)
                    .animation(
                        nearEnd && !reduceMotion ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : nil,
                        value: ringPulse
                    )
                    .accessibilityHidden(true)
            }

            Circle()
                // In the cancel zone the button goes neutral-gray with an xmark
                // so the "release now = discard" outcome is unmistakable before
                // the finger lifts (apple-design §8: telegraph the outcome).
                .fill(isInCancelZone ? Color(white: 0.45) : (isRecording ? CT.savedRed : Color.black.opacity(0.85)))
                .frame(width: 56, height: 56)
                .shadow(radius: isRecording ? 10 : 4)

            Image(systemName: isInCancelZone ? "xmark" : (isRecording ? "waveform" : "mic.fill"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: isRecording && !isInCancelZone)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in startRecording() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Pre-warm all generators at first touch so impactOccurred() fires without latency.
                    recordStartGenerator.prepare()
                    recordStopSuccessGenerator.prepare()
                    recordStopEmptyGenerator.prepare()
                    permissionDeniedGenerator.prepare()
                    speechDetectedGenerator.prepare()

                    // Slide-up-to-cancel: while recording, track upward travel.
                    // Crossing the threshold arms cancel (and disarming below it
                    // re-arms send), each transition ticking a haptic so the
                    // state change is felt without looking.
                    guard isRecording else { return }
                    let over = value.translation.height < -cancelSlideThreshold
                    if over != isInCancelZone {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            isInCancelZone = over
                        }
                        Haptics.selection()
                    }
                }
                .onEnded { _ in
                    guard isRecording else { return }
                    if isInCancelZone {
                        cancelRecording()
                    } else {
                        stopRecording()
                    }
                }
        )
        .accessibilityLabel(Text(NSLocalizedString("voice.button", comment: "Voice input")))
        .accessibilityHint(Text(NSLocalizedString("voice.button.hint", comment: "Double tap to start recording, double tap again to stop")))
        .accessibilityValue(Text(isRecording
            ? NSLocalizedString("voice.button.value.recording", comment: "Recording")
            : NSLocalizedString("voice.button.value.idle", comment: "Idle")))
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityAction(named: Text(NSLocalizedString("voice.a11y.toggle", comment: "Start/Stop voice input"))) {
            if isRecording { stopRecording() } else { startRecording() }
        }
        .alert(NSLocalizedString("voice.permission.title", comment: ""), isPresented: $showPermissionAlert) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("voice.permission.message", comment: ""))
        }
        .alert(NSLocalizedString("voice.error.title", comment: "Voice recognition error"),
               isPresented: Binding(get: { recognitionError != nil }, set: { if !$0 { recognitionError = nil } })) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { recognitionError = nil }
        } message: {
            Text(recognitionError ?? "")
        }
        .overlay(alignment: .top) {
            if isRecording || autoStopMessage != nil || emptyHint != nil {
                let secondsRemaining = Int(maxRecordingDuration) - Int(elapsed)
                let inCountdown = elapsed >= 50 && !didAutoStop
                VStack(spacing: 4) {
                    if isInCancelZone {
                        // In the cancel zone the whole pill collapses to one
                        // unambiguous "release to cancel" line — no timer, no
                        // transcript competing with the decision.
                        Text(NSLocalizedString("voice.recording.releaseToCancel", comment: "Release to cancel"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AnyShapeStyle(CT.savedRed))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .transition(reduceMotion ? .identity : .opacity)
                            .accessibilityHidden(true)
                    } else if let hint = emptyHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(AnyShapeStyle(CT.warningText))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .transition(reduceMotion ? .identity : .opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hint)
                            .accessibilityHidden(true)
                    } else if let message = autoStopMessage {
                        Text(message)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AnyShapeStyle(CT.warningText))
                            .accessibilityHidden(true)
                    } else if inCountdown {
                        Text(String(format: NSLocalizedString("voice.recording.secondsLeft", comment: "%ds left countdown"), secondsRemaining))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AnyShapeStyle(CT.warningText))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: secondsRemaining)
                            .accessibilityHidden(true)
                    } else {
                        Text(formattedElapsed)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AnyShapeStyle(Color.secondary))
                            .accessibilityHidden(true)
                    }

                    if emptyHint == nil && !isInCancelZone {
                        let displayText = liveTranscript.isEmpty
                            ? NSLocalizedString("chat.voice.listening", comment: "Listening placeholder")
                            : liveTranscript
                        Text(displayText)
                            .font(.caption)
                            .foregroundStyle(liveTranscript.isEmpty ? .secondary : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .transition(reduceMotion ? .identity : .opacity)
                            .id(liveTranscript.isEmpty)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: liveTranscript.isEmpty)
                    }
                }
                .offset(y: -62)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(emptyHint != nil
                    ? (emptyHint ?? "")
                    : inCountdown
                        ? String(format: NSLocalizedString("voice.recording.secondsLeft", comment: ""), secondsRemaining)
                        : String(format: NSLocalizedString("voice.recording.timer.a11y", comment: ""), Int(elapsed))))
            }
        }
    }

    // MARK: - Helpers

    static func shouldFireSpeechHaptic(alreadyFired: Bool, transcript: String) -> Bool {
        !alreadyFired && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedElapsed: String {
        let min = Int(elapsed) / 60
        let sec = Int(elapsed) % 60
        return String(format: "%d:%02d", min, sec)
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            let granted = await voiceService.requestPermission()
            guard granted else {
                permissionDeniedGenerator.notificationOccurred(.warning)
                showPermissionAlert = true
                return
            }
            do {
                isRecording = true
                isInCancelZone = false
                if !reduceMotion { pulse = true }
                liveTranscript = ""
                elapsed = 0
                didAutoStop = false
                autoStopMessage = nil
                didWarnCountdown = false
                didDetectSpeech = false
                recordStartGenerator.impactOccurred()
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(notification: .announcement,
                        argument: NSLocalizedString("voice.announcement.listening", comment: "Listening…"))
                }
                startElapsedTimer()
                let stream = try voiceService.startListening()
                streamTask = Task {
                    do {
                        for try await text in stream {
                            let animate = !reduceMotion
                            await MainActor.run {
                                withAnimation(animate ? .easeOut(duration: 0.18) : nil) { liveTranscript = text }
                                if VoiceButton.shouldFireSpeechHaptic(alreadyFired: didDetectSpeech, transcript: text) {
                                    didDetectSpeech = true
                                    speechDetectedGenerator.impactOccurred()
                                }
                            }
                        }
                    } catch {
                        guard !(error is CancellationError) else { return }
                        // Surface recognition errors to the user via alert.
                        await MainActor.run {
                            isRecording = false
                            pulse = false
                            stopElapsedTimer()
                            recognitionError = error.localizedDescription
                        }
                    }
                }
            } catch {
                isRecording = false
                pulse = false
                stopElapsedTimer()
                recognitionError = error.localizedDescription
            }
        }
    }

    private func stopRecording(suppressStoppedAnnouncement: Bool = false) {
        voiceService.stopListening()
        isRecording = false
        pulse = false
        let recordingElapsed = elapsed
        stopElapsedTimer()
        if UIAccessibility.isVoiceOverRunning && !suppressStoppedAnnouncement {
            UIAccessibility.post(notification: .announcement,
                argument: NSLocalizedString("voice.announcement.stopped", comment: "Recording stopped"))
        }
        let final = liveTranscript
        streamTask?.cancel()
        streamTask = nil
        if !final.isEmpty {
            recordStopSuccessGenerator.notificationOccurred(.success)
            onTranscript(final)
        } else {
            recordStopEmptyGenerator.impactOccurred()
            let hintKey = recordingElapsed < 1.0
                ? "voice.recording.tooShort"
                : "voice.recording.empty"
            let hint = NSLocalizedString(hintKey, comment: "")
            emptyHint = hint
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: hint)
            }
            emptyHintTask?.cancel()
            emptyHintTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                if emptyHint == hint { emptyHint = nil }
            }
        }
        liveTranscript = ""
    }

    /// Slide-up cancel: stop listening and DISCARD the transcript — the mirror
    /// of `stopRecording`, minus the `onTranscript` callback and success haptic.
    /// A soft impact + spoken announcement confirm the discard.
    private func cancelRecording() {
        voiceService.stopListening()
        isRecording = false
        pulse = false
        stopElapsedTimer()
        streamTask?.cancel()
        streamTask = nil
        liveTranscript = ""
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            isInCancelZone = false
        }
        recordStopEmptyGenerator.impactOccurred()
        let hint = NSLocalizedString("voice.recording.cancelled", comment: "Recording discarded")
        emptyHint = hint
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: hint)
        }
        emptyHintTask?.cancel()
        emptyHintTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            if emptyHint == hint { emptyHint = nil }
        }
    }

    private func startElapsedTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                elapsed += 1
                if elapsed >= 50 && !ringPulse && !reduceMotion {
                    ringPulse = true
                }
                if elapsed >= 50 && !didWarnCountdown {
                    didWarnCountdown = true
                    Haptics.notify(.warning)
                }
                if elapsed >= maxRecordingDuration && !didAutoStop {
                    didAutoStop = true
                    autoStopMessage = NSLocalizedString("voice.recording.maxReached", comment: "Maximum recording length reached")
                    if UIAccessibility.isVoiceOverRunning {
                        UIAccessibility.post(notification: .announcement,
                            argument: NSLocalizedString("voice.recording.maxReached.a11y", comment: "Maximum recording length reached — transcript saved"))
                    }
                    stopRecording(suppressStoppedAnnouncement: true)
                    // Keep the pill visible briefly before the timer resets it.
                    let capturedMessage = autoStopMessage
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        if autoStopMessage == capturedMessage {
                            autoStopMessage = nil
                        }
                    }
                    break
                }
            }
        }
    }

    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
        elapsed = 0
        // autoStopMessage is intentionally NOT cleared here; the auto-stop path
        // keeps it visible for ~1.2s via a delayed Task before nilling it out.
        // Manual stops don't set autoStopMessage, so it stays nil.
        ringPulse = false
        didWarnCountdown = false
    }
}

#Preview("Default") {
    VoiceButton(voiceService: VoiceService()) { transcript in
        #if DEBUG
        print("VoiceButton preview transcript: \(transcript)")
        #else
        _ = transcript
        #endif
    }
    .padding()
}

#Preview("Listening placeholder") {
    // Simulates the recording state before any speech is recognized.
    _ListeningPlaceholderPreview()
        .padding()
}

#Preview("Empty hint — too short") {
    _EmptyHintPreview(hint: NSLocalizedString("voice.recording.tooShort", comment: ""))
        .padding()
}

#Preview("Empty hint — silence") {
    _EmptyHintPreview(hint: NSLocalizedString("voice.recording.empty", comment: ""))
        .padding()
}

private struct _EmptyHintPreview: View {
    let hint: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(radius: 4)
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .top) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(AnyShapeStyle(Color.orange))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .transition(reduceMotion ? .identity : .opacity)
                .offset(y: -50)
        }
    }
}

private struct _ListeningPlaceholderPreview: View {
    @State private var isRecording = true
    @State private var liveTranscript = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .frame(width: 56, height: 56)
                .shadow(radius: 10)
            Image(systemName: "waveform")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .top) {
            let displayText = liveTranscript.isEmpty
                ? NSLocalizedString("chat.voice.listening", comment: "Listening placeholder")
                : liveTranscript
            Text(displayText)
                .font(.caption)
                .foregroundStyle(liveTranscript.isEmpty ? .secondary : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .offset(y: -50)
                .transition(reduceMotion ? .identity : .opacity)
                .id(liveTranscript.isEmpty)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: liveTranscript.isEmpty)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let animate = !reduceMotion
                withAnimation(animate ? .easeOut(duration: 0.18) : nil) { liveTranscript = "quiet café nearby" }
            }
        }
    }
}
