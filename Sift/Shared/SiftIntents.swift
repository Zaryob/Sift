import Foundation
import AppIntents

/// App Intent enabling Siri to generate and speak a personalized Sift briefing using Apple Intelligence.
public struct ReadSiftBriefingIntent: AppIntent {
    public static var title: LocalizedStringResource = "Read Sift Briefing"
    public static var description = IntentDescription("Reads a spoken news briefing of your unread articles using Apple Intelligence and Siri.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let briefing = await ArticleIntelligenceService.shared.generateBriefingForUnreadArticles()
        return .result(dialog: IntentDialog(stringLiteral: briefing))
    }
}

/// App Intent enabling Siri to summarize the most recent unread article in Sift.
public struct SummarizeLatestArticleIntent: AppIntent {
    public static var title: LocalizedStringResource = "Summarize Latest Article"
    public static var description = IntentDescription("Summarizes the most recent unread article from your RSS feeds.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await ArticleIntelligenceService.shared.summarizeLatestUnreadArticle()
        return .result(dialog: IntentDialog(stringLiteral: summary))
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
