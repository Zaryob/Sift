import Foundation
import UserNotifications
import AppKit

public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    public static let openArticleNotification = Notification.Name("SiftOpenArticleNotification")
    public static let openFeedNotification = Notification.Name("SiftOpenFeedNotification")

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
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
        if #available(macOS 11.0, *) {
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
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            WindowActionTarget.shared.showMainWindow()
            
            if let articleIDStr = userInfo["articleID"] as? String,
               let url = URL(string: "rssreader://article/\(articleIDStr)") {
                NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
            } else if let feedIDStr = userInfo["feedID"] as? String,
                      let url = URL(string: "rssreader://feed/\(feedIDStr)") {
                NotificationCenter.default.post(name: .siftHandleDeepLink, object: url)
            }
        }
        completionHandler()
    }

    /// Sends an individual notification for a single newly arrived article
    public func sendArticleNotification(
        articleTitle: String,
        feedTitle: String,
        articleID: UUID,
        feedID: UUID,
        faviconURL: URL? = nil
    ) {
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
        guard count > 0 else { return }

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

    /// Creates a notification attachment from a feed's favicon, or falls back to the Sift app icon.
    private func createNotificationAttachment(from faviconURL: URL?) async -> UNNotificationAttachment? {
        let tempDir = FileManager.default.temporaryDirectory

        // 1. Try to download and convert remote favicon
        if let faviconURL = faviconURL {
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 2.5
            let session = URLSession(configuration: sessionConfig)

            if let (data, response) = try? await session.data(from: faviconURL),
               let httpResp = response as? HTTPURLResponse,
               (200...299).contains(httpResp.statusCode),
               !data.isEmpty {

                let fileURL = tempDir.appendingPathComponent("notif_\(UUID().uuidString).png")
                if let image = NSImage(data: data),
                   let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                    if let attachment = try? UNNotificationAttachment(identifier: UUID().uuidString, url: fileURL, options: nil) {
                        return attachment
                    }
                }
            }
        }

        // 2. Fallback to application brand icon as attachment if favicon is not available
        if let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName),
           let tiffData = appIcon.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            let fileURL = tempDir.appendingPathComponent("appicon_\(UUID().uuidString).png")
            try? pngData.write(to: fileURL)
            if let attachment = try? UNNotificationAttachment(identifier: UUID().uuidString, url: fileURL, options: nil) {
                return attachment
            }
        }

        return nil
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
