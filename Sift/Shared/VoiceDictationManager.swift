import SwiftUI
import Speech
import AVFoundation

@Observable
final class VoiceDictationManager {
    var isRecording: Bool = false
    var errorMessage: String? = nil

    #if os(iOS)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
    #endif

    func toggleRecording(onResult: @escaping (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(onResult: onResult)
        }
    }

    func startRecording(onResult: @escaping (String) -> Void) {
        #if os(iOS)
        stopRecording()

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.requestMicrophoneAndBegin(onResult: onResult)
                case .denied, .restricted:
                    self.errorMessage = "Speech recognition access was denied."
                case .notDetermined:
                    self.errorMessage = "Speech recognition not determined."
                @unknown default:
                    self.errorMessage = "Unknown speech recognition status."
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func requestMicrophoneAndBegin(onResult: @escaping (String) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.beginAudioSessionAndRecognition(onResult: onResult)
                    } else {
                        self.errorMessage = "Microphone access denied."
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.beginAudioSessionAndRecognition(onResult: onResult)
                    } else {
                        self.errorMessage = "Microphone access denied."
                    }
                }
            }
        }
    }

    private func beginAudioSessionAndRecognition(onResult: @escaping (String) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            self.errorMessage = "Speech recognizer is not available on this device."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            self.audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            self.isRecording = true
            self.errorMessage = nil

            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        onResult(text)
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            self.errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            stopRecording()
        }
    }
    #endif

    func stopRecording() {
        #if os(iOS)
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
}
