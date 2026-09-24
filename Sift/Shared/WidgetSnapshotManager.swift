import Foundation
import SwiftData

public final class WidgetSnapshotManager {
    public static let shared = WidgetSnapshotManager()
    
    /// Standard generic macOS AppData directory: ~/Library/Application Support/Sift/
    public static var siftAppDataDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
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
            let items = try context.fetch(descriptor).prefix(10)
            let snapshots = items.map { item in
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
        
        let targetURL = Self.sharedCacheURL
        try? data.write(to: targetURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: targetURL.path)
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        let targetURL = sharedCacheURL
        guard let data = try? Data(contentsOf: targetURL) else {
            return []
        }

        // Decode from binary PropertyList format
        let decoder = PropertyListDecoder()
        if let snapshots = try? decoder.decode([ArticleSnapshot].self, from: data), !snapshots.isEmpty {
            return snapshots
        }

        // Fallback for JSON decode if needed
        if let jsonSnapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data), !jsonSnapshots.isEmpty {
            return jsonSnapshots
        }

        return []
    }
}
