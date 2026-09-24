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

    // Foreground notification display callback
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Notification click response callback -> activate app & navigate to article via NotificationCenter
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            if let articleIDStr = userInfo["articleID"] as? String, let uuid = UUID(uuidString: articleIDStr) {
                NotificationCenter.default.post(name: NotificationManager.openArticleNotification, object: uuid)
            } else if let feedIDStr = userInfo["feedID"] as? String, let uuid = UUID(uuidString: feedIDStr) {
                NotificationCenter.default.post(name: NotificationManager.openFeedNotification, object: uuid)
            }
        }
        completionHandler()
    }

    /// Sends a local notification with optional website Favicon attachment and Article ID
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

        if let faviconURL = faviconURL {
            Task {
                var attachment: UNNotificationAttachment? = nil
                if let (data, response) = try? await URLSession.shared.data(from: faviconURL),
                   let httpResp = response as? HTTPURLResponse,
                   httpResp.statusCode == 200,
                   !data.isEmpty {
                    
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("favicon_\(UUID().uuidString).png")
                    
                    if let image = NSImage(data: data),
                       let tiffData = image.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                        try? pngData.write(to: fileURL)
                    } else {
                        try? data.write(to: fileURL)
                    }

                    attachment = try? UNNotificationAttachment(identifier: "favicon", url: fileURL, options: nil)
                }

                if let attachment = attachment {
                    content.attachments = [attachment]
                }
                self.scheduleRequest(content: content)
            }
        } else {
            scheduleRequest(content: content)
        }
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
