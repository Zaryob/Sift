import Foundation

/// Tracks how many promotional/sponsored articles Sift has kept out of the
/// user's library — either by never storing them at ingestion time, or by
/// sweeping them out of existing storage — so the app can occasionally show
/// off the number instead of it being invisible bookkeeping.
public enum PromotionalCleanupStats {
    private static let lifetimeCountKey = "promotionalCleanupLifetimeCount"
    private static let countAtLastPopupKey = "promotionalCleanupCountAtLastPopup"
    private static let lastPopupDateKey = "promotionalCleanupLastPopupDate"
    private static let popupInterval: TimeInterval = 7 * 24 * 60 * 60

    /// Total promotional/sponsored articles skipped or removed since install.
    public static var lifetimeCount: Int {
        UserDefaults.standard.integer(forKey: lifetimeCountKey)
    }

    /// Call once per batch (not per article) whenever promotional/sponsored
    /// articles are skipped at ingestion or deleted from existing storage.
    public static func recordCleaned(_ count: Int) {
        guard count > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: lifetimeCountKey) + count, forKey: lifetimeCountKey)
    }

    /// Returns how many articles were cleaned since the last time this was
    /// shown, but only once at least a week has passed and there's something
    /// new to report. Marks itself as shown as a side effect, so call this at
    /// most once per check (e.g. on launch) rather than from view re-renders.
    public static func popupCountIfDue(now: Date = Date()) -> Int? {
        let defaults = UserDefaults.standard
        let lastShown = defaults.object(forKey: lastPopupDateKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(lastShown) >= popupInterval else { return nil }

        let total = defaults.integer(forKey: lifetimeCountKey)
        let countAtLastPopup = defaults.integer(forKey: countAtLastPopupKey)
        let delta = total - countAtLastPopup
        guard delta > 0 else { return nil }

        defaults.set(total, forKey: countAtLastPopupKey)
        defaults.set(now, forKey: lastPopupDateKey)
        return delta
    }
}
