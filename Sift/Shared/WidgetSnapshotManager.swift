import Foundation
import SwiftData
import Darwin

public final class WidgetSnapshotManager {
    public static let shared = WidgetSnapshotManager()
    
    /// Standard generic macOS AppData directory: ~/Library/Application Support/Sift/
    public static var siftAppDataDirectory: URL {
        let realHome: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let path = FileManager.default.string(withFileSystemRepresentation: dir, length: Int(strlen(dir)))
            realHome = URL(fileURLWithPath: path)
        } else {
            realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        }
        let dir = realHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Sift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Primary shared file in generic AppData directory: ~/Library/Application Support/Sift/widget_articles.plist
    public static var sharedCacheURL: URL {
        siftAppDataDirectory.appendingPathComponent("widget_articles.plist")
    }

    public func updateSnapshot(context: ModelContext) {
        let descriptor = FetchDescriptor<FeedItem>(
            sortBy: [
                SortDescriptor(\.publicationDate, order: .reverse),
                SortDescriptor(\.discoveredDate, order: .reverse)
            ]
        )
        
        do {
            var items: [FeedItem] = (try? context.fetch(descriptor)) ?? []
            if items.isEmpty {
                items = (try? context.fetch(FetchDescriptor<FeedItem>())) ?? []
                items.sort { $0.publicationDate > $1.publicationDate }
            }
            
            let snapshots = items.prefix(10).map { item in
                ArticleSnapshot(
                    id: item.id,
                    title: item.title,
                    feedTitle: item.feed?.title ?? "Feed",
                    date: item.publicationDate
                )
            }
            if !snapshots.isEmpty {
                saveSnapshots(Array(snapshots))
            }
        } catch {
            print("[WidgetSnapshotManager] Failed to fetch articles: \(error)")
        }
    }

    public func saveSnapshots(_ snapshots: [ArticleSnapshot]) {
        guard !snapshots.isEmpty else { return }
        
        // Encode using Apple's high-performance native binary PropertyList format
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        
        guard let data = try? encoder.encode(snapshots) else { return }
        
        var targetURLs: [URL] = [Self.sharedCacheURL]
        
        // Also write to container App Support as fallback
        let containerAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let containerSift = containerAppSupport?.appendingPathComponent("Sift", isDirectory: true) {
            try? FileManager.default.createDirectory(at: containerSift, withIntermediateDirectories: true)
            targetURLs.append(containerSift.appendingPathComponent("widget_articles.plist"))
        }

        // Also write to App Group if configured
        let appGroupID = PersistenceController.appGroupID
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            targetURLs.append(groupURL.appendingPathComponent("widget_articles.plist"))
        }

        for url in targetURLs {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
        }
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        var candidateURLs: [URL] = [sharedCacheURL]
        
        let containerAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let containerSift = containerAppSupport?.appendingPathComponent("Sift", isDirectory: true) {
            candidateURLs.append(containerSift.appendingPathComponent("widget_articles.plist"))
        }

        let appGroupID = PersistenceController.appGroupID
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            candidateURLs.append(groupURL.appendingPathComponent("widget_articles.plist"))
        }

        let decoder = PropertyListDecoder()
        for url in candidateURLs {
            if let data = try? Data(contentsOf: url) {
                if let snapshots = try? decoder.decode([ArticleSnapshot].self, from: data), !snapshots.isEmpty {
                    return snapshots
                }
                if let jsonSnapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data), !jsonSnapshots.isEmpty {
                    return jsonSnapshots
                }
            }
        }

        return []
    }
}
