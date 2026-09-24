import SwiftUI
import SwiftData
import WidgetKit
import AppKit

extension Notification.Name {
    public static let siftHandleDeepLink = Notification.Name("siftHandleDeepLink")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Register notification delegate immediately at app startup
        _ = NotificationManager.shared
        NotificationManager.shared.requestAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the background when the window is closed
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowActionTarget.shared.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? PersistenceController.shared.container.mainContext.save()
    }
}

@main
struct SiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var backgroundScheduler = BackgroundFeedScheduler.shared

    init() {
        if CommandLine.arguments.contains("--background-refresh") {
            Task {
                let service = FeedRefreshService()
                await service.refreshAllFeeds()
                WidgetSnapshotManager.shared.updateSnapshot(context: PersistenceController.shared.container.mainContext)
                WidgetCenter.shared.reloadAllTimelines()
                exit(0)
            }
        }
    }

    var body: some Scene {
        Window("Sift", id: "main") {
            ContentView()
        }
        .handlesExternalEvents(matching: ["*"])
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
