import Foundation
import AppIntents

/// App Intent enabling Siri to generate and speak a personalized Sift briefing using Apple Intelligence.
public struct ReadSiftBriefingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Read Sift Briefing"
    public static var description = IntentDescription("Reads a spoken news briefing of your unread articles using Apple Intelligence and Siri.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let output = await ArticleIntelligenceService.shared.generateBriefingForUnreadArticlesOutput()
        return .result(dialog: IntentDialog(stringLiteral: Self.dialogText(for: output)))
    }

    private static func dialogText(for output: IntelligenceOutput) -> String {
        guard output.modelKind == .extractiveFallback else { return output.text }
        return String(localized: "Apple Intelligence was unavailable, so Sift used an offline briefing. \(output.text)")
    }
}

/// App Intent enabling Siri to summarize the most recent unread article in Sift.
public struct SummarizeLatestArticleIntent: AppIntent {
    public static var title: LocalizedStringResource = "Summarize Latest Article"
    public static var description = IntentDescription("Summarizes the most recent unread article from your RSS feeds.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let output = await ArticleIntelligenceService.shared.summarizeLatestUnreadArticleOutput()
        return .result(dialog: IntentDialog(stringLiteral: Self.dialogText(for: output)))
    }

    private static func dialogText(for output: IntelligenceOutput) -> String {
        guard output.modelKind == .extractiveFallback else { return output.text }
        return String(localized: "Apple Intelligence was unavailable, so Sift used an offline summary. \(output.text)")
    }
}

/// Summarizes a specific Sift article selected through Siri or Shortcuts.
public struct SummarizeArticleIntent: AppIntent {
    public static var title: LocalizedStringResource = "Summarize Article"
    public static var description = IntentDescription("Summarizes a selected article using Apple Intelligence.")
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "Article")
    public var article: ArticleEntity

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let output = await ArticleIntelligenceService.shared.summarizeArticle(id: article.id) else {
            return .result(dialog: "That article is no longer available in Sift.")
        }
        let text = output.modelKind == .extractiveFallback
            ? String(localized: "Apple Intelligence was unavailable, so Sift used an offline summary. \(output.text)")
            : output.text
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// Exposes Siri App Shortcuts for voice activation without manual shortcut setup.
public struct SiftShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadSiftBriefingIntent(),
            phrases: [
                "Read my \(.applicationName) briefing",
                "Give me my \(.applicationName) briefing",
                "What's new in \(.applicationName)?",
                "Read \(.applicationName)"
            ],
            shortTitle: "Sift Briefing",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: SummarizeLatestArticleIntent(),
            phrases: [
                "Summarize \(.applicationName)",
                "Summarize latest article in \(.applicationName)"
            ],
            shortTitle: "Summarize Latest",
            systemImageName: "sparkles"
        )
    }
}
