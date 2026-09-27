import Foundation
import AVFoundation
import Combine

/// Native Text-to-Speech service for listening to articles.
@MainActor
public final class ArticleSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = ArticleSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var currentArticleID: UUID?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the provided article title and content.
    public func speak(articleID: UUID, title: String, text: String) {
        if isSpeaking, currentArticleID == articleID {
            if isPaused {
                resume()
            } else {
                pause()
            }
            return
        }

        stop()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let fullText = "\(title).\n\n\(text)"
        let utterance = AVSpeechUtterance(string: fullText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        // Use current preferred system language voice or default
        if let language = Locale.preferredLanguages.first {
            utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
        }

        currentArticleID = articleID
        isSpeaking = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    /// Pauses ongoing speech.
    public func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// Resumes paused speech.
    public func resume() {
        guard isSpeaking, isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    /// Stops speech completely.
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentArticleID = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.currentArticleID = nil
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
            self.currentArticleID = nil
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = true
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPaused = false
        }
    }
}
