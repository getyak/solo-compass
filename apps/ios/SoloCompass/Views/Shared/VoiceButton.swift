import SwiftUI

/// Long-press to speak. Releases → fires `onTranscript` with the final text.
public struct VoiceButton: View {
    let voiceService: VoiceService
    let onTranscript: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isRecording = false
    @State private var liveTranscript: String = ""
    @State private var showPermissionAlert = false
    @State private var recognitionError: String? = nil
    @State private var pulse = false
    @State private var streamTask: Task<Void, Never>?
    @State private var elapsed: TimeInterval = 0
    @State private var timerTask: Task<Void, Never>?

    // Retained generators — prepare() pre-warms the Taptic Engine to eliminate first-fire latency.
    private let recordStartGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let recordStopSuccessGenerator = UINotificationFeedbackGenerator()
    private let recordStopEmptyGenerator = UIImpactFeedbackGenerator(style: .light)
    private let permissionDeniedGenerator = UINotificationFeedbackGenerator()

    public init(voiceService: VoiceService, onTranscript: @escaping (String) -> Void) {
        self.voiceService = voiceService
        self.onTranscript = onTranscript
    }

    public var body: some View {
        ZStack {
            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 4)
                    .frame(width: 72, height: 72)
                    .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.2 : 0.95))
                    .opacity(reduceMotion ? 0.7 : (pulse ? 0.0 : 0.8))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }

            Circle()
                .fill(isRecording ? Color.red : Color.black.opacity(0.85))
                .frame(width: 56, height: 56)
                .shadow(radius: isRecording ? 10 : 4)

            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: isRecording)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in startRecording() }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // Pre-warm all generators at first touch so impactOccurred() fires without latency.
                    recordStartGenerator.prepare()
                    recordStopSuccessGenerator.prepare()
                    recordStopEmptyGenerator.prepare()
                    permissionDeniedGenerator.prepare()
                }
                .onEnded { _ in
                    if isRecording { stopRecording() }
                }
        )
        .accessibilityLabel(Text(NSLocalizedString("voice.button", comment: "Voice input")))
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
            if isRecording {
                VStack(spacing: 4) {
                    Text(formattedElapsed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(elapsed >= 50
                            ? AnyShapeStyle(Color.orange)
                            : AnyShapeStyle(Color.secondary))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: elapsed >= 50)
                        .accessibilityHidden(true)

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
                .offset(y: -62)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(String(format: NSLocalizedString("voice.recording.timer.a11y", comment: ""), Int(elapsed))))
            }
        }
    }

    // MARK: - Helpers

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
                if !reduceMotion { pulse = true }
                liveTranscript = ""
                elapsed = 0
                recordStartGenerator.impactOccurred()
                startElapsedTimer()
                let stream = try voiceService.startListening()
                streamTask = Task {
                    do {
                        for try await text in stream {
                            let animate = !reduceMotion
                            await MainActor.run { withAnimation(animate ? .easeOut(duration: 0.18) : nil) { liveTranscript = text } }
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

    private func stopRecording() {
        voiceService.stopListening()
        isRecording = false
        pulse = false
        stopElapsedTimer()
        let final = liveTranscript
        streamTask?.cancel()
        streamTask = nil
        if !final.isEmpty {
            recordStopSuccessGenerator.notificationOccurred(.success)
            onTranscript(final)
        } else {
            recordStopEmptyGenerator.impactOccurred()
        }
        liveTranscript = ""
    }

    private func startElapsedTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                elapsed += 1
            }
        }
    }

    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
        elapsed = 0
    }
}

#Preview("Default") {
    VoiceButton(voiceService: VoiceService()) { transcript in
        print("Got: \(transcript)")
    }
    .padding()
}

#Preview("Listening placeholder") {
    // Simulates the recording state before any speech is recognized.
    _ListeningPlaceholderPreview()
        .padding()
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
