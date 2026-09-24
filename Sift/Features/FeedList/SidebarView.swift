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
        allArticles.filter { Calendar.current.isDateInToday($0.publicationDate) }.count
    }

    private var thisWeekCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allArticles.filter { $0.publicationDate >= sevenDaysAgo }.count
    }

    private var unreadArticlesCount: Int {
        allArticles.filter { !$0.isRead }.count
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

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            Section("Smart Filters") {
                NavigationLink(value: SidebarItem.all) {
                    Label {
                        HStack {
                            Text("All Articles")
                            Spacer()
                            if totalUnreadCount > 0 {
                                countBadge(totalUnreadCount, color: .secondary.opacity(0.2))
                            }
                        }
                    } icon: {
                        Image(systemName: "tray.full")
                    }
                }

                NavigationLink(value: SidebarItem.today) {
                    Label {
                        HStack {
                            Text("Today")
                            Spacer()
                            if todayCount > 0 {
                                countBadge(todayCount, color: .purple.opacity(0.2))
                            }
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
                            if thisWeekCount > 0 {
                                countBadge(thisWeekCount, color: .teal.opacity(0.2))
                            }
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
                            if unreadArticlesCount > 0 {
                                countBadge(unreadArticlesCount, color: .blue.opacity(0.2))
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
                                countBadge(starredArticlesCount, color: .orange.opacity(0.2))
                            }
                        }
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Categorized Folders
            ForEach(sortedCategories, id: \.self) { categoryName in
                Section(header: Label(categoryName, systemImage: "folder.fill").font(.subheadline).foregroundStyle(.secondary)) {
                    if let categoryFeeds = categorizedFeeds[categoryName] {
                        ForEach(categoryFeeds) { feed in
                            feedRow(feed: feed)
                        }
                    }
                }
            }

            // Uncategorized Feeds
            Section {
                ForEach(uncategorizedFeeds) { feed in
                    feedRow(feed: feed)
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

    @ViewBuilder
    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
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
                    countBadge(count, color: .secondary.opacity(0.2))
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
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                default:
                    Image(systemName: "dot.radiowaves.up.and.right")
                        .foregroundStyle(.orange)
                        .frame(width: 16, height: 16)
                }
            }
        } else {
            Image(systemName: "dot.radiowaves.up.and.right")
                .foregroundStyle(.orange)
                .frame(width: 16, height: 16)
        }
    }
}
