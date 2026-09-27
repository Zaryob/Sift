import Foundation
import Combine

/// Safe, sandbox-compliant adapter that redirects legacy LaunchAgent invocations
/// to `BackgroundFeedScheduler` (`NSBackgroundActivityScheduler` on macOS, `BGTaskScheduler` on iOS).
/// Does not use `Process()` or unsandboxed filesystem paths.
public final class LaunchAgentManager: ObservableObject {
    public static let shared = LaunchAgentManager()

    @Published public var isEnabled: Bool = true
    @Published public var intervalSeconds: Int = 900

    private init() {
        let storedMinutes = UserDefaults.standard.integer(forKey: "feedRefreshIntervalMinutes")
        self.intervalSeconds = (storedMinutes > 0 ? storedMinutes : 15) * 60
        self.isEnabled = UserDefaults.standard.object(forKey: "backgroundRefreshEnabled") as? Bool ?? true
    }

    public func syncOnLaunch() {
        // Sandboxed background scheduling is delegated directly to BackgroundFeedScheduler
        BackgroundFeedScheduler.shared.syncOnLaunch()
    }

    public func setEnabled(_ enabled: Bool, intervalMinutes: Int = 15) {
        self.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "backgroundRefreshEnabled")
        if enabled {
            BackgroundFeedScheduler.shared.refreshIntervalMinutes = max(5, intervalMinutes)
        } else {
            BackgroundFeedScheduler.shared.refreshIntervalMinutes = 0
        }
    }
}
