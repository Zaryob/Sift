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

// MARK: - Article Filter Configuration (Apple Mail Style)

struct ArticleFilterConfig: Codable, Equatable {
    var includeUnread: Bool = true
    var includeStarred: Bool = false
    var onlyWithMedia: Bool = false
    var onlyToday: Bool = false
    var onlyVIPFeeds: Bool = false
    var excludedFeedIDs: Set<UUID> = []

    static let defaultConfig = ArticleFilterConfig(
        includeUnread: true,
        includeStarred: false,
        onlyWithMedia: false,
        onlyToday: false,
        onlyVIPFeeds: false,
        excludedFeedIDs: []
    )

    var isDefault: Bool {
        self == Self.defaultConfig
    }

    var summaryText: String {
        var parts: [String] = []
        if includeUnread && includeStarred {
            parts.append(String(localized: "Unread, Starred"))
        } else if includeUnread {
            parts.append(String(localized: "Unread"))
        } else if includeStarred {
            parts.append(String(localized: "Starred"))
        }

        if onlyToday {
            parts.append(String(localized: "Today"))
        }

        if onlyWithMedia {
            parts.append(String(localized: "With Media"))
        }

        if onlyVIPFeeds {
            parts.append(String(localized: "VIP Feeds"))
        }

        if !excludedFeedIDs.isEmpty {
            let count = excludedFeedIDs.count
            let noun = count == 1 ? String(localized: "feed excluded") : String(localized: "feeds excluded")
            parts.append("\(count) \(noun)")
        }

        if parts.isEmpty {
            return String(localized: "All Articles")
        }
        return parts.joined(separator: " · ")
    }

    func matches(_ article: FeedItem, vipFeedIDs: Set<UUID>) -> Bool {
        if let feedID = article.feed?.id, excludedFeedIDs.contains(feedID) {
            return false
        }

        if includeUnread || includeStarred {
            let matchesUnread = includeUnread && !article.isRead
            let matchesStarred = includeStarred && article.isStarred
            if !matchesUnread && !matchesStarred {
                return false
            }
        }

        if onlyToday {
            if !Calendar.current.isDateInToday(article.publicationDate) {
                return false
            }
        }

        if onlyWithMedia {
            guard let imageURL = article.imageURL, !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }

        if onlyVIPFeeds {
            guard let feedID = article.feed?.id, vipFeedIDs.contains(feedID) else {
                return false
            }
        }

        return true
    }
}

// MARK: - Article List View

