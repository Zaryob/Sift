import Foundation
import Combine
import SwiftData
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

public final class BackgroundFeedScheduler: ObservableObject {
    public static let shared = BackgroundFeedScheduler()

    #if os(iOS)
    /// Identifier registered in Info.plist under BGTaskSchedulerPermittedIdentifiers
    public static let backgroundTaskIdentifier = "io.github.zaryob.sift.refresh"
    #endif

    private var timerTask: Task<Void, Never>?
    private let refreshService = FeedRefreshService()

    @Published public var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "feedRefreshIntervalMinutes")
            scheduleNextRefresh()
        }
    }

    private init() {
        let stored = UserDefaults.standard.integer(forKey: "feedRefreshIntervalMinutes")
        self.refreshIntervalMinutes = stored > 0 ? stored : 15
        scheduleNextRefresh()
    }

    public func syncOnLaunch() {
        print("[BackgroundFeedScheduler] Synchronizing background timers on launch...")
        scheduleNextRefresh()
    }

    /// In-process timer that only keeps refreshing while the app is actually running
    /// (foreground or briefly backgrounded). On iOS this is not sufficient once the app
    /// is suspended or terminated — see scheduleAppRefresh() for the real background path.
    public func scheduleNextRefresh() {
        timerTask?.cancel()

        guard refreshIntervalMinutes > 0 else { return }

        let interval = TimeInterval(refreshIntervalMinutes * 60)

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                print("Executing background feed refresh...")
                await refreshService.refreshAllFeeds()
            }
        }
    }

    #if os(iOS)
    /// Submits (or re-submits) a BGAppRefreshTaskRequest so iOS can wake the app to
    /// refresh feeds even while it's suspended or not running at all.
    public func scheduleAppRefresh() {
        guard refreshIntervalMinutes > 0 else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(refreshIntervalMinutes * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundFeedScheduler] Failed to schedule BGAppRefreshTask: \(error)")
        }
    }

    /// Invoked by SwiftUI's `.backgroundTask(.appRefresh(identifier))` when iOS wakes the app.
    public func performBackgroundRefresh() async {
        // Immediately queue the next occurrence so the refresh cycle keeps going.
        scheduleAppRefresh()
        await refreshService.refreshAllFeeds()
        await MainActor.run {
            WidgetSnapshotManager.shared.updateSnapshot(context: PersistenceController.shared.container.mainContext)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    #endif
}
