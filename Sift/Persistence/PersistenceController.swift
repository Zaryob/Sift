import Foundation
import SwiftData

nonisolated public final class PersistenceController: @unchecked Sendable {
    public static let appGroupID = "group.io.github.zaryob.sift"

    public static let shared = PersistenceController()

    public let container: ModelContainer

    public init(inMemory: Bool = false) {
        let schema = Schema([
            Feed.self,
            FeedItem.self
        ])
        
        let modelConfiguration: ModelConfiguration
        if inMemory {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            // Standard sandboxed persistent SQLite store.
            // Stored in the app's sandboxed Application Support directory with full read/write & lock support.
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("[PersistenceController] Successfully initialized persistent SwiftData container.")
        } catch {
            print("[PersistenceController] Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                // Notify the UI that we are running on a temporary in-memory store.
                // The user should be told to restart the app; all data in this session
                // will be lost. This is vastly better than a hard crash.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: PersistenceController.storeFailedNotification,
                        object: error
                    )
                }
            } catch {
                // Both persistent and in-memory stores failed — something is fundamentally
                // wrong with the environment. Crash with a clear message instead of
                // propagating into undefined state.
                fatalError("[PersistenceController] Could not create any ModelContainer: \(error)")
            }
        }
    }

    /// Posted on the main thread when the persistent store fails and Sift falls
    /// back to an in-memory (non-persistent) container. UI should show an alert.
    public static let storeFailedNotification = Notification.Name("SiftPersistentStoreFailedNotification")
}
