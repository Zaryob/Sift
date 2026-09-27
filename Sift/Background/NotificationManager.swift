import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

nonisolated public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationManager()
    
    public static let openArticleNotification = Notification.Name("SiftOpenArticleNotification")
    public static let openFeedNotification = Notification.Name("SiftOpenFeedNotification")
    public static let articleAlertsEnabledKey = "articleAlertsEnabled"

    private var areArticleAlertsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.articleAlertsEnabledKey) as? Bool ?? true
    }

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        cleanUpTemporaryAttachments()
    }

    private func cleanUpTemporaryAttachments() {
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files {
                let name = file.lastPathComponent
                if (name.hasPrefix("notif_") || name.hasPrefix("appicon_")) && name.hasSuffix(".png") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    /// Updates the unread count badge shown on the app icon (iOS Home Screen / macOS Dock).
    nonisolated public func updateBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Failed to set badge count: \(error)")
            }
        }
    }

    private var isRequestingAuth = false

    public func requestAuthorization() {
        guard !isRequestingAuth else { return }
        isRequestingAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            self?.isRequestingAuth = false
            if let error = error {
                print("Notification permission error: \(error)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }

    // Foreground notification display callback - allow banner, list, sound, and badge
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    // Notification click response callback -> activate existing window & navigate to article
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let articleIDStr = response.notification.request.content.userInfo["articleID"] as? String
        let feedIDStr = response.notification.request.content.userInfo["feedID"] as? String
        DispatchQueue.main.async {
            Platform.showMainWindow()
            
            if let articleIDStr,
               let url = URL(string: "rssreader://article/\(articleIDStr)") {
                NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
            } else if let feedIDStr,
                      let url = URL(string: "rssreader://feed/\(feedIDStr)") {
                NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
            }
        }
        completionHandler()
    }

    /// Sends an individual notification for a single newly arrived article
    nonisolated public func sendArticleNotification(
        articleTitle: String,
        feedTitle: String,
        articleID: UUID,
        feedID: UUID,
        faviconURL: URL? = nil
    ) {
        guard areArticleAlertsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = feedTitle
        content.body = articleTitle
        content.sound = .default
        content.userInfo = [
            "articleID": articleID.uuidString,
            "feedID": feedID.uuidString
        ]

        Task {
            if let attachment = await createNotificationAttachment(from: faviconURL) {
                content.attachments = [attachment]
            }
            self.scheduleRequest(content: content)
        }
    }

    /// Legacy collective notification helper
    public func sendNewArticlesNotification(
        count: Int,
        feedTitle: String,
        latestArticleTitle: String,
        faviconURL: URL? = nil,
        articleID: UUID? = nil,
        feedID: UUID? = nil
    ) {
        guard count > 0, areArticleAlertsEnabled else { return }

        let content = UNMutableNotificationContent()
        if count == 1 {
            content.title = feedTitle
            content.body = latestArticleTitle
        } else {
            content.title = "\(feedTitle) (\(count) new articles)"
            content.body = latestArticleTitle
        }
        content.sound = .default

        var userInfo: [String: Any] = [:]
        if let articleID = articleID {
            userInfo["articleID"] = articleID.uuidString
        }
        if let feedID = feedID {
            userInfo["feedID"] = feedID.uuidString
        }
        content.userInfo = userInfo

        Task {
            if let attachment = await createNotificationAttachment(from: faviconURL) {
                content.attachments = [attachment]
            }
            self.scheduleRequest(content: content)
        }
    }

    /// Creates a notification attachment from a decoded feed favicon. ImageIO is
    /// used directly because AppKit can raise an Objective-C exception when a
    /// named or vector-backed NSImage has no bitmap image representation.
    private func createNotificationAttachment(from faviconURL: URL?) async -> UNNotificationAttachment? {
        guard let faviconURL,
           let data = await FaviconManager.shared.faviconData(for: faviconURL),
           !data.isEmpty,
           let pngData = Self.validatedPNGData(from: data) else { return nil }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif_\(UUID().uuidString).png")
        do {
            try pngData.write(to: fileURL, options: .atomic)
            return try UNNotificationAttachment(
                identifier: UUID().uuidString,
                url: fileURL,
                options: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            print("Failed to create notification image attachment: \(error)")
            return nil
        }
    }

    private static func validatedPNGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func scheduleRequest(content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            } else {
                print("Successfully posted notification with content: \(content.title)")
            }
        }
    }
}
