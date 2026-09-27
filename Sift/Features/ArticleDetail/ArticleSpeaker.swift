import Foundation
import AVFoundation
import Combine
import NaturalLanguage

/// Native Text-to-Speech service for listening to articles.
@MainActor
public final class ArticleSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = ArticleSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtteranceIDs: Set<ObjectIdentifier> = []
    private var pendingSegments: [(text: String, isTitle: Bool, isParagraphEnd: Bool)] = []
    private var nextSegmentIndex = 0
    private var activeVoice: AVSpeechSynthesisVoice?

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

        let segments = speechSegments(title: title, text: text)
        guard !segments.isEmpty else { return }

        currentArticleID = articleID
        isSpeaking = true
        isPaused = false
        pendingSegments = segments
        nextSegmentIndex = 0
        activeVoice = fallbackVoiceIfNeeded(for: "\(title) \(text)")
        speakNextSegment()
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
        activeUtteranceIDs.removeAll()
        pendingSegments.removeAll(keepingCapacity: false)
        nextSegmentIndex = 0
        activeVoice = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentArticleID = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.complete(utteranceID)
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.complete(utteranceID)
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

    private func complete(_ utteranceID: ObjectIdentifier) {
        guard activeUtteranceIDs.remove(utteranceID) != nil else { return }
        guard activeUtteranceIDs.isEmpty else { return }

        if nextSegmentIndex < pendingSegments.count, currentArticleID != nil {
            speakNextSegment()
            return
        }

        pendingSegments.removeAll(keepingCapacity: false)
        nextSegmentIndex = 0
        activeVoice = nil
        isSpeaking = false
        isPaused = false
        currentArticleID = nil
    }

    /// Feed the synthesizer one utterance at a time. Enqueuing every sentence
    /// of a long article at once can make AVSpeechSynthesizer monopolize the
    /// main thread while it prepares the complete queue.
    private func speakNextSegment() {
        guard nextSegmentIndex < pendingSegments.count else { return }

        let segment = pendingSegments[nextSegmentIndex]
        nextSegmentIndex += 1

        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = activeVoice
        utterance.prefersAssistiveTechnologySettings = true
        utterance.preUtteranceDelay = segment.isTitle ? 0 : 0.04
        utterance.postUtteranceDelay = segment.isParagraphEnd ? 0.28 : 0.12
        activeUtteranceIDs.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    private func bestAvailableVoice(for languageIdentifier: String) -> AVSpeechSynthesisVoice? {
        let requested = Locale.Language(identifier: languageIdentifier)
        let matchingVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            requested.isEquivalent(to: Locale.Language(identifier: voice.language))
        }

        return matchingVoices.first(where: { $0.quality == .premium })
            ?? matchingVoices.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: languageIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Keep the voice unset for system-language content so iOS can honor the
    /// person's default speech voice and rate. Select a language-specific voice
    /// only when the article is still in another language.
    private func fallbackVoiceIfNeeded(for text: String) -> AVSpeechSynthesisVoice? {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en-US"
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2_000)))

        guard let detectedLanguage = recognizer.dominantLanguage?.rawValue else {
            return nil
        }

        let preferred = Locale.Language(identifier: preferredLanguage)
        let detected = Locale.Language(identifier: detectedLanguage)
        guard !preferred.isEquivalent(to: detected) else {
            return nil
        }

        return bestAvailableVoice(for: detectedLanguage)
    }

    private func speechSegments(title: String, text: String) -> [(text: String, isTitle: Bool, isParagraphEnd: Bool)] {
        var segments: [(text: String, isTitle: Bool, isParagraphEnd: Bool)] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            segments.append((cleanTitle, true, true))
        }

        let paragraphs = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for paragraph in paragraphs {
            var sentences: [String] = []
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { substring, _, _, _ in
                if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                    sentences.append(sentence)
                }
            }

            if sentences.isEmpty {
                sentences = [paragraph]
            }
            for (index, sentence) in sentences.enumerated() {
                segments.append((sentence, false, index == sentences.count - 1))
            }
        }
        return segments
    }
}
