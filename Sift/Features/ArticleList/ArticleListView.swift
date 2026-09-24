import SwiftUI
import SwiftData

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var articles: [FeedItem]
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var selectedFeed: Feed? {
        if case .feed(let feedID) = viewModel.selectedSidebarItem {
            return feeds.first(where: { $0.id == feedID })
        }
        return nil
    }

    private var filteredArticles: [FeedItem] {
        let baseArticles: [FeedItem]
        switch viewModel.selectedSidebarItem {
        case .all, .none:
            baseArticles = articles
        case .today:
            baseArticles = articles.filter { Calendar.current.isDateInToday($0.publicationDate) }
        case .thisWeek:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            baseArticles = articles.filter { $0.publicationDate >= sevenDaysAgo }
        case .unread:
            baseArticles = articles.filter { !$0.isRead }
        case .starred:
            baseArticles = articles.filter { $0.isStarred }
        case .feed(let feedID):
            baseArticles = articles.filter { $0.feed?.id == feedID }
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseArticles
        } else {
            let query = searchText.lowercased()
            return baseArticles.filter { item in
                item.title.lowercased().contains(query) ||
                (item.summary?.lowercased().contains(query) ?? false) ||
                (item.feed?.title.lowercased().contains(query) ?? false)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Feed Details Header when a specific feed is selected
            if let feed = selectedFeed {
                FeedDetailsHeaderView(feed: feed, onRefresh: {
                    Task {
                        try? await FeedRefreshService().refreshFeed(id: feed.id)
                    }
                }, onMarkAllAsRead: {
                    viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                })
                Divider()
            }

            List(selection: $viewModel.selectedArticle) {
                ForEach(filteredArticles) { article in
                    ArticleRow(article: article)
                        .tag(article)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            viewModel.openArticleExternally(article)
                        }
                        .onTapGesture(count: 1) {
                            viewModel.selectedArticle = article
                            if !article.isRead {
                                article.isRead = true
                                try? modelContext.save()
                            }
                        }
                        .contextMenu {
                            Button(article.isRead ? "Mark as Unread" : "Mark as Read") {
                                article.isRead.toggle()
                                try? modelContext.save()
                            }
                            Button(article.isStarred ? "Unstar" : "Star") {
                                article.isStarred.toggle()
                                try? modelContext.save()
                            }
                            Divider()
                            Button("Open in Browser") {
                                viewModel.openArticleExternally(article)
                            }
                        }
                }
            }
            .searchable(text: $searchText, prompt: "Search articles")
            .overlay {
                if filteredArticles.isEmpty {
                    ContentUnavailableView(
                        "No Articles",
                        systemImage: "doc.text",
                        description: Text("No articles found in this selection.")
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                .disabled(filteredArticles.isEmpty || !filteredArticles.contains(where: { !$0.isRead }))
                .help("Mark All as Read")
            }
        }
        .background {
            Group {
                Button("") { viewModel.selectNextArticle(in: filteredArticles) }
                    .keyboardShortcut("j", modifiers: [])
                Button("") { viewModel.selectPreviousArticle(in: filteredArticles) }
                    .keyboardShortcut("k", modifiers: [])
                Button("") {
                    if let article = viewModel.selectedArticle {
                        article.isRead.toggle()
                        try? modelContext.save()
                    }
                }
                .keyboardShortcut("m", modifiers: [])
                Button("") {
                    if let article = viewModel.selectedArticle {
                        article.isStarred.toggle()
                        try? modelContext.save()
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                Button("") {
                    if let article = viewModel.selectedArticle {
                        viewModel.openArticleExternally(article)
                    }
                }
                .keyboardShortcut("o", modifiers: [])
                Button("") {
                    viewModel.refreshAllFeeds()
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("") {
                    viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .navigationTitle(titleForSelection)
    }

    private var titleForSelection: String {
        switch viewModel.selectedSidebarItem {
        case .all, .none: return "All Articles"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .unread: return "Unread"
        case .starred: return "Starred"
        case .feed:
            if let feed = selectedFeed {
                return feed.title
            }
            return "Feed"
        }
    }
}

struct FeedDetailsHeaderView: View {
    let feed: Feed
    let onRefresh: () -> Void
    let onMarkAllAsRead: () -> Void

    private var faviconURL: URL? {
        FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                if let url = faviconURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            Image(systemName: "rss.circle.fill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Image(systemName: "rss.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(feed.title)
                            .font(.headline)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: onMarkAllAsRead) {
                            Label("Mark All Read", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: onRefresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let desc = feed.feedDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let siteURLStr = feed.siteURL, let siteURL = URL(string: siteURLStr) {
                            Link(destination: siteURL) {
                                Label(siteURL.host ?? "Website", systemImage: "link")
                                    .font(.caption)
                            }
                        }

                        if let lastRefresh = feed.lastSuccessfulRefresh {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text("Updated \(lastRefresh, style: .relative) ago")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }

                        Text("• \(feed.unreadCount) unread (\(feed.items.count) total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = feed.refreshError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Refresh Warning: \(error)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.1)))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ArticleRow: View {
    let article: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(article.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(.body)
                        .fontWeight(article.isRead ? .regular : .semibold)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let feedTitle = article.feed?.title {
                            Text(feedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(article.publicationDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
