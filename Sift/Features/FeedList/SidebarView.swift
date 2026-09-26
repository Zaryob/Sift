import SwiftUI
import SwiftData

/// The "Mailboxes" screen: Library scopes + Feeds/folders. This is the navigation root; the
/// timeline (ArticleListView) is pushed on top of it and backs out to here, the same way Mail's
/// unified inbox backs out to its Mailboxes list.
struct SidebarView: View {
    @Bindable var viewModel: AppViewModel

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext

    @State private var editingFeedForCategory: Feed?
    @State private var categoryInputText: String = ""
    @State private var showCategoryPrompt: Bool = false
    @State private var collapsedFolders: Set<String> = []

    private var unreadCount: Int {
        allArticles.filter { !$0.isRead }.count
    }

    private var starredCount: Int {
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
        (categorizedFeeds[categoryName] ?? []).reduce(0) { $0 + $1.unreadCount }
    }

    private func expansionBinding(for folder: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedFolders.contains(folder) },
            set: { isExpanded in
                if isExpanded {
                    collapsedFolders.remove(folder)
                } else {
                    collapsedFolders.insert(folder)
                }
            }
        )
    }

    private var statusSubtitle: String {
        if feeds.isEmpty {
            return String(localized: "No subscriptions yet")
        }
        let feedText = feeds.count == 1 ? String(localized: "1 feed") : "\(feeds.count) \(String(localized: "feeds"))"
        let unreadText = unreadCount == 1 ? String(localized: "1 unread") : "\(unreadCount) \(String(localized: "unread"))"
        return "\(feedText) · \(unreadText)"
    }

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            Section("Library") {
                libraryRow("All Articles", systemImage: "tray.full", item: .all, count: allArticles.isEmpty ? nil : allArticles.count)
                libraryRow("Unread", systemImage: "circlebadge", item: .unread, count: unreadCount)
                libraryRow("Starred", systemImage: "star", item: .starred, count: starredCount)
            }

            Section("Feeds") {
                ForEach(sortedCategories, id: \.self) { folder in
                    DisclosureGroup(isExpanded: expansionBinding(for: folder)) {
                        ForEach(categorizedFeeds[folder] ?? []) { feed in
                            feedRow(feed: feed)
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(folder)
                                Spacer()
                                countText(categoryUnreadCount(folder))
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                }

                ForEach(uncategorizedFeeds) { feed in
                    feedRow(feed: feed)
                }
            }

            #if os(iOS)
            // Subtle status section on iOS Mailboxes root
            Section {
                HStack(spacing: 8) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Refreshing feeds…")
                    } else {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                        Text(statusSubtitle)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            #endif
        }
        .listStyle(.sidebar)
        .navigationTitle("Sift")
        .refreshable {
            await viewModel.refreshAll(context: modelContext)
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }

                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationDestination(isPresented: $viewModel.isShowingSettings) {
            SettingsView()
        }
        #endif
    }

    @ViewBuilder
    private func libraryRow(_ title: String, systemImage: String, item: SidebarItem, count: Int?) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let count, count > 0 {
                    countText(count)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor(for: item))
        }
        .tag(item)
    }

    private func iconColor(for item: SidebarItem) -> Color {
        switch item {
        case .all:
            return Color.siftAccent
        case .unread:
            return Color.blue
        case .starred:
            return Color.siftStarred
        case .feed:
            return Color.secondary
        }
    }

    @ViewBuilder
    private func feedRow(feed: Feed) -> some View {
        Label {
            HStack {
                Text(feed.title)
                    .lineLimit(1)
                Spacer()
                if feed.unreadCount > 0 {
                    countText(feed.unreadCount)
                }
            }
        } icon: {
            FeedFaviconView(feed: feed, size: 16, cornerRadius: 4)
        }
        .tag(SidebarItem.feed(feed.id))
        .contextMenu {
            Button {
                editingFeedForCategory = feed
                categoryInputText = feed.category ?? ""
                showCategoryPrompt = true
            } label: {
                Label("Edit Folder…", systemImage: "folder.badge.gearshape")
            }

            if feed.category != nil {
                Button {
                    viewModel.updateFeedCategory(feed, category: nil, context: modelContext)
                } label: {
                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deleteFeed(feed, context: modelContext)
            } label: {
                Label("Delete Feed", systemImage: "trash")
            }
        }
    }

    private func countText(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}


struct FeedFaviconView: View {
    let feed: Feed?
    var title: String = ""
    var size: CGFloat = 16
    var cornerRadius: CGFloat = 4

    init(feed: Feed, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = feed
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.22
    }

    init(title: String, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = nil
        self.title = title
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.22
    }

    private var faviconURL: URL? {
        guard let feed else { return nil }
        return FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)
    }

    var body: some View {
        Group {
            if let url = faviconURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderIcon: some View {
        ZStack {
            Color.siftAccent.opacity(0.15)
            Image(systemName: "dot.radiowaves.up.and.right")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color.siftAccent)
        }
    }
}
