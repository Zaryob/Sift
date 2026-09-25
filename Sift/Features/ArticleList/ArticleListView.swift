import SwiftUI
import SwiftData

enum ArticleFilter: String, CaseIterable, Identifiable {
    case all = "All Articles"
    case unread = "Unread Only"
    case starred = "Starred Only"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .unread: return "circle.fill"
        case .starred: return "star.fill"
        }
    }
}

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var articles: [FeedItem]
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterMode: ArticleFilter = .all

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

        // Apply secondary segmented filter (All / Unread / Starred)
        let modeFiltered: [FeedItem]
        switch filterMode {
        case .all:
            modeFiltered = baseArticles
        case .unread:
            modeFiltered = baseArticles.filter { !$0.isRead }
        case .starred:
            modeFiltered = baseArticles.filter { $0.isStarred }
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return modeFiltered
        } else {
            let query = searchText.lowercased()
            return modeFiltered.filter { item in
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

            // Filter status banner when a non-default filter is active
            if filterMode != .all {
                HStack(spacing: 6) {
                    Image(systemName: filterMode.icon)
                        .font(.caption2)
                        .foregroundStyle(filterMode == .unread ? Color.blue : Color.orange)
                    Text("Filtered by: \(filterMode.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filterMode = .all
                        }
                    } label: {
                        Text("Show All")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08))
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
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                article.isRead.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                article.isStarred.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star.fill")
                            }
                            .tint(.orange)
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
                            if let link = article.link, let url = URL(string: link) {
                                Button("Copy Article Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                }
                            }
                        }
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search articles")
            .overlay {
                if filteredArticles.isEmpty {
                    emptyStateView
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Filter Articles") {
                        ForEach(ArticleFilter.allCases) { filter in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    filterMode = filter
                                }
                            } label: {
                                if filterMode == filter {
                                    Label(filter.rawValue, systemImage: "checkmark")
                                } else {
                                    Label(filter.rawValue, systemImage: filter.icon)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filterMode == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filterMode == .all ? Color.secondary : Color.accentColor)
                }
                .help("Filter articles by status")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                .disabled(filteredArticles.isEmpty || !filteredArticles.contains(where: { !$0.isRead }))
                .help("Mark All Filtered Articles as Read")
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

    @ViewBuilder
    private var emptyStateView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView(
                "No Matching Articles",
                systemImage: "magnifyingglass",
                description: Text("No articles matched '\(searchText)'.")
            )
        } else if filterMode == .unread {
            ContentUnavailableView(
                "All Caught Up",
                systemImage: "checkmark.circle",
                description: Text("No unread articles in this view.")
            )
        } else if filterMode == .starred {
            ContentUnavailableView(
                "No Starred Articles",
                systemImage: "star",
                description: Text("Star important articles to save them here.")
            )
        } else {
            ContentUnavailableView(
                "No Articles",
                systemImage: "doc.text",
                description: Text("No articles found in this feed or selection.")
            )
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if let url = faviconURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        default:
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let desc = feed.feedDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Refresh this feed")

                    Button(action: onMarkAllAsRead) {
                        Label("Mark Read", systemImage: "checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Mark all articles in this feed as read")
                }
            }

            HStack(spacing: 10) {
                if let siteURLStr = feed.siteURL, let siteURL = URL(string: siteURLStr) {
                    Link(destination: siteURL) {
                        Label(siteURL.host ?? "Website", systemImage: "safari")
                            .font(.caption2)
                    }
                }

                if let lastRefresh = feed.lastSuccessfulRefresh {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text("Updated \(lastRefresh, style: .relative) ago")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(feed.unreadCount) unread • \(feed.items.count) total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = feed.refreshError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("Warning: \(error)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.yellow.opacity(0.12)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: "dot.radiowaves.up.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.orange)
        }
    }
}

struct ArticleRow: View {
    let article: FeedItem

    private var cleanSnippet: String {
        let raw = article.summary ?? article.content ?? ""
        let stripped = HTMLSanitizer.stripTags(from: raw)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: Unread indicator + Title + Star
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(article.isRead ? Color.clear : Color.blue)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)

                Text(article.title)
                    .font(.system(size: 13, weight: article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .padding(.top, 3)
                }
            }

            // Summary snippet preview
            if !cleanSnippet.isEmpty {
                Text(cleanSnippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.leading, 14)
            }

            // Metadata footer
            HStack(spacing: 6) {
                if let feedTitle = article.feed?.title {
                    Text(feedTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                Text(article.publicationDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 14)
        }
        .padding(.vertical, 3)
    }
}
