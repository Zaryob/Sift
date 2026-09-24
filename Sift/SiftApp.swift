import SwiftUI
import SwiftData

@main
struct SiftApp: App {
    @StateObject private var backgroundScheduler = BackgroundFeedScheduler.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NotificationManager.shared.requestAuthorization()
                }
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .modelContainer(PersistenceController.shared.container)
        
        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(PersistenceController.shared.container)
        }
        
        MenuBarExtra("Sift RSS", systemImage: "dot.radiowaves.up.and.right") {
            MenuBarExtraView()
                .modelContainer(PersistenceController.shared.container)
        }
        #endif
    }
}
