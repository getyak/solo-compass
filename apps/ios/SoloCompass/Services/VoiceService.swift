import Foundation
import Speech
import AVFoundation
import Observation

/// Native speech recognition. No third-party deps — uses SFSpeechRecognizer +
/// AVAudioEngine. Streams partial transcripts via AsyncThrowingStream so the
/// UI can show live waveform/text as the user speaks.
///
/// Main-actor isolated so callers (all SwiftUI views / view models) can `await`
/// `requestPermission()` and read `isListening` / `amplitude` without crossing
/// actor boundaries. Under `SWIFT_STRICT_CONCURRENCY: complete`, sending a
/// `VoiceService` value into a `@MainActor` method (e.g. ChatSheet's
/// push-to-talk task) is then race-free — the instance never leaves the main
/// actor.
@MainActor
@Observable
public final class VoiceService {
    /// Failures that can occur while capturing and transcribing the traveler's speech.
    public enum VoiceError: Error, LocalizedError {
        case permissionDenied
        case recognizerUnavailable
        case audioSessionFailed(Error)
        case recognitionFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return NSLocalizedString("voice.error.permission", comment: "Mic/speech permission denied")
            case .recognizerUnavailable:
                return NSLocalizedString("voice.error.unavailable", comment: "Speech recognizer unavailable")
            case .audioSessionFailed(let err):
                return err.localizedDescription
            case .recognitionFailed(let err):
                return err.localizedDescription
            }
        }
    }

    public private(set) var isListening: Bool = false

    /// Normalized amplitude 0–1 from the audio tap. Updated at ~60fps while
    /// listening. Consumed by VoiceWaveformView.
    public private(set) var amplitude: Double = 0

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    public init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Asks for both speech and microphone permission. Returns `true` only when
    /// both are granted.
    public func requestPermission() async -> Bool {
        let speechAuthorized: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }

        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Returns a stream of transcripts. Each yielded value is the *current*
    /// best-guess transcript (replace, do not append). Stream ends on
    /// `stopListening()` or when the recognizer signals final.
    public func startListening() throws -> AsyncThrowingStream<String, Error> {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        // Audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.audioSessionFailed(error)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        // The tap runs on a real-time, non-isolated audio thread. Capture
        // `request` directly (SFSpeechAudioBufferRecognitionRequest.append is
        // thread-safe) instead of touching main-actor-isolated `self` state, and
        // hop to the main actor only to publish the amplitude.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            // Compute RMS amplitude for waveform rendering
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var rms: Float = 0
                for i in 0..<frames { rms += channelData[i] * channelData[i] }
                rms = sqrtf(rms / Float(max(frames, 1)))
                let normalized = Double(min(rms * 8, 1.0))
                Task { @MainActor [weak self] in self?.amplitude = normalized }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceError.audioSessionFailed(error)
        }

        isListening = true

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        // Start the recognition task on the main actor (we're already isolated
        // here) so assigning `recognitionTask` is race-free. The recognizer's
        // result handler fires on a background queue; it only touches the
        // `Sendable` continuation directly and hops to the main actor for any
        // isolated cleanup.
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                    Task { @MainActor [weak self] in self?.cleanup() }
                }
            }
            if let error {
                continuation.finish(throwing: VoiceError.recognitionFailed(error))
                Task { @MainActor [weak self] in self?.cleanup() }
            }
        }

        continuation.onTermination = { _ in
            Task { @MainActor [weak self] in self?.stopListening() }
        }

        return stream
    }

    /// Stops voice capture and tears down the audio session.
    public func stopListening() {
        cleanup()
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        // Best-effort audio session deactivation — ignore if it fails (e.g.
        // another task is using the session).
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        amplitude = 0
    }
}
