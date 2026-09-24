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
        } else if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            let storeURL = appGroupURL.appendingPathComponent("SiftData.sqlite")
            modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            modelConfiguration = ModelConfiguration(schema: schema)
        }

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to initialize ModelContainer: \(error). Falling back to in-memory store.")
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
}
