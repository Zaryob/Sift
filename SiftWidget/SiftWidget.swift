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
                ArticleSnapshot(id: UUID(), title: "Sample Article Headline 1", feedTitle: "Tech News", date: Date().addingTimeInterval(-600)),
                ArticleSnapshot(id: UUID(), title: "Sample Article Headline 2", feedTitle: "Science Journal", date: Date().addingTimeInterval(-3600)),
                ArticleSnapshot(id: UUID(), title: "Sample Article Headline 3", feedTitle: "Design Blog", date: Date().addingTimeInterval(-7200))
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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadSnapshots() -> [ArticleSnapshot] {
        let appGroupID = "group.com.sift.app"
        let userDefaultsKey = "sift_recent_articles_json"

        // 1. Check UserDefaults suite & standard
        if let groupDefaults = UserDefaults(suiteName: appGroupID),
           let jsonStr = groupDefaults.string(forKey: userDefaultsKey),
           let data = jsonStr.data(using: .utf8),
           let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data),
           !snapshots.isEmpty {
            return snapshots
        }

        if let jsonStr = UserDefaults.standard.string(forKey: userDefaultsKey),
           let data = jsonStr.data(using: .utf8),
           let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data),
           !snapshots.isEmpty {
            return snapshots
        }

        // 2. Check File candidates
        var candidates: [URL] = []
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            candidates.append(groupURL.appendingPathComponent("recent_articles.json"))
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let siftAppSupport = appSupport.appendingPathComponent("Sift", isDirectory: true)
        candidates.append(siftAppSupport.appendingPathComponent("recent_articles.json"))
        candidates.append(URL(fileURLWithPath: "/tmp/devplaceholder_sift_recent_articles.json"))
        candidates.append(URL(fileURLWithPath: "/tmp/sift_recent_articles.json"))

        for fileURL in candidates {
            if let data = try? Data(contentsOf: fileURL),
               let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data),
               !snapshots.isEmpty {
                return snapshots
            }
        }
        return []
    }
}

struct SiftWidgetEntryView: View {
    var entry: ArticleWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sift RSS", systemImage: "rss")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.articles.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No Recent Articles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let maxCount = maxArticlesCount(for: family)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.articles.prefix(maxCount))) { article in
                        Link(destination: URL(string: "rssreader://article/\(article.id.uuidString)")!) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(article.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(article.feedTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("•")
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
