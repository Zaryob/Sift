import SwiftUI
import SwiftData

struct MenuBarExtraView: View {
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var articles: [FeedItem]
    private let refreshService = FeedRefreshService()

    private var unreadArticles: [FeedItem] {
        articles.filter { !$0.isRead }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Sift RSS Reader")
                    .font(.headline)
                Spacer()
                Text("\(unreadArticles.count) Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if unreadArticles.isEmpty {
                Text("No unread articles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                Text("Latest Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(unreadArticles.prefix(5)) { item in
                    Button {
                        if let link = item.link, let url = URL(string: link) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                                .font(.body)
                            if let feedTitle = item.feed?.title {
                                Text(feedTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Refresh Feeds") {
                Task {
                    await refreshService.refreshAllFeeds()
                }
            }

            Button("Open Reader Window") {
                WindowCloseHandler.shared.showMainWindow()
            }

            Divider()

            Button("Quit Sift") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}
