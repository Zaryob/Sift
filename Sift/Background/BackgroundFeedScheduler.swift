import Foundation
import Combine
import SwiftData

public final class BackgroundFeedScheduler: ObservableObject {
    public static let shared = BackgroundFeedScheduler()
    
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
}
