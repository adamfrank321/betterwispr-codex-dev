import Foundation
import Observation
@preconcurrency import AVFoundation
@preconcurrency import Speech

enum DictationError: LocalizedError {
    case microphoneDenied, speechDenied, localUnavailable, noSpeech, recognition(String)
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Enable microphone access for BetterWispr in Settings."
        case .speechDenied: "Enable speech recognition for BetterWispr in Settings."
        case .localUnavailable: "On-device speech is unavailable for this language. Install its dictation assets in iOS Settings or explicitly choose an API provider."
        case .noSpeech: "No speech was recognized. Try recording again."
        case .recognition(let message): message
        }
    }
}

@MainActor @Observable
final class DictationRecorder {
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var onLimit: (() -> Void)?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognitionTimeout: Task<Void, Never>?
    @ObservationIgnored private var continuation: CheckedContinuation<String, any Error>?
    @ObservationIgnored private var recognitionID = UUID()

    func start() async throws {
        cancel()
        let permission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard permission else { throw DictationError.microphoneDenied }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [])
        try audio.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("betterwispr-\(UUID().uuidString).m4a")
        recordingURL = url
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                                      AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        let capture = try AVAudioRecorder(url: url, settings: settings)
        capture.isMeteringEnabled = true
        guard capture.record() else { throw DictationError.recognition("Could not start microphone recording.") }
        recorder = capture; elapsed = 0
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let recorder = self.recorder else { return }
                recorder.updateMeters(); self.elapsed = recorder.currentTime
                self.level = pow(10, recorder.averagePower(forChannel: 0) / 20)
                if self.elapsed >= 60 { self.onLimit?(); return }
            }
        }
    }

    func stop() throws -> (url: URL, duration: TimeInterval) {
        guard let recorder, let url = recordingURL else { throw DictationError.noSpeech }
        let duration = recorder.currentTime
        recorder.stop(); self.recorder = nil; recordingURL = nil
        ticker?.cancel(); ticker = nil; level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (url, duration)
    }

    func transcribe(_ url: URL, language: String, hints: [String]) async throws -> String {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard authorization == .authorized else { throw DictationError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else { throw DictationError.localUnavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.contextualStrings = Array(hints.prefix(200))
        let token = UUID(); recognitionID = token
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                recognitionTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(90)) } catch { return }
                    guard let self, self.recognitionID == token else { return }
                    self.recognitionTask?.cancel()
                    self.complete(.failure(DictationError.recognition("Speech recognition timed out. Try a shorter clip.")))
                }
                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.bestTranscription.formattedString
                    let isFinal = result?.isFinal ?? false
                    let failure = error?.localizedDescription
                    Task { @MainActor in
                        guard let self, self.recognitionID == token else { return }
                        if let failure { self.complete(.failure(DictationError.recognition(failure))) }
                        else if isFinal, let text { self.complete(.success(text)) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.recognitionID == token else { return }
                self.complete(.failure(CancellationError())); self.recognitionTask?.cancel()
            }
        }
    }

    private func complete(_ result: Result<String, any Error>) {
        recognitionTimeout?.cancel(); recognitionTimeout = nil
        let pending = continuation; continuation = nil
        pending?.resume(with: result)
    }

    func cancel() {
        ticker?.cancel(); ticker = nil
        recorder?.stop(); recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        complete(.failure(CancellationError()))
        recognitionTask?.cancel(); recognitionTask = nil; recognitionID = UUID()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        level = 0
    }
}
