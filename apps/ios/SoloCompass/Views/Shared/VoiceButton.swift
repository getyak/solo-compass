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

    private let startFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let endFeedback = UIImpactFeedbackGenerator(style: .soft)

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
            if isRecording, !liveTranscript.isEmpty {
                Text(liveTranscript)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .offset(y: -50)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            let granted = await voiceService.requestPermission()
            guard granted else {
                showPermissionAlert = true
                return
            }
            do {
                isRecording = true
                if !reduceMotion { pulse = true }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                liveTranscript = ""
                startFeedback.prepare()
                startFeedback.impactOccurred()
                endFeedback.prepare()
                let stream = try voiceService.startListening()
                streamTask = Task {
                    do {
                        for try await text in stream {
                            await MainActor.run { liveTranscript = text }
                        }
                    } catch {
                        // Surface recognition errors to the user via alert.
                        await MainActor.run {
                            isRecording = false
                            pulse = false
                            recognitionError = error.localizedDescription
                        }
                    }
                }
            } catch {
                isRecording = false
                pulse = false
                recognitionError = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        voiceService.stopListening()
        isRecording = false
        pulse = false
        let final = liveTranscript
        streamTask?.cancel()
        streamTask = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !final.isEmpty {
            endFeedback.impactOccurred()
            onTranscript(final)
        }
        liveTranscript = ""
    }
}

#Preview {
    VoiceButton(voiceService: VoiceService()) { transcript in
        print("Got: \(transcript)")
    }
    .padding()
}
