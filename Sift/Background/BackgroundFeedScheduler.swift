import Foundation
import Combine
import SwiftData
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

@MainActor
public final class BackgroundFeedScheduler: ObservableObject {
    public static let shared = BackgroundFeedScheduler()

    #if os(iOS)
    /// Identifier registered in Info.plist under BGTaskSchedulerPermittedIdentifiers
    public static let backgroundTaskIdentifier = "io.github.zaryob.sift.refresh"
    #endif

    #if os(macOS)
    private var macActivityScheduler: NSBackgroundActivityScheduler?
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
        print("[BackgroundFeedScheduler] Synchronizing background timers and activity scheduler on launch...")
        scheduleNextRefresh()
    }

    /// Schedules periodic feed refreshes across platforms using sandbox-compliant APIs.
    /// - On macOS: Runs in-process timer while active/in menu bar, plus NSBackgroundActivityScheduler.
    /// - On iOS: Runs in-process timer while active, plus BGAppRefreshTask when backgrounded.
    public func scheduleNextRefresh() {
        timerTask?.cancel()

        guard refreshIntervalMinutes > 0 else {
            #if os(macOS)
            macActivityScheduler?.invalidate()
            macActivityScheduler = nil
            #endif
            return
        }

        let interval = TimeInterval(refreshIntervalMinutes * 60)

        // 1. In-process timer for when app is open or running in MenuBar
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                print("[BackgroundFeedScheduler] Executing periodic feed refresh...")
                await refreshService.refreshAllFeeds()
            }
        }

        #if os(macOS)
        // 2. Sandboxed native macOS scheduler (NSBackgroundActivityScheduler)
        macActivityScheduler?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: "io.github.zaryob.sift.backgroundactivity")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = max(60, interval / 4)
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }
            if scheduler.shouldDefer {
                completion(.deferred)
                return
            }
            Task {
                await self.refreshService.refreshAllFeeds()
                completion(.finished)
            }
        }
        self.macActivityScheduler = scheduler
        #endif
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
    }
    #endif
}
