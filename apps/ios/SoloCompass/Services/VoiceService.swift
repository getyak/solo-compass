import Foundation
import Speech
import AVFoundation
import Observation
import os

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
        // Throttle the main-actor hop: at 1024-frame buffers the tap fires
        // ~43×/sec, and each hop wrote `amplitude` (an @Observable) → a full
        // SwiftUI waveform re-evaluation. That's 43 actor hops + 43 redraws per
        // second for a bar chart the eye can't resolve past ~20fps. The gate
        // hops only when the amplitude moved a visible amount OR ~50ms elapsed,
        // roughly halving the hop/redraw rate while keeping the attack crisp.
        let amplitudeGate = AmplitudeGate()
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            request.append(buffer)
            // Compute RMS amplitude for waveform rendering
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var rms: Float = 0
                for i in 0..<frames { rms += channelData[i] * channelData[i] }
                rms = sqrtf(rms / Float(max(frames, 1)))
                let normalized = Double(min(rms * 8, 1.0))
                guard amplitudeGate.shouldPublish(normalized, at: time.hostTime) else { return }
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

/// Coalesces the ~43 amplitude samples/sec the audio tap produces down to the
/// ~20/sec the waveform can actually show. Called from the real-time audio
/// thread, so it must be `Sendable` and lock-guarded — it holds only two
/// `Double`s behind an `os_unfair_lock`, cheap enough for a render-thread call.
///
/// Publish rule: emit when the amplitude moved ≥ `minDelta` (so a sudden
/// syllable's attack is never swallowed) OR ≥ `minInterval` elapsed since the
/// last emit (so a slow swell still animates). Everything else is dropped.
final class AmplitudeGate: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var lastPublished: Double = -1
    private var lastHostTime: UInt64 = 0

    /// Minimum visible amplitude change (0–1) that forces an immediate publish.
    private let minDelta: Double = 0.04
    /// Minimum wall-clock gap between forced publishes, in seconds (~20fps).
    private let minInterval: Double = 0.05

    /// `hostTime` is the buffer's `AVAudioTime.hostTime` (mach absolute ticks).
    func shouldPublish(_ amplitude: Double, at hostTime: UInt64) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let elapsed = Self.seconds(from: lastHostTime, to: hostTime)
        let movedEnough = abs(amplitude - lastPublished) >= minDelta
        let waitedEnough = lastHostTime == 0 || elapsed >= minInterval
        guard movedEnough || waitedEnough else { return false }

        lastPublished = amplitude
        lastHostTime = hostTime
        return true
    }

    /// Convert a mach-tick delta to seconds using the host timebase.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func seconds(from start: UInt64, to end: UInt64) -> Double {
        guard end > start, timebase.denom != 0 else { return .greatestFiniteMagnitude }
        let nanos = Double(end - start) * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000
    }
}
