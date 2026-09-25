import SwiftUI
import SwiftData
import WidgetKit
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    public static let siftHandleDeepLink = Notification.Name("siftHandleDeepLink")
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Register notification delegate immediately at app startup
        _ = NotificationManager.shared
        NotificationManager.shared.requestAuthorization()

        // Synchronize launchd background daemon and timers whenever a new app version or build runs
        LaunchAgentManager.shared.syncOnLaunch()
        BackgroundFeedScheduler.shared.syncOnLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the background when the window is closed
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowActionTarget.shared.showMainWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        WindowActionTarget.shared.showMainWindow()
        for url in urls {
            AppDelegate.pendingURL = url
            NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? PersistenceController.shared.container.mainContext.save()
    }
}
#endif

@main
struct SiftApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif
    @StateObject private var backgroundScheduler = BackgroundFeedScheduler.shared

    init() {
        #if os(macOS)
        if CommandLine.arguments.contains("--background-refresh") {
            Task {
                let service = FeedRefreshService()
                await service.refreshAllFeeds()
                WidgetSnapshotManager.shared.updateSnapshot(context: PersistenceController.shared.container.mainContext)
                WidgetCenter.shared.reloadAllTimelines()
                exit(0)
            }
        }
        #else
        // Queue an initial background refresh in case the app is closed before
        // it ever transitions through .background (e.g. killed from the app switcher).
        BackgroundFeedScheduler.shared.scheduleAppRefresh()
        #endif
        _ = NotificationManager.shared
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        #if os(macOS)
        Window("Sift", id: "main") {
            ContentView()
        }
        .modelContainer(PersistenceController.shared.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .modelContainer(PersistenceController.shared.container)
        }

        MenuBarExtra {
            MenuBarExtraView()
                .modelContainer(PersistenceController.shared.container)
        } label: {
            Image("MenuBarIcon")
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared.container)
        .backgroundTask(.appRefresh(BackgroundFeedScheduler.backgroundTaskIdentifier)) {
            await BackgroundFeedScheduler.shared.performBackgroundRefresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundFeedScheduler.shared.scheduleAppRefresh()
            }
        }
        #endif
    }
}
