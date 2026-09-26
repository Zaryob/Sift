import SwiftUI
import SwiftData

enum ArticleSortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"

    var id: String { rawValue }
}

private enum TimelineSection: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "Earlier This Week"
    case older = "Older"

    init(for date: Date) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else {
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            if date >= weekAgo {
                self = .thisWeek
            } else {
                self = .older
            }
        }
    }
}

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var allArticles: [FeedItem]
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var activeScope: ArticleScope = .all
    @State private var hideRead = false
    @State private var sortOrder: ArticleSortOrder = .newestFirst
    @State private var isConfirmingMarkAllRead = false
    @State private var showToast = false

    @AppStorage(ReadingPreferenceKey.density) private var densityRaw: String = ArticleDensity.comfortable.rawValue
    @AppStorage(ReadingPreferenceKey.showFeedIcons) private var showFeedIcons: Bool = true
    @AppStorage(ReadingPreferenceKey.showArticlePreviews) private var showArticlePreviews: Bool = true
    @AppStorage(ReadingPreferenceKey.markReadBehavior) private var markReadRaw: String = MarkReadBehavior.whenOpened.rawValue

    private var density: ArticleDensity {
        ArticleDensity(rawValue: densityRaw) ?? .comfortable
    }

    private var markReadBehavior: MarkReadBehavior {
        MarkReadBehavior(rawValue: markReadRaw) ?? .whenOpened
    }

    // MARK: - Filtered Articles

    private var sourceArticles: [FeedItem] {
        if case .feed(let feedID) = viewModel.selectedSidebarItem {
            return allArticles.filter { $0.feed?.id == feedID }
        }

        switch activeScope {
        case .all:
            return allArticles
        case .unread:
            return allArticles.filter { !$0.isRead }
        case .starred:
            return allArticles.filter { $0.isStarred }
        case .today:
            return allArticles.filter { Calendar.current.isDateInToday($0.publicationDate) }
        }
    }

    private var filteredArticles: [FeedItem] {
        let articles = sourceArticles.filter { article in
            if hideRead && article.isRead { return false }
            if searchText.isEmpty { return true }
            let query = searchText.lowercased()
            let titleMatch = article.title.lowercased().contains(query)
            let authorMatch = article.author?.lowercased().contains(query) ?? false
            let summaryMatch = article.summary?.lowercased().contains(query) ?? false
            let feedMatch = article.feed?.title.lowercased().contains(query) ?? false
            return titleMatch || authorMatch || summaryMatch || feedMatch
        }

        switch sortOrder {
        case .newestFirst:
            return articles.sorted { $0.publicationDate > $1.publicationDate }
        case .oldestFirst:
            return articles.sorted { $0.publicationDate < $1.publicationDate }
        }
    }

    private var timelineSections: [(section: TimelineSection, articles: [FeedItem])] {
        let grouped = Dictionary(grouping: filteredArticles) { TimelineSection(for: $0.publicationDate) }
        return TimelineSection.allCases.compactMap { section in
            guard let articles = grouped[section], !articles.isEmpty else { return nil }
            return (section, articles)
        }
    }

    private var totalUnreadCount: Int {
        allArticles.filter { !$0.isRead }.count
    }

    private var currentScopeUnreadCount: Int {
        sourceArticles.filter { !$0.isRead }.count
    }

    private var currentFeedTitle: String? {
        if case .feed(let feedID) = viewModel.selectedSidebarItem {
            return feeds.first(where: { $0.id == feedID })?.title
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            List(selection: $viewModel.selectedArticle) {
                // Header Area on iOS (Brand Logotype + Live Status + Filter Bar)
                #if os(iOS)
                Section {
                    headerContent
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                #endif

                if let currentFeed = selectedFeedItem, let error = currentFeed.refreshError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                }

                if filteredArticles.isEmpty {
                    Section {
                        emptyStateView
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .padding(.top, 40)
                    }
                } else {
                    ForEach(timelineSections, id: \.section) { group in
                        Section {
                            ForEach(group.articles) { article in
                                articleRowLink(article)
                                    .listRowInsets(EdgeInsets(
                                        top: density == .compact ? 8 : (density == .spacious ? 14 : 11),
                                        leading: 16,
                                        bottom: density == .compact ? 8 : (density == .spacious ? 14 : 11),
                                        trailing: 16
                                    ))
                                    .listRowSeparator(.visible)
                            }
                        } header: {
                            Text(group.section.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                                .padding(.top, 4)
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
            #if os(iOS)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search articles, feeds…")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .searchable(text: $searchText, prompt: "Search articles, feeds…")
            .navigationTitle(currentFeedTitle ?? "Sift")
            #endif
            .toolbar {
                toolbarItems
            }
            .confirmationDialog(
                "Mark All as Read?",
                isPresented: $isConfirmingMarkAllRead,
                titleVisibility: .visible
            ) {
                Button("Mark as Read") {
                    viewModel.markAllAsRead(in: sourceArticles, context: modelContext)
                    showUndoToast()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Mark \(currentScopeUnreadCount) unread articles in this view as read?")
            }
            .sheet(isPresented: $viewModel.isShowingManageFeeds) {
                ManageSourcesSheet(viewModel: viewModel)
            }
            .background {
                keyboardShortcuts
            }

            // Undo Toast
            if showToast, let message = viewModel.toastMessage {
                undoToastView(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var selectedFeedItem: Feed? {
        if case .feed(let id) = viewModel.selectedSidebarItem {
            return feeds.first(where: { $0.id == id })
        }
        return nil
    }

    // MARK: - Header Content (Logotype, Status, Filter Pills)

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Logotype + Single Feed Back Button
            HStack(alignment: .firstTextBaseline) {
                if let feedTitle = currentFeedTitle {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedSidebarItem = .all
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("All Feeds")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.siftAccent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(feedTitle)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("Sift")
                        .font(.siftSerif(.largeTitle, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }

            // Status Line: e.g. "50 unread · Updated 2 min ago"
            statusLineView

            // Filter Bar Chips
            if currentFeedTitle == nil {
                filterBarView
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLineView: some View {
        HStack(spacing: 6) {
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Updating feeds…")
            } else {
                let unreadText = "\(totalUnreadCount) unread"
                let updatedText = updatedAgoString
                Text("\(unreadText) · \(updatedText)")
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(.secondary)
    }

    private var updatedAgoString: String {
        guard let last = viewModel.lastRefreshedAt else {
            return "Updated recently"
        }
        let seconds = Date().timeIntervalSince(last)
        if seconds < 60 {
            return "Updated just now"
        } else if seconds < 3600 {
            let mins = Int(seconds / 60)
            return "Updated \(mins)m ago"
        } else {
            let hours = Int(seconds / 3600)
            return "Updated \(hours)h ago"
        }
    }

    // MARK: - Filter Bar (Apple Mail category pills)

    private var filterBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ArticleScope.allCases) { scope in
                    filterChip(for: scope)
                }
            }
        }
    }

    private func filterChip(for scope: ArticleScope) -> some View {
        let isSelected = activeScope == scope
        let count: Int? = {
            switch scope {
            case .all: return nil
            case .unread: return totalUnreadCount > 0 ? totalUnreadCount : nil
            case .starred:
                let sc = allArticles.filter { $0.isStarred }.count
                return sc > 0 ? sc : nil
            case .today:
                let tc = allArticles.filter { Calendar.current.isDateInToday($0.publicationDate) }.count
                return tc > 0 ? tc : nil
            }
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                activeScope = scope
            }
        } label: {
            HStack(spacing: 5) {
                Text(scope.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))

                if let count {
                    Text(count.formatted())
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .opacity(isSelected ? 0.9 : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary)
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Article Row Link

    private func articleRowLink(_ article: FeedItem) -> some View {
        NavigationLink(value: article) {
            ArticleRow(
                article: article,
                density: density,
                showFeedIcon: showFeedIcons,
                showPreview: showArticlePreviews
            )
        }
        .tag(article)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    article.isRead.toggle()
                    try? modelContext.save()
                }
            } label: {
                Label(article.isRead ? "Unread" : "Read", systemImage: article.isRead ? "circle.fill" : "checkmark")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    article.isStarred.toggle()
                    try? modelContext.save()
                }
            } label: {
                Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star")
            }
            .tint(Color.siftStarred)

            Button {
                viewModel.openArticleExternally(article)
            } label: {
                Label("Browser", systemImage: "safari")
            }
            .tint(.gray)
        }
        .contextMenu {
            Button {
                viewModel.selectedArticle = article
            } label: {
                Label("Open", systemImage: "book")
            }

            Button {
                viewModel.openArticleExternally(article)
            } label: {
                Label("Open Original", systemImage: "safari")
            }

            Divider()

            Button {
                article.isStarred.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.slash" : "star")
            }

            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isRead ? "Mark as Unread" : "Mark as Read", systemImage: article.isRead ? "circle" : "checkmark.circle")
            }

            Divider()

            if let link = article.link, let url = URL(string: link) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    Platform.copyToPasteboard(url.absoluteString)
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Add Feed")

                moreOptionsMenu
            }
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.isAddingFeed = true
            } label: {
                Label("Add Feed", systemImage: "plus")
            }

            moreOptionsMenu
        }
        #endif
    }

    private var moreOptionsMenu: some View {
        Menu {
            Section {
                Button {
                    isConfirmingMarkAllRead = true
                } label: {
                    Label("Mark All as Read", systemImage: "checkmark.circle")
                }
                .disabled(currentScopeUnreadCount == 0)

                Button {
                    viewModel.refreshAllFeeds(context: modelContext)
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }

            Section("View Options") {
                Toggle("Show Feed Icons", isOn: $showFeedIcons)
                Toggle("Show Article Previews", isOn: $showArticlePreviews)
                Toggle("Hide Read Articles", isOn: $hideRead)

                Menu("Density") {
                    Picker("Density", selection: $densityRaw) {
                        ForEach(ArticleDensity.allCases) { d in
                            Text(d.rawValue).tag(d.rawValue)
                        }
                    }
                }

                Menu("Sort") {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(ArticleSortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                }
            }

            Section {
                Button {
                    viewModel.isShowingManageFeeds = true
                } label: {
                    Label("Manage Feeds…", systemImage: "folder")
                }

                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Options")
    }

    // MARK: - Undo Toast

    private func undoToastView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Button("Undo") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.undoMarkAllAsRead(context: modelContext)
                    showToast = false
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.siftAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }

    private func showUndoToast() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showToast = false
                }
            }
        }
    }

    private func markSelectedArticleReadIfNeeded() async {
        guard let article = viewModel.selectedArticle, !article.isRead else { return }
        switch markReadBehavior {
        case .manually:
            return
        case .afterDelay:
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, viewModel.selectedArticle?.id == article.id else { return }
        case .whenOpened:
            break
        }
        article.isRead = true
        try? modelContext.save()
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if feeds.isEmpty {
            VStack(spacing: 12) {
                Text("Sift")
                    .font(.siftSerif(.title, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Your feeds will appear here.\nAdd RSS feeds to build your own quiet, chronological news inbox.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.siftAccent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        } else if activeScope == .unread || hideRead {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.siftAccent)
                    .padding(.bottom, 4)

                Text("You’re all caught up.")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Nothing new to sift through right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("View All Articles") {
                    withAnimation {
                        activeScope = .all
                        hideRead = false
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.siftAccent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        } else if activeScope == .starred {
            VStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Text("No Starred Articles")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Star anything you want to return to later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                "No Articles",
                systemImage: "doc.text",
                description: Text("Pull to refresh or add feeds to populate your timeline.")
            )
        }
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
                if currentScopeUnreadCount > 0 {
                    isConfirmingMarkAllRead = true
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - Article Row (Apple Mail Density & Layout)

struct ArticleRow: View {
    let article: FeedItem
    let density: ArticleDensity
    var showFeedIcon: Bool = true
    var showPreview: Bool = true

    private var iconSize: CGFloat {
        switch density {
        case .compact: return 30
        case .comfortable: return 38
        case .spacious: return 42
        }
    }

    private var snippet: String {
        HTMLSanitizer.stripTags(from: article.summary ?? article.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var feedTitle: String {
        article.feed?.title ?? article.author ?? "Feed"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Unread dot
            ZStack(alignment: .top) {
                if !article.isRead {
                    Circle()
                        .fill(Color.siftAccent)
                        .frame(width: 7.5, height: 7.5)
                        .padding(.top, 4)
                }
            }
            .frame(width: 8)

            // Feed Favicon / Initial Monogram
            if showFeedIcon {
                if let feed = article.feed {
                    FeedFaviconView(feed: feed, size: iconSize, cornerRadius: iconSize * 0.22)
                } else {
                    FeedFaviconView(title: feedTitle, size: iconSize, cornerRadius: iconSize * 0.22)
                }
            }

            // Article Content: Header line, Title, Snippet
            VStack(alignment: .leading, spacing: density == .compact ? 2 : 3) {
                // Header: Feed Name + Timestamp
                HStack(alignment: .firstTextBaseline) {
                    Text(feedTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(formattedTime(for: article.publicationDate))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)

                    if article.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.siftStarred)
                    }
                }

                // Article Title
                Text(article.title.isEmpty ? "Untitled" : article.title)
                    .font(.system(size: 16, weight: article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? Color.secondary : Color.primary)
                    .lineSpacing(1.2)
                    .lineLimit(density == .compact ? 1 : 2)

                // Article Preview Snippet
                if showPreview, !snippet.isEmpty, density != .compact {
                    Text(snippet)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary.opacity(article.isRead ? 0.7 : 0.88))
                        .lineSpacing(1.1)
                        .lineLimit(density == .spacious ? 2 : 1)
                        .padding(.top, 1)
                }
            }
        }
    }

    private func formattedTime(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
