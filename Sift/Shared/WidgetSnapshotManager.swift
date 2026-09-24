import Foundation
import SwiftData

public final class WidgetSnapshotManager {
    public static let shared = WidgetSnapshotManager()
    
    private let appGroupID = PersistenceController.appGroupID

    public func updateSnapshot(context: ModelContext) {
        let descriptor = FetchDescriptor<FeedItem>(
            sortBy: [SortDescriptor(\.publicationDate, order: .reverse)]
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
            saveSnapshots(Array(snapshots))
        } catch {
            print("Failed to generate widget snapshot: \(error)")
        }
    }

    private func getSnapshotURLs() -> [URL] {
        var urls: [URL] = []
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            urls.append(groupURL.appendingPathComponent("recent_articles.json"))
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        urls.append(appSupport.appendingPathComponent("recent_articles.json"))
        
        let tmpURL = URL(fileURLWithPath: "/tmp/devplaceholder_sift_recent_articles.json")
        urls.append(tmpURL)
        return urls
    }

    private func saveSnapshots(_ snapshots: [ArticleSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        for url in getSnapshotURLs() {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        let appGroupID = PersistenceController.appGroupID
        var candidates: [URL] = []
        
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            candidates.append(groupURL.appendingPathComponent("recent_articles.json"))
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        candidates.append(appSupport.appendingPathComponent("recent_articles.json"))
        candidates.append(URL(fileURLWithPath: "/tmp/devplaceholder_sift_recent_articles.json"))

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
