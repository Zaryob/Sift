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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowCloseHandler.shared.showMainWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WindowCloseHandler.shared.showMainWindow()
        if let url = urls.first {
            NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
        }
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
        WindowGroup(id: "main") {
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
