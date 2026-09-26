import WidgetKit
import SwiftUI
#if os(macOS)
import Darwin
#endif

// MARK: - Relative Date Extension

extension Date {
    var compactTimeAgo: String {
        let elapsed = max(0, -self.timeIntervalSinceNow)
        if elapsed < 60 {
            return "now"
        }
        let minutes = Int(elapsed / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = Int(elapsed / 3600)
        if hours < 24 {
            return "\(hours)h"
        }
        let days = Int(elapsed / 86400)
        if days < 7 {
            return "\(days)d"
        }
        let weeks = Int(days / 7)
        if weeks < 4 {
            return "\(weeks)w"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

// MARK: - Timeline Entry

public struct WidgetArticleEntry: TimelineEntry {
    public let date: Date
    public let articles: [ArticleSnapshot]
    
    public init(date: Date, articles: [ArticleSnapshot]) {
        self.date = date
        self.articles = articles
    }
    
    public static var sample: WidgetArticleEntry {
        WidgetArticleEntry(
            date: Date(),
            articles: [
                ArticleSnapshot(
                    id: UUID(),
                    title: "Swift 6.0 Released with Full Concurrency Safety",
                    feedTitle: "Swift Blog",
                    date: Date().addingTimeInterval(-3600),
                    summary: "Swift 6 marks a major milestone with compile-time data race safety enabled by default across platforms.",
                    isRead: false
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "Designing Modern Multiplatform Applications with SwiftUI",
                    feedTitle: "Apple Developer",
                    date: Date().addingTimeInterval(-7200),
                    summary: "Learn best practices for SwiftUI and WidgetKit across iOS, iPadOS, and macOS.",
                    isRead: false
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "Appeals Court Reverses Decision on Landmark Tech Regulations",
                    feedTitle: "Business Insider",
                    date: Date().addingTimeInterval(-62400),
                    summary: "The federal appeals court issued a unanimous ruling reshaping compliance expectations for digital services.",
                    isRead: true
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "New Advances in Room-Temperature Quantum Processing",
                    feedTitle: "MIT Tech Review",
                    date: Date().addingTimeInterval(-86400),
                    summary: "Researchers achieve new coherence stability metrics in room-temperature qubit systems.",
                    isRead: true
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "Understanding Modern Distributed Storage Systems",
                    feedTitle: "Ars Technica",
                    date: Date().addingTimeInterval(-100000),
                    summary: "A deep dive into distributed consensus, raft algorithms, and modern storage replication.",
                    isRead: true
                ),
                ArticleSnapshot(
                    id: UUID(),
                    title: "Exploration of Deep Space Planetary Atmospheres",
                    feedTitle: "Science Daily",
                    date: Date().addingTimeInterval(-140000),
                    summary: "New spectrometer data reveals atmospheric composition of distant exoplanets.",
                    isRead: true
                )
            ]
        )
    }
}

// MARK: - Timeline Provider

public struct ArticleWidgetProvider: TimelineProvider {
    public typealias Entry = WidgetArticleEntry

    public init() {}

    public func placeholder(in context: Context) -> WidgetArticleEntry {
        WidgetArticleEntry.sample
    }

    public func getSnapshot(in context: Context, completion: @escaping (WidgetArticleEntry) -> Void) {
        let snapshots = loadSnapshots()
        let entry = WidgetArticleEntry(date: Date(), articles: snapshots.isEmpty ? WidgetArticleEntry.sample.articles : snapshots)
        completion(entry)
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetArticleEntry>) -> Void) {
        let snapshots = loadSnapshots()
        let entry = WidgetArticleEntry(date: Date(), articles: snapshots.isEmpty ? WidgetArticleEntry.sample.articles : snapshots)
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

// MARK: - Root Entry View

struct SiftWidgetEntryView: View {
    var entry: ArticleWidgetProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if entry.articles.isEmpty {
                emptyStateView
            } else {
                switch family {
                case .systemSmall:
                    SmallWidgetView(entry: entry)
                case .systemMedium:
                    MediumWidgetView(entry: entry)
                case .systemLarge, .systemExtraLarge:
                    LargeWidgetView(entry: entry)
                default:
                    MediumWidgetView(entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Sift", systemImage: "dot.radiowaves.up.and.right")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Spacer()
            }
            Spacer()
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No Recent Articles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Small Widget (Glance Mode)

private struct SmallWidgetView: View {
    let entry: ArticleWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Clean brand + last update time
            HStack {
                Label("Sift", systemImage: "dot.radiowaves.up.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            // Content: 2 distinct stories with full title breathing room
            let articles = Array(entry.articles.prefix(2))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(articles) { article in
                    Link(destination: articleURL(for: article.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(article.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 3) {
                                if !article.isRead {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 4, height: 4)
                                }
                                Text(article.feedTitle)
                                    .lineLimit(1)
                                Text("•")
                                    .foregroundStyle(.tertiary)
                                Text(article.date.compactTimeAgo)
                            }
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if article.id != articles.last?.id {
                        Divider()
                            .opacity(0.35)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Medium Widget (Feed Preview Mode)

private struct MediumWidgetView: View {
    let entry: ArticleWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label("Sift", systemImage: "dot.radiowaves.up.and.right")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8, weight: .semibold))
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            // Content: 3 feed preview items
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entry.articles.prefix(3))) { article in
                    Link(destination: articleURL(for: article.id)) {
                        HStack(alignment: .center, spacing: 7) {
                            // Orange dot only for unread articles
                            if !article.isRead {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                            } else {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 5, height: 5)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(article.feedTitle)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(article.date.compactTimeAgo)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Large Widget (Dashboard Mode)

private struct LargeWidgetView: View {
    let entry: ArticleWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("Sift", systemImage: "dot.radiowaves.up.and.right")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("Updated \(entry.date, format: .dateTime.hour().minute())")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            // Featured Hero Story Card
            if let featured = entry.articles.first {
                Link(destination: articleURL(for: featured.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 8, weight: .bold))
                                Text("TOP STORY")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())

                            Spacer()

                            Text(featured.feedTitle)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(featured.date.compactTimeAgo)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(featured.title)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let summary = featured.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Section Label
            HStack {
                Text("RECENT STORIES")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)

            // Latest Stories List
            let recentArticles = Array(entry.articles.dropFirst().prefix(4))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recentArticles) { article in
                    Link(destination: articleURL(for: article.id)) {
                        HStack(alignment: .center, spacing: 7) {
                            if !article.isRead {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                            } else {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 5, height: 5)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(article.feedTitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text("•")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Text(article.date.compactTimeAgo)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if article.id != recentArticles.last?.id {
                        Divider()
                            .opacity(0.25)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Navigation Helper

private func articleURL(for id: UUID) -> URL {
    URL(string: "rssreader://article/\(id.uuidString)") ?? URL(string: "rssreader://")!
}

// MARK: - Widget Declaration

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

// MARK: - Previews

#Preview("Small Widget", as: .systemSmall) {
    SiftWidget()
} timeline: {
    WidgetArticleEntry.sample
}

#Preview("Medium Widget", as: .systemMedium) {
    SiftWidget()
} timeline: {
    WidgetArticleEntry.sample
}

#Preview("Large Widget", as: .systemLarge) {
    SiftWidget()
} timeline: {
    WidgetArticleEntry.sample
}
