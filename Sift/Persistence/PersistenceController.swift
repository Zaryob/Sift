import Foundation
import SwiftData

public final class PersistenceController {
    public static let appGroupID = "group.com.sift.app"

    public static let shared: PersistenceController = {
        PersistenceController()
    }()

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
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
}
