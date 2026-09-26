import SwiftUI
import SwiftData

/// A publication-date range applied on top of whatever the sidebar selected.
enum TimeScope: String, CaseIterable, Identifiable {
    case anyTime = "Any Time"
    case today = "Today"
    case week = "Past 7 Days"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .anyTime:
            return true
        case .today:
            return Calendar.current.isDateInToday(date)
        case .week:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return date >= sevenDaysAgo
        }
    }
}

private enum DaySection: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case earlier = "Earlier"

    init(for date: Date) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else {
            self = .earlier
        }
    }
}

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var hideRead = false
    @State private var timeScope: TimeScope = .anyTime
    @State private var isConfirmingMarkAllRead = false
    @AppStorage(ReadingPreferenceKey.markReadBehavior) private var markReadRaw: String = MarkReadBehavior.whenOpened.rawValue
    @AppStorage(ReadingPreferenceKey.density) private var densityRaw: String = ArticleDensity.comfortable.rawValue

    private var markReadBehavior: MarkReadBehavior {
        MarkReadBehavior(rawValue: markReadRaw) ?? .whenOpened
    }

    private var density: ArticleDensity {
        ArticleDensity(rawValue: densityRaw) ?? .comfortable
    }

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
            guard !(hideRead && article.isRead), timeScope.includes(article.publicationDate) else { return false }

            if searchText.isEmpty { return true }
            let query = searchText.lowercased()
            let titleMatch = article.title.lowercased().contains(query)
            let authorMatch = article.author?.lowercased().contains(query) ?? false
            let summaryMatch = article.summary?.lowercased().contains(query) ?? false
            return titleMatch || authorMatch || summaryMatch
        }
    }

    private var daySections: [(section: DaySection, articles: [FeedItem])] {
        let grouped = Dictionary(grouping: filteredArticles) { DaySection(for: $0.publicationDate) }
        return DaySection.allCases.compactMap { section in
            guard let articles = grouped[section], !articles.isEmpty else { return nil }
            return (section, articles)
        }
    }

    private var titleForSelection: String {
        switch viewModel.selectedSidebarItem {
        case .all, .none: return "All Articles"
        case .unread: return "Unread"
        case .starred: return "Starred"
        case .feed:
            return selectedFeed?.title ?? "Feed"
        }
    }

    private var subtitle: String {
        if viewModel.isRefreshing {
            return "Refreshing…"
        }
        var parts: [String] = []
        if timeScope != .anyTime { parts.append(timeScope.rawValue) }
        if hideRead { parts.append("Unread only") }
        parts.append(unreadCount > 0 ? "\(unreadCount) unread" : "All caught up")
        return parts.joined(separator: " · ")
    }

    private var unreadCount: Int {
        filteredArticles.filter { !$0.isRead }.count
    }

    var body: some View {
        List(selection: $viewModel.selectedArticle) {
            if let error = selectedFeed?.refreshError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ForEach(daySections, id: \.section) { group in
                Section(group.section.rawValue) {
                    ForEach(group.articles) { article in
                        articleLink(article)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
        .refreshable {
            await viewModel.refreshAll(context: modelContext)
        }
        .task(id: viewModel.selectedArticle?.id) {
            await markSelectedArticleReadIfNeeded()
        }
        .overlay {
            if filteredArticles.isEmpty {
                emptyStateView
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search articles")
        .navigationTitle(titleForSelection)
        .navigationSubtitle(subtitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isConfirmingMarkAllRead = true
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                .disabled(unreadCount == 0)
                .help("Mark all articles in this list as read")
                .confirmationDialog(
                    "Mark \(unreadCount) articles as read?",
                    isPresented: $isConfirmingMarkAllRead,
                    titleVisibility: .visible
                ) {
                    Button("Mark \(unreadCount) as Read", role: .destructive) {
                        viewModel.markAllAsRead(in: filteredArticles, context: modelContext)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Only articles in “\(titleForSelection)” with the current filters are affected.")
                }
            }
        }
        .background {
            keyboardShortcuts
        }
    }

    private func articleLink(_ article: FeedItem) -> some View {
        NavigationLink(value: article) {
            ArticleRow(article: article, density: density)
        }
        .tag(article)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circlebadge" : "checkmark")
            }
            .tint(Color.siftAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                article.isStarred.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star")
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

    private var isFiltered: Bool {
        hideRead || timeScope != .anyTime
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Hide Read Articles", systemImage: "circlebadge", isOn: $hideRead.animation(.easeInOut(duration: 0.15)))
            Section("Published") {
                Picker("Published", selection: $timeScope.animation(.easeInOut(duration: 0.15))) {
                    ForEach(TimeScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            if isFiltered {
                Divider()
                Button("Clear Filters", systemImage: "xmark.circle") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hideRead = false
                        timeScope = .anyTime
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter articles")
    }

    private func markSelectedArticleReadIfNeeded() async {
        guard let article = viewModel.selectedArticle, !article.isRead else { return }
        switch markReadBehavior {
        case .manually:
            return
        case .afterDelay:
            // Cancelled automatically if the selection changes (e.g. the user backs out quickly).
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, viewModel.selectedArticle?.id == article.id else { return }
        case .whenOpened:
            break
        }
        article.isRead = true
        try? modelContext.save()
    }

    private var keyboardShortcuts: some View {
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
                if unreadCount > 0 {
                    isConfirmingMarkAllRead = true
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if hideRead || viewModel.selectedSidebarItem == .unread {
            ContentUnavailableView(
                "All Caught Up",
                systemImage: "checkmark.circle",
                description: Text("Nothing new to sift through.")
            )
        } else if viewModel.selectedSidebarItem == .starred {
            ContentUnavailableView(
                "No Starred Articles",
                systemImage: "star",
                description: Text("Star articles to keep them here.")
            )
        } else {
            ContentUnavailableView(
                "No Articles",
                systemImage: "doc.text",
                description: Text(timeScope == .anyTime ? "Pull to refresh or add a feed." : "Nothing published in this time range.")
            )
        }
    }
}

struct ArticleRow: View {
    let article: FeedItem
    let density: ArticleDensity

    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var dotBaselineOffset: CGFloat = 5
    @ScaledMetric(relativeTo: .body) private var gutter: CGFloat = 14

    private var snippet: String {
        HTMLSanitizer.stripTags(from: article.summary ?? article.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only meaningful when the feed ships full content; a summary would always read "1 min".
    private var readingMinutes: Int? {
        guard let content = article.content else { return nil }
        let words = HTMLSanitizer.stripTags(from: content).split(whereSeparator: \.isWhitespace).count
        return words >= 200 ? Int((Double(words) / 200).rounded(.up)) : nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            unreadIndicator
                .frame(width: gutter, alignment: .leading)

            VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
                // Read is a state, not "disabled": weight and color step down, but never below
                // .secondary so read rows keep legible contrast.
                Text(article.title)
                    .font(.body.weight(article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(density == .compact ? 2 : 3)

                if density == .comfortable, !snippet.isEmpty {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                metadataLine
                    .padding(.top, density == .compact ? 0 : 2)
            }
        }
        .padding(.vertical, density == .compact ? 2 : 6)
    }

    @ViewBuilder
    private var unreadIndicator: some View {
        if article.isRead {
            Color.clear.frame(width: dotSize, height: dotSize)
        } else {
            Circle()
                .fill(Color.siftAccent)
                .frame(width: dotSize, height: dotSize)
                // Center the dot on the title's x-height instead of letting it sit on the baseline.
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + dotBaselineOffset }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 5) {
            if let feed = article.feed {
                FeedFaviconView(feed: feed, size: 14)
                Text(feed.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Text("·")
            Text(Self.compactAge(of: article.publicationDate))

            if density == .comfortable, let minutes = readingMinutes {
                Text("·")
                Text("\(minutes) min")
            }

            if article.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.siftStarred)
                    .imageScale(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// "now", "12m", "4h", "3d", then a short date; static, so the list doesn't tick.
    static func compactAge(of date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return String(localized: "now")
        case ..<3_600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3_600))h"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d"
        default:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
