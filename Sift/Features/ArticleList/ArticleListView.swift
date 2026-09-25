import SwiftUI
import SwiftData

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

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

/// Time is a scope over whatever the sidebar selected, not a sibling of Library/Feeds.
enum TimeScope: String, CaseIterable, Identifiable {
    case latest = "Latest"
    case today = "Today"
    case week = "This Week"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .latest:
            return true
        case .today:
            return Calendar.current.isDateInToday(date)
        case .week:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return date >= sevenDaysAgo
        }
    }
}

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var filterMode: ArticleFilter = .all
    @State private var timeScope: TimeScope = .latest

    private var selectedFeed: Feed? {
        guard let item = viewModel.selectedSidebarItem, case .feed(let id) = item else { return nil }
        return allArticles.first(where: { $0.feed?.id == id })?.feed
    }

    private var sourceArticles: [FeedItem] {
        guard let item = viewModel.selectedSidebarItem else { return [] }
        switch item {
        case .all:
            return allArticles
        case .unread:
            return allArticles.filter { !$0.isRead }
        case .starred:
            return allArticles.filter { $0.isStarred }
        case .feed(let feedID):
            return allArticles.filter { $0.feed?.id == feedID }
        }
    }

    private var filteredArticles: [FeedItem] {
        sourceArticles.filter { article in
            // Filter by read/starred state
            let matchesFilter: Bool
            switch filterMode {
            case .all:
                matchesFilter = true
            case .unread:
                matchesFilter = !article.isRead
            case .starred:
                matchesFilter = article.isStarred
            }

            guard matchesFilter, timeScope.includes(article.publicationDate) else { return false }

            // Filter by search query
            if searchText.isEmpty { return true }
            let query = searchText.lowercased()
            let titleMatch = article.title.lowercased().contains(query)
            let authorMatch = article.author?.lowercased().contains(query) ?? false
            let summaryMatch = article.summary?.lowercased().contains(query) ?? false
            return titleMatch || authorMatch || summaryMatch
        }
    }

    private var titleForSelection: String {
        switch viewModel.selectedSidebarItem {
        case .all, .none: return "All Articles"
        case .unread: return "Unread"
        case .starred: return "Starred"
        case .feed:
            if let feed = selectedFeed {
                return feed.title
            }
            return "Feed"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header if a specific feed is selected
            if let feed = selectedFeed {
                FeedDetailsHeaderView(feed: feed) {
                    Task {
                        try? await FeedRefreshService().refreshFeed(id: feed.id)
                    }
                } onMarkAllAsRead: {
                    viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                }
                Divider()
            }

            // Filter mode indicator bar if non-default
            if isScoped {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text(scopeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filterMode = .all
                            timeScope = .latest
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
                    NavigationLink(value: article) {
                        ArticleRow(article: article)
                    }
                    .tag(article)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.openArticleExternally(article)
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
                        .tint(Color.siftStarred)
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
                                Platform.copyToPasteboard(url.absoluteString)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: viewModel.selectedArticle) { _, newArticle in
                if let article = newArticle, !article.isRead {
                    article.isRead = true
                    try? modelContext.save()
                }
            }
            .overlay {
                if filteredArticles.isEmpty {
                    emptyStateView
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search articles")
        #if os(iOS)
        .toolbarTitleMenu {
            scopeMenuContent
        }
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    scopeMenuContent
                } label: {
                    Label("Filter", systemImage: isScoped ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Filter articles by status and time")
            }
            #endif

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
        .labelStyle(.iconOnly)
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var isScoped: Bool {
        filterMode != .all || timeScope != .latest
    }

    private var scopeDescription: String {
        [filterMode != .all ? filterMode.rawValue : nil, timeScope != .latest ? timeScope.rawValue : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var scopeMenuContent: some View {
        Picker("Show", selection: $filterMode.animation(.easeInOut(duration: 0.15))) {
            ForEach(ArticleFilter.allCases) { filter in
                Label(filter.rawValue, systemImage: filter.icon).tag(filter)
            }
        }
        Picker("Time", selection: $timeScope.animation(.easeInOut(duration: 0.15))) {
            ForEach(TimeScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
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
                        Text("Updated \(relativeDateFormatter.localizedString(for: lastRefresh, relativeTo: Date()))")
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
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: "dot.radiowaves.up.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentColor)
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
        VStack(alignment: .leading, spacing: 5) {
            // Header: Unread indicator + Title + Star
            HStack(alignment: .top, spacing: 8) {
                if !article.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                }

                Text(article.title)
                    .font(.body.weight(article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if article.isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Color.siftStarred)
                        .padding(.top, 3)
                }
            }

            // Summary snippet preview
            if !cleanSnippet.isEmpty {
                Text(cleanSnippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, article.isRead ? 0 : 16)
            }

            // Metadata footer
            HStack(spacing: 6) {
                if let feedTitle = article.feed?.title {
                    Text(feedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(article.publicationDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, article.isRead ? 0 : 16)
        }
        .padding(.vertical, 4)
    }
}
