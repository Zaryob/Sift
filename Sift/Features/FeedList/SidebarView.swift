import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var viewModel: AppViewModel
    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext
    
    @State private var editingFeedForCategory: Feed?
    @State private var categoryInputText: String = ""
    @State private var showCategoryPrompt: Bool = false

    private var totalUnreadCount: Int {
        allArticles.filter { !$0.isRead }.count
    }

    private var todayCount: Int {
        allArticles.filter { Calendar.current.isDateInToday($0.publicationDate) && !$0.isRead }.count
    }

    private var thisWeekCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allArticles.filter { $0.publicationDate >= sevenDaysAgo && !$0.isRead }.count
    }

    private var unreadArticlesCount: Int {
        totalUnreadCount
    }

    private var starredArticlesCount: Int {
        allArticles.filter { $0.isStarred }.count
    }

    private var categorizedFeeds: [String: [Feed]] {
        Dictionary(grouping: feeds) { feed in
            feed.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private var sortedCategories: [String] {
        categorizedFeeds.keys.filter { !$0.isEmpty }.sorted()
    }

    private var uncategorizedFeeds: [Feed] {
        categorizedFeeds[""] ?? []
    }

    private func categoryUnreadCount(_ categoryName: String) -> Int {
        let catFeeds = categorizedFeeds[categoryName] ?? []
        return catFeeds.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            Section("Smart Filters") {
                NavigationLink(value: SidebarItem.all) {
                    Label {
                        HStack {
                            Text("All Articles")
                            Spacer()
                            countBadge(totalUnreadCount, tint: .indigo)
                        }
                    } icon: {
                        Image(systemName: "tray.full.fill")
                            .foregroundStyle(.indigo)
                    }
                }

                NavigationLink(value: SidebarItem.today) {
                    Label {
                        HStack {
                            Text("Today")
                            Spacer()
                            countBadge(todayCount, tint: .purple)
                        }
                    } icon: {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.purple)
                    }
                }

                NavigationLink(value: SidebarItem.thisWeek) {
                    Label {
                        HStack {
                            Text("This Week")
                            Spacer()
                            countBadge(thisWeekCount, tint: .teal)
                        }
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(.teal)
                    }
                }

                NavigationLink(value: SidebarItem.unread) {
                    Label {
                        HStack {
                            Text("Unread")
                            Spacer()
                            countBadge(unreadArticlesCount, tint: .blue)
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
                            countBadge(starredArticlesCount, tint: .orange)
                        }
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Categorized Folders
            ForEach(sortedCategories, id: \.self) { categoryName in
                Section {
                    if let categoryFeeds = categorizedFeeds[categoryName] {
                        ForEach(categoryFeeds) { feed in
                            feedRow(feed: feed)
                        }
                    }
                } header: {
                    HStack {
                        Label(categoryName, systemImage: "folder.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        let catCount = categoryUnreadCount(categoryName)
                        if catCount > 0 {
                            Text("\(catCount)")
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Uncategorized Feeds
            if !uncategorizedFeeds.isEmpty || sortedCategories.isEmpty {
                Section("Feeds") {
                    ForEach(uncategorizedFeeds) { feed in
                        feedRow(feed: feed)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sift")
        #if os(macOS)
        .safeAreaInset(edge: .bottom) {
            sidebarBottomBar
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add New RSS Feed")
            }
        }
        #else
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Feed")

                Spacer()

                if viewModel.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text("Refreshing...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(feeds.count) \(feeds.count == 1 ? "feed" : "feeds")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button {
                    viewModel.refreshAllFeeds()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
                .help("Refresh Feeds")
            }
        }
        #endif
        .alert("Set Folder / Category", isPresented: $showCategoryPrompt) {
            TextField("Folder Name (e.g. Tech, News)", text: $categoryInputText)
            Button("Save") {
                if let feed = editingFeedForCategory {
                    viewModel.updateFeedCategory(feed, category: categoryInputText, context: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a folder name for this feed or leave empty to remove from folder.")
        }
    }

    #if os(macOS)
    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .help("Add RSS Feed")

                Spacer()

                if viewModel.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text("Refreshing...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(feeds.count) \(feeds.count == 1 ? "feed" : "feeds")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    viewModel.refreshAllFeeds()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRefreshing)
                .help("Refresh All Feeds")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
    #endif

    @ViewBuilder
    private func countBadge(_ count: Int, tint: Color) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(tint.opacity(0.14))
                )
        }
    }

    @ViewBuilder
    private func feedRow(feed: Feed) -> some View {
        NavigationLink(value: SidebarItem.feed(feed.id)) {
            HStack(spacing: 8) {
                FeedFaviconView(feed: feed)

                Text(feed.title)
                    .lineLimit(1)

                Spacer()

                let count = feed.unreadCount
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
        }
        .contextMenu {
            Button("Set Folder...") {
                editingFeedForCategory = feed
                categoryInputText = feed.category ?? ""
                showCategoryPrompt = true
            }
            Divider()
            Button("Refresh Feed") {
                Task {
                    try? await FeedRefreshService().refreshFeed(id: feed.id)
                }
            }
            if let siteURLStr = feed.siteURL, let url = URL(string: siteURLStr) {
                Button("Visit Website") {
                    Platform.openURL(url)
                }
            }
            Button("Copy Feed URL") {
                Platform.copyToPasteboard(feed.url)
            }
            Divider()
            Button("Delete Feed", role: .destructive) {
                viewModel.deleteFeed(feed, context: modelContext)
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
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                default:
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 16, height: 16)

            Image(systemName: "dot.radiowaves.up.and.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}
