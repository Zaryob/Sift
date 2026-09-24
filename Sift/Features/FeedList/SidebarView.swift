import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext

    private var totalUnreadCount: Int {
        allArticles.filter { !$0.isRead }.count
    }

    private var unreadArticlesCount: Int {
        allArticles.filter { !$0.isRead }.count
    }

    private var starredArticlesCount: Int {
        allArticles.filter { $0.isStarred }.count
    }

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            Section("Smart Filters") {
                NavigationLink(value: SidebarItem.all) {
                    Label {
                        HStack {
                            Text("All Articles")
                            Spacer()
                            if totalUnreadCount > 0 {
                                Text("\(totalUnreadCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }
                        }
                    } icon: {
                        Image(systemName: "tray.full")
                    }
                }

                NavigationLink(value: SidebarItem.unread) {
                    Label {
                        HStack {
                            Text("Unread")
                            Spacer()
                            if unreadArticlesCount > 0 {
                                Text("\(unreadArticlesCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.2)))
                            }
                        }
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink(value: SidebarItem.starred) {
                    Label {
                        HStack {
                            Text("Starred")
                            Spacer()
                            if starredArticlesCount > 0 {
                                Text("\(starredArticlesCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                            }
                        }
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                ForEach(feeds) { feed in
                    NavigationLink(value: SidebarItem.feed(feed.id)) {
                        HStack(spacing: 8) {
                            FeedFaviconView(feed: feed)

                            Text(feed.title)
                                .lineLimit(1)

                            Spacer()

                            let count = feed.unreadCount
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }
                        }
                    }
                    .contextMenu {
                        Button("Refresh Feed") {
                            Task {
                                try? await FeedRefreshService().refreshFeed(id: feed.id)
                            }
                        }
                        Divider()
                        Button("Delete Feed", role: .destructive) {
                            viewModel.deleteFeed(feed, context: modelContext)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Feeds")
                    Spacer()
                    Button {
                        viewModel.isAddingFeed = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refreshAllFeeds()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
    }
}

struct FeedFaviconView: View {
    let feed: Feed
    
    private var faviconURL: URL? {
        FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)
    }

    var body: some View {
        if let url = faviconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                default:
                    Image(systemName: "rss")
                        .foregroundStyle(.orange)
                        .frame(width: 16, height: 16)
                }
            }
        } else {
            Image(systemName: "rss")
                .foregroundStyle(.orange)
                .frame(width: 16, height: 16)
        }
    }
}