struct ArticleListView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \FeedItem.publicationDate, order: .reverse) private var allArticles: [FeedItem]
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var isFilterActive = false
    @State private var filterConfig = ArticleFilterConfig.defaultConfig
    @State private var isShowingFilters = false
    @State private var isConfirmingMarkAllRead = false
    @State private var showToast = false
    @State private var sortOrder: ArticleSortOrder = .newestFirst
    @State private var hideRead = false

    @AppStorage("vipFeedIDs") private var vipFeedIDsRaw: String = ""
    @AppStorage("articleFilterConfigData") private var savedFilterConfigData: Data = Data()

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

    private var vipFeedIDs: Set<UUID> {
        get {
            Set(vipFeedIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        }
        set {
            vipFeedIDsRaw = newValue.map(\.uuidString).joined(separator: ",")
        }
    }

    private var vipFeedIDsBinding: Binding<Set<UUID>> {
        Binding(
            get: {
                Set(vipFeedIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            },
            set: { newSet in
                vipFeedIDsRaw = newSet.map(\.uuidString).joined(separator: ",")
            }
        )
    }

    // MARK: - Filtered Articles

    private var baseArticles: [FeedItem] {
        if case .feed(let feedID) = viewModel.selectedSidebarItem {
            return allArticles.filter { $0.feed?.id == feedID }
        }
        switch viewModel.selectedSidebarItem {
        case .unread:
            return allArticles.filter { !$0.isRead }
        case .starred:
            return allArticles.filter { $0.isStarred }
        case .all, .none, .feed:
            return allArticles
        }
    }

    private var sourceArticles: [FeedItem] {
        if isFilterActive {
            return baseArticles.filter { filterConfig.matches($0, vipFeedIDs: vipFeedIDs) }
        }
        return baseArticles
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
        baseArticles.filter { !$0.isRead }.count
    }

    private var currentScopeTitle: String {
        switch viewModel.selectedSidebarItem {
        case .unread: return String(localized: "Unread")
        case .starred: return String(localized: "Starred")
        case .all, .none: return String(localized: "All Articles")
        case .feed(let id): return feeds.first(where: { $0.id == id })?.title ?? String(localized: "Feed")
        }
    }

    private var currentFeedTitle: String? {
        if case .feed(let feedID) = viewModel.selectedSidebarItem {
            return feeds.first(where: { $0.id == feedID })?.title
        }
        return nil
    }

    private var rowInsets: EdgeInsets {
        let vertical: CGFloat = switch density {
        case .compact: 8
        case .comfortable: 11
        case .spacious: 14
        }
        return EdgeInsets(top: vertical, leading: 16, bottom: vertical, trailing: 16)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            List(selection: $viewModel.selectedArticle) {
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
                                    .listRowInsets(rowInsets)
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
            .navigationTitle(currentNavTitle)
            .navigationSubtitle(currentNavSubtitle)
            #if os(iOS)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search articles, feeds…")
            .searchToolbarBehavior(isFilterActive ? .minimize : .automatic)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
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
                    filterConfig: $filterConfig,
                    vipFeedIDs: vipFeedIDsBinding,
                    feeds: feeds
                )
            }
            .onAppear {
                if let decoded = try? JSONDecoder().decode(ArticleFilterConfig.self, from: savedFilterConfigData) {
                    filterConfig = decoded
                }
            }
            .onChange(of: filterConfig) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) {
                    savedFilterConfigData = data
                }
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

    private var currentNavTitle: String {
        currentFeedTitle ?? currentScopeTitle
    }

    private var currentNavSubtitle: String {
        if viewModel.isRefreshing {
            return String(localized: "Updating feeds…")
        }
        if isFilterActive {
            let count = filteredArticles.count
            return "\(currentScopeTitle) · \(count) \(filterConfig.summaryText)"
        } else {
            return statusText
        }
    }

    private var selectedFeedItem: Feed? {
        if case .feed(let id) = viewModel.selectedSidebarItem {
            return feeds.first(where: { $0.id == id })
        }
        return nil
    }

    // MARK: - Status

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

    // MARK: - Article Row Link

    private func articleRowLink(_ article: FeedItem) -> some View {
        NavigationLink(value: article) {
            ArticleRow(
                article: article,
                density: density,
                showFeedIcon: showFeedIcons,
                showPreview: showArticlePreviews,
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

        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFilterActive.toggle()
                }
            } label: {
                filterButtonIcon
            }
            .accessibilityLabel(isFilterActive ? "Turn filter off" : "Turn filter on")
            .contextMenu {
                Button {
                    isShowingFilters = true
                } label: {
                    Label("Filter Options…", systemImage: "slider.horizontal.3")
                }
                if isFilterActive {
                    Button(role: .destructive) {
                        withAnimation {
                            isFilterActive = false
                        }
                    } label: {
                        Label("Turn Filter Off", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }

            Spacer()

            if isFilterActive {
                Button {
                    isShowingFilters = true
                } label: {
                    HStack(spacing: 3) {
                        Text("Filtered by:")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(filterConfig.summaryText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filtered by \(filterConfig.summaryText). Tap to edit filters.")
            } else {
                Text(statusText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }

        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation {
                    isFilterActive.toggle()
                }
            } label: {
                Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(isFilterActive ? Color.blue : Color.primary)
            }
            .help(isFilterActive ? "Turn Filter Off" : "Turn Filter On")
            .contextMenu {
                Button("Filter Options…") {
                    isShowingFilters = true
                }
            }

            Button {
                viewModel.isAddingFeed = true
            } label: {
                Label("Add Feed", systemImage: "plus")
            }

            moreOptionsMenu
        }
        #endif
    }

    @ViewBuilder
    private var filterButtonIcon: some View {
        if isFilterActive {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.blue)
        } else {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
        }
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
        } else if isFilterActive {
            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.siftAccent)
                    .padding(.bottom, 4)

                Text("No Articles Match Filter")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Try adjusting your filters or turn off filtering to see all articles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Turn Off Filter") {
                    withAnimation {
                        isFilterActive = false
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.siftAccent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        } else if case .unread = viewModel.selectedSidebarItem, currentScopeUnreadCount == 0 {
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
                        viewModel.selectedSidebarItem = .all
                        hideRead = false
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.siftAccent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
        } else if case .starred = viewModel.selectedSidebarItem {
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

// MARK: - Article Filters Sheet (Apple Mail Style)

struct ArticleFiltersSheet: View {
    @Binding var filterConfig: ArticleFilterConfig
    @Binding var vipFeedIDs: Set<UUID>
    let feeds: [Feed]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !feeds.isEmpty {
                    Section {
                        ForEach(feeds) { feed in
                            feedRow(feed)
                        }
                    } header: {
                        Text("Include Articles From")
                    }
                }

                Section {
                    unreadRow
                    starredRow
                } header: {
                    Text("Include")
                }

                Section {
                    Toggle(isOn: $filterConfig.onlyWithMedia) {
                        HStack(spacing: 12) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Only Articles with Media")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }
                    }

                    Toggle(isOn: $filterConfig.onlyVIPFeeds) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.yellow)
                                .frame(width: 24)
                            Text("Only from VIP Feeds")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }
                    }

                    Toggle(isOn: $filterConfig.onlyToday) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Only Articles Sent Today")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if !filterConfig.isDefault {
                    Section {
                        Button("Reset Filters", role: .destructive) {
                            withAnimation {
                                filterConfig = .defaultConfig
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        #if os(iOS)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.blue, in: Circle())
                        #else
                        Text("Done")
                        #endif
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private func feedRow(_ feed: Feed) -> some View {
        let isIncluded = !filterConfig.excludedFeedIDs.contains(feed.id)
        let isVIP = vipFeedIDs.contains(feed.id)

        return Button {
            if isIncluded {
                filterConfig.excludedFeedIDs.insert(feed.id)
            } else {
                filterConfig.excludedFeedIDs.remove(feed.id)
            }
        } label: {
            HStack(spacing: 12) {
                FeedFaviconView(feed: feed, size: 24, cornerRadius: 5)

                Text(feed.title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    if isVIP {
                        vipFeedIDs.remove(feed.id)
                    } else {
                        vipFeedIDs.insert(feed.id)
                    }
                } label: {
                    Image(systemName: isVIP ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(isVIP ? Color.yellow : Color.secondary.opacity(0.35))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isVIP ? "Remove VIP" : "Mark as VIP Feed")

                if isIncluded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var unreadRow: some View {
        Button {
            filterConfig.includeUnread.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                Text("Unread")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                if filterConfig.includeUnread {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var starredRow: some View {
        Button {
            filterConfig.includeStarred.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                Text("Starred")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                if filterConfig.includeStarred {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
