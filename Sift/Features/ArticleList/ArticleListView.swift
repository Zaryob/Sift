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
    @State private var isShowingFilters = false
    @State private var excludedFeedIDs: Set<UUID> = []

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

        let scopedArticles = switch activeScope {
        case .all:
            allArticles
        case .unread:
            allArticles.filter { !$0.isRead }
        case .starred:
            allArticles.filter { $0.isStarred }
        case .today:
            allArticles.filter { Calendar.current.isDateInToday($0.publicationDate) }
        }

        return scopedArticles.filter { article in
            guard let feedID = article.feed?.id else { return true }
            return !excludedFeedIDs.contains(feedID)
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
                // The title and status live in the navigation bar (so search can slot in under the
                // large title); only the scope chips are list content, and only on the home timeline.
                #if os(iOS)
                if currentFeedTitle == nil {
                    Section {
                        filterBarView
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
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
            .navigationTitle(currentFeedTitle ?? "Sift")
            .navigationSubtitle(statusText)
            #if os(iOS)
            // On iPhone, toolbar placement gives search the same bottom-bar presentation as Mail.
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search articles, feeds…")
            .searchToolbarBehavior(hasActiveFilters ? .minimize : .automatic)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            // The standard back button (to Sidebar/"Sift") remains visible while searching.
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $viewModel.isShowingSettings) {
                SettingsView()
            }
            #else
            .searchable(text: $searchText, prompt: "Search articles, feeds…")
            #endif
            .toolbar {
                toolbarItems
            }
            .onChange(of: viewModel.selectedSidebarItem) { _, item in
                // Library rows selected from the Sidebar map onto the home scopes.
                switch item {
                case .all: activeScope = .all
                case .unread: activeScope = .unread
                case .starred: activeScope = .starred
                case .feed, .none: break
                }
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
            .sheet(isPresented: $isShowingFilters) {
                ArticleFiltersSheet(
                    activeScope: $activeScope,
                    excludedFeedIDs: $excludedFeedIDs,
                    feeds: feeds
                )
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

    // MARK: - Status

    /// "46 unread · Updated just now"; inside a feed, the unread count is that feed's.
    private var statusText: String {
        if viewModel.isRefreshing {
            return String(localized: "Updating feeds…")
        }
        let unread = currentFeedTitle == nil ? totalUnreadCount : currentScopeUnreadCount
        return "\(String(localized: "\(unread) unread")) · \(updatedAgoString)"
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
        let selectionColor: Color = switch scope {
        case .all: .primary
        case .unread: .blue
        case .starred: .pink
        case .today: .green
        }
        let symbolName: String = switch scope {
        case .all: "tray.full"
        case .unread: "circle.fill"
        case .starred: "star.fill"
        case .today: "calendar"
        }
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
            withAnimation(.smooth(duration: 0.24)) {
                activeScope = scope
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))

                if isSelected {
                    Text(scope.rawValue)
                        .font(.system(size: 16, weight: .semibold))

                    if let count {
                        Text(count.formatted())
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .opacity(0.85)
                    }
                }
            }
            .frame(minWidth: 24)
            .padding(.horizontal, isSelected ? 16 : 12)
            .padding(.vertical, 11)
            .background {
                if isSelected {
                    Capsule()
                        .fill(selectionColor)
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.secondary))
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
                showPreview: showArticlePreviews,
                // In a single feed the source is already the nav title; repeating it on every
                // row is just noise, so the row can spend that space on the article itself.
                showSource: currentFeedTitle == nil
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

        ToolbarItem(placement: .bottomBar) {
            Button {
                isShowingFilters = true
            } label: {
                ArticleFilterToolbarLabel(
                    isActive: hasActiveFilters,
                    summary: filterSummaryText
                )
            }
            .accessibilityLabel("Article Filters")
        }

        DefaultToolbarItem(kind: .search, placement: .bottomBar)
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

    private var filterSummaryText: String {
        guard !excludedFeedIDs.isEmpty else { return activeScope.rawValue }
        let noun = excludedFeedIDs.count == 1 ? "feed" : "feeds"
        return "\(activeScope.rawValue) · \(excludedFeedIDs.count) \(noun) excluded"
    }

    private var hasActiveFilters: Bool {
        activeScope != .all || !excludedFeedIDs.isEmpty
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

#if os(iOS)
private struct ArticleFilterToolbarLabel: View {
    let isActive: Bool
    let summary: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: isActive ? 17 : 17, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: isActive ? 40 : 20, height: isActive ? 40 : 20)
                .background {
                    Circle()
                        .fill(
                            isActive
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(.clear)
                        )
                }

            if isActive {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Filtered by")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
        }
        .frame(minWidth: isActive ? 170 : 20, alignment: .leading)
    }
}

private struct ArticleFiltersSheet: View {
    @Binding var activeScope: ArticleScope
    @Binding var excludedFeedIDs: Set<UUID>
    let feeds: [Feed]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Include Articles") {
                    filterRow(scope: .all, title: "All Articles", systemImage: "tray.full")
                    filterRow(scope: .unread, title: "Unread", systemImage: "envelope.badge")
                    filterRow(scope: .starred, title: "Starred", systemImage: "star")
                    filterRow(scope: .today, title: "Published Today", systemImage: "calendar")
                }

                if !feeds.isEmpty {
                    Section("Include Feeds From") {
                        ForEach(feeds) { feed in
                            Button {
                                toggleFeed(feed.id)
                            } label: {
                                HStack {
                                    Label(feed.title, systemImage: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if !excludedFeedIDs.contains(feed.id) {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                if activeScope != .all || !excludedFeedIDs.isEmpty {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            activeScope = .all
                            excludedFeedIDs.removeAll()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func filterRow(scope: ArticleScope, title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            activeScope = scope
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if activeScope == scope {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func toggleFeed(_ id: UUID) {
        if excludedFeedIDs.contains(id) {
            excludedFeedIDs.remove(id)
        } else {
            excludedFeedIDs.insert(id)
        }
    }
}
#endif

// MARK: - Article Row (Apple Mail Density & Layout)

struct ArticleRow: View {
    let article: FeedItem
    let density: ArticleDensity
    var showFeedIcon: Bool = true
    var showPreview: Bool = true
    /// False inside a single feed's list, where the feed name is already the screen's nav title.
    var showSource: Bool = true

    private var iconSize: CGFloat {
        switch density {
        case .compact: return 30
        case .comfortable: return 36
        case .spacious: return 40
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
        HStack(alignment: .top, spacing: 8) {
            // Unread dot
            ZStack(alignment: .top) {
                if !article.isRead {
                    Circle()
                        .fill(Color.siftAccent)
                        .frame(width: 6.5, height: 6.5)
                        .padding(.top, 4)
                }
            }
            .frame(width: 7)

            // Feed Favicon / Initial Monogram
            if showFeedIcon && showSource {
                if let feed = article.feed {
                    FeedFaviconView(feed: feed, size: iconSize, cornerRadius: iconSize * 0.22)
                } else {
                    FeedFaviconView(title: feedTitle, size: iconSize, cornerRadius: iconSize * 0.22)
                }
            }

            // Article Content: Header line, Title, Snippet
            VStack(alignment: .leading, spacing: density == .compact ? 2 : 3) {
                if showSource {
                    // Header: Feed Name + Timestamp
                    HStack(alignment: .firstTextBaseline) {
                        Text(feedTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(article.isRead ? Color.primary.opacity(0.75) : Color.primary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        trailingMeta
                    }
                }

                // Article Title (+ trailing time/star inline when the header line is gone)
                HStack(alignment: .firstTextBaseline) {
                    Text(article.title.isEmpty ? "Untitled" : article.title)
                        .font(.system(size: 16, weight: article.isRead ? .regular : .semibold))
                        .foregroundStyle(article.isRead ? Color.primary.opacity(0.78) : Color.primary)
                        .lineSpacing(1.2)
                        .lineLimit(density == .compact ? 1 : 2)

                    if !showSource {
                        Spacer(minLength: 6)
                        trailingMeta
                    }
                }

                // Article Preview Snippet
                if showPreview, !snippet.isEmpty, density != .compact {
                    Text(snippet)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(article.isRead ? 0.58 : 0.7))
                        .lineSpacing(1.1)
                        .lineLimit(density == .spacious ? 2 : 1)
                        .padding(.top, 1)
                }
            }
        }
    }

    @ViewBuilder
    private var trailingMeta: some View {
        Text(formattedTime(for: article.publicationDate))
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)

        if article.isStarred {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.siftStarred)
        }
    }

    private func formattedTime(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
