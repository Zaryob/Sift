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

    private func getSnapshotURL() -> URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return groupURL.appendingPathComponent("recent_articles.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("recent_articles.json")
    }

    private func saveSnapshots(_ snapshots: [ArticleSnapshot]) {
        let fileURL = getSnapshotURL()
        do {
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save widget snapshot file: \(error)")
        }
    }

    public static func loadSnapshots() -> [ArticleSnapshot] {
        let appGroupID = PersistenceController.appGroupID
        let fileURL: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            fileURL = groupURL.appendingPathComponent("recent_articles.json")
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            fileURL = appSupport.appendingPathComponent("recent_articles.json")
        }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshots = try? JSONDecoder().decode([ArticleSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }
}
