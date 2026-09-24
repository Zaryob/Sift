import SwiftUI
import SwiftData

@main
struct SiftApp: App {
    @StateObject private var backgroundScheduler = BackgroundFeedScheduler.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared.container)
        
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(PersistenceController.shared.container)
        }
        
        MenuBarExtra("Sift RSS", systemImage: "rss") {
            MenuBarExtraView()
                .modelContainer(PersistenceController.shared.container)
        }
        #endif
    }
}
