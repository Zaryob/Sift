import WidgetKit
import SwiftUI
#if os(macOS)
import Darwin
#endif

public struct WidgetArticleEntry: TimelineEntry {
    public let date: Date
    public let articles: [ArticleSnapshot]
    
    public init(date: Date, articles: [ArticleSnapshot]) {
        self.date = date
        self.articles = articles
    }
}

public struct ArticleWidgetProvider: TimelineProvider {
    public typealias Entry = WidgetArticleEntry

    public init() {}

    public func placeholder(in context: Context) -> WidgetArticleEntry {
        WidgetArticleEntry(
            date: Date(),
            articles: [
                ArticleSnapshot(id: UUID(), title: "Swift 6.0 Released with Full Concurrency Safety", feedTitle: "Swift Blog", date: Date()),
                ArticleSnapshot(id: UUID(), title: "Designing Modern Multiplatform Applications", feedTitle: "Apple Developer", date: Date())
            ]
        )
    }

    public func getSnapshot(in context: Context, completion: @escaping (WidgetArticleEntry) -> Void) {
        let snapshots = loadSnapshots()
        let entry = WidgetArticleEntry(date: Date(), articles: snapshots.isEmpty ? placeholder(in: context).articles : snapshots)
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
        var candidateURLs: [URL] = []

        #if os(macOS)
        // Resolve real user home directory outside sandbox container redirect
        let realHome: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = FileManager.default.string(withFileSystemRepresentation: dir, length: Int(strlen(dir)))
            realHome = URL(fileURLWithPath: path)
        } else {
            realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        }

        let realAppSupportPlist = realHome
            .appendingPathComponent("Library/Application Support/Sift/widget_articles.plist")
        candidateURLs.append(realAppSupportPlist)
        #endif

        // Container fallback
        let containerAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let containerPlist = containerAppSupport?.appendingPathComponent("Sift/widget_articles.plist") {
            candidateURLs.append(containerPlist)
        }

        // App Group fallback
        let appGroupID = "group.io.github.zaryob.sift"
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            candidateURLs.append(groupURL.appendingPathComponent("widget_articles.plist"))
        }

        let plistDecoder = PropertyListDecoder()
        let jsonDecoder = JSONDecoder()

        for url in candidateURLs {
            if let data = try? Data(contentsOf: url) {
                if let snapshots = try? plistDecoder.decode([ArticleSnapshot].self, from: data), !snapshots.isEmpty {
                    return snapshots
                }
                if let snapshots = try? jsonDecoder.decode([ArticleSnapshot].self, from: data), !snapshots.isEmpty {
                    return snapshots
                }
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
                Label("Sift RSS", systemImage: "dot.radiowaves.up.and.right")
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
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func maxArticlesCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 2
        case .systemMedium:
            return 3
        case .systemLarge:
            return 7
        case .systemExtraLarge:
            return 10
        @unknown default:
            return 3
        }
    }
}

public struct SiftWidget: Widget {
    public let kind: String = "SiftWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ArticleWidgetProvider()) { entry in
            SiftWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Sift Recent Articles")
        .description("View latest RSS headlines directly on your desktop or Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
