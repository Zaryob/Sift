import WidgetKit
import SwiftUI

public struct WidgetArticleEntry: TimelineEntry {
    public let date: Date
    public let articles: [ArticleSnapshot]

    public init(date: Date, articles: [ArticleSnapshot]) {
        self.date = date
        self.articles = articles
    }
}

public struct ArticleWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> WidgetArticleEntry {
        WidgetArticleEntry(
            date: Date(),
            articles: [
                ArticleSnapshot(id: UUID(), title: "Apple Releases macOS 15 Sequoia", feedTitle: "Ars Technica", date: Date().addingTimeInterval(-600)),
                ArticleSnapshot(id: UUID(), title: "New Swift 6 Concurrency Features", feedTitle: "Swift Blog", date: Date().addingTimeInterval(-3600)),
                ArticleSnapshot(id: UUID(), title: "Linux Kernel 6.11 Released", feedTitle: "LWN", date: Date().addingTimeInterval(-7200))
            ]
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (WidgetArticleEntry) -> Void) {
        let snapshots = loadSnapshots()
        let entry = WidgetArticleEntry(date: Date(), articles: snapshots)
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetArticleEntry>) -> Void) {
        let snapshots = loadSnapshots()
        let entry = WidgetArticleEntry(date: Date(), articles: snapshots)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadSnapshots() -> [ArticleSnapshot] {
        let appGroupID = "group.com.sift.app"
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return []
        }
        let fileURL = groupURL.appendingPathComponent("recent_articles.json")
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }
}

struct SiftWidgetEntryView: View {
    var entry: ArticleWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Latest Articles", systemImage: "rss")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.articles.isEmpty {
                VStack {
                    Spacer()
                    Text("No Recent Articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                let maxCount = maxArticlesCount(for: family)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.articles.prefix(maxCount))) { article in
                        Link(destination: URL(string: "rssreader://article/\(article.id.uuidString)")!) {
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(article.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(article.feedTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Text(article.date, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .widgetURL(URL(string: "rssreader://all")!)
    }

    private func maxArticlesCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 4
        case .systemLarge: return 7
        default: return 4
        }
    }
}

struct SiftWidget: Widget {
    let kind: String = "SiftWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ArticleWidgetProvider()) { entry in
            SiftWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sift Recent Articles")
        .description("View recent RSS articles.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
