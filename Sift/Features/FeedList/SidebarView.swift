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

    var body: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            Section("Library") {
                libraryRow("All Articles", systemImage: "tray.full", item: .all, count: nil)
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

            // Subtle status section to keep empty space balanced and informative
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
                        Text(feeds.isEmpty ? "No subscriptions yet" : "\(feeds.count) feeds · \(unreadCount) unread")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sift")
        .refreshable {
            await viewModel.refreshAll(context: modelContext)
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.isAddingFeed = true
                } label: {
                    Label("Add Feed", systemImage: "plus")
                }
                .help("Add New RSS Feed")

                Button {
                    viewModel.refreshAllFeeds(context: modelContext)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
                .help("Refresh All Feeds")
            }
        }
        #else
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $viewModel.isShowingSettings) {
            SettingsView()
        }
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

    private func libraryRow(_ title: LocalizedStringKey, systemImage: String, item: SidebarItem, count: Int?) -> some View {
        NavigationLink(value: item) {
            Label {
                HStack {
                    Text(title)
                    Spacer()
                    if let count {
                        countText(count)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    @ViewBuilder
    private func countText(_ count: Int) -> some View {
        if count > 0 {
            Text(count, format: .number)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func feedRow(feed: Feed) -> some View {
        NavigationLink(value: SidebarItem.feed(feed.id)) {
            Label {
                HStack {
                    Text(feed.title)
                        .lineLimit(1)
                    Spacer()
                    countText(feed.unreadCount)
                }
            } icon: {
                FeedFaviconView(feed: feed)
            }
        }
        .contextMenu {
            Button("Set Folder…") {
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
    var size: CGFloat = 16

    private var faviconURL: URL? {
        FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL)
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
