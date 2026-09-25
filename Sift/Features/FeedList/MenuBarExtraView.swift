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
                Label("Sift", systemImage: "dot.radiowaves.up.and.right")
                    .font(.headline)
                Spacer()
                if !unreadArticles.isEmpty {
                    Text("\(unreadArticles.count) Unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            Divider()

            if unreadArticles.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            } else {
                Text("Latest Unread")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(unreadArticles.prefix(6)) { item in
                    Button {
                        if let link = item.link, let url = URL(string: link) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                                .font(.body)

                            HStack(spacing: 4) {
                                if let feedTitle = item.feed?.title {
                                    Text(feedTitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(item.publicationDate, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                Task {
                    await refreshService.refreshAllFeeds()
                }
            } label: {
                Label("Refresh Feeds", systemImage: "arrow.clockwise")
            }

            Button {
                WindowActionTarget.shared.showMainWindow()
            } label: {
                Label("Open Sift", systemImage: "macwindow")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Divider()

            Button("Quit Sift") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.vertical, 4)
    }
}
