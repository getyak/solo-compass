import Foundation
import Speech
import AVFoundation
import Observation

/// Native speech recognition. No third-party deps — uses SFSpeechRecognizer +
/// AVAudioEngine. Streams partial transcripts via AsyncThrowingStream so the
/// UI can show live waveform/text as the user speaks.
@Observable
public final class VoiceService {
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceError.audioSessionFailed(error)
        }

        isListening = true

        return AsyncThrowingStream { continuation in
            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    continuation.yield(result.bestTranscription.formattedString)
                    if result.isFinal {
                        continuation.finish()
                        self?.cleanup()
                    }
                }
                if let error {
                    continuation.finish(throwing: VoiceError.recognitionFailed(error))
                    self?.cleanup()
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.stopListening()
            }
        }
    }

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
        isListening = false
    }
}
