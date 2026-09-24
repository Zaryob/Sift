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

    private func saveSnapshots(_ snapshots: [ArticleSnapshot]) {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        let fileURL = groupURL.appendingPathComponent("recent_articles.json")
        do {
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save widget snapshot file: \(error)")
        }
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupID) else {
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
