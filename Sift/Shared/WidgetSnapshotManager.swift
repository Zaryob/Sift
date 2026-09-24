import Foundation
import SwiftData

public final class WidgetSnapshotManager {
    public static let shared = WidgetSnapshotManager()
    
    private let appGroupID = PersistenceController.appGroupID
    private let userDefaultsKey = "sift_recent_articles_json"
    public static let sharedFileURL = URL(fileURLWithPath: "/Users/Shared/sift_recent_articles.json")

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
                print("[WidgetSnapshotManager] Successfully generated and saving \(snapshots.count) article snapshots.")
                saveSnapshots(Array(snapshots))
            } else {
                print("[WidgetSnapshotManager] No articles found in database yet. Preserving existing snapshot storage.")
            }
        } catch {
            print("Failed to generate widget snapshot: \(error)")
        }
    }

    private func getSnapshotURLs() -> [URL] {
        var urls: [URL] = [Self.sharedFileURL]
        
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            urls.append(groupURL.appendingPathComponent("recent_articles.json"))
        }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let siftAppSupport = appSupport.appendingPathComponent("Sift", isDirectory: true)
        try? FileManager.default.createDirectory(at: siftAppSupport, withIntermediateDirectories: true)
        urls.append(siftAppSupport.appendingPathComponent("recent_articles.json"))
        
        urls.append(URL(fileURLWithPath: "/tmp/devplaceholder_sift_recent_articles.json"))
        urls.append(URL(fileURLWithPath: "/tmp/sift_recent_articles.json"))
        return urls
    }

    private func saveSnapshots(_ snapshots: [ArticleSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        
        // Save to file system candidates
        for url in getSnapshotURLs() {
            try? data.write(to: url, options: .atomic)
        }

        // Save to UserDefaults candidates
        if let jsonString = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: userDefaultsKey)
            if let groupDefaults = UserDefaults(suiteName: appGroupID) {
                groupDefaults.set(jsonString, forKey: userDefaultsKey)
            }
        }
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        let appGroupID = PersistenceController.appGroupID
        let userDefaultsKey = "sift_recent_articles_json"

        // 1. Check Shared User File
        if let data = try? Data(contentsOf: sharedFileURL),
           let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data),
           !snapshots.isEmpty {
            return snapshots
        }

        // 2. Check App Group Container JSON File
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let fileURL = groupURL.appendingPathComponent("recent_articles.json")
            if let data = try? Data(contentsOf: fileURL),
               let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data),
               !snapshots.isEmpty {
                return snapshots
            }
        }

        // 3. Check UserDefaults suite & standard
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

        // 4. Check File candidates
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let siftAppSupport = appSupport.appendingPathComponent("Sift", isDirectory: true)
        let candidates = [
            siftAppSupport.appendingPathComponent("recent_articles.json"),
            appSupport.appendingPathComponent("recent_articles.json"),
            URL(fileURLWithPath: "/tmp/devplaceholder_sift_recent_articles.json"),
            URL(fileURLWithPath: "/tmp/sift_recent_articles.json")
        ]

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
