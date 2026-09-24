import SwiftUI
import SwiftData

struct MenuBarExtraView: View {
    @Query private var articles: [FeedItem]
    private let refreshService = FeedRefreshService()
    @Environment(\.openWindow) private var openWindow

    private var unreadCount: Int {
        articles.filter { !$0.isRead }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sift RSS Reader")
                .font(.headline)
            
            Text("\(unreadCount) Unread Articles")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Refresh Now") {
                Task {
                    await refreshService.refreshAllFeeds()
                }
            }

            Button("Open Reader") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }

            Divider()

            Button("Quit Sift") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}
