import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var viewModel: AppViewModel
    var isSheet: Bool = false

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query private var allArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

            // Subtle status section
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
        .navigationTitle(isSheet ? "Manage Feeds" : "Sift")
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
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isAddingFeed = true
                    } label: {
                        Label("Add Feed", systemImage: "plus")
                    }
                }
            } else {
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
        Button {
            viewModel.selectedSidebarItem = item
            if isSheet {
                dismiss()
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if let count {
                    countText(count)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        Button {
            viewModel.selectedSidebarItem = .feed(feed.id)
            if isSheet {
                dismiss()
            }
        } label: {
            HStack {
                FeedFaviconView(feed: feed, size: 20, cornerRadius: 5)
                Text(feed.title)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer()
                countText(feed.unreadCount)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

struct ManageSourcesSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SidebarView(viewModel: viewModel, isSheet: true)
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 460, minHeight: 450)
        #endif
    }
}

struct FeedFaviconView: View {
    let feed: Feed?
    var feedTitle: String? = nil
    var siteURL: String? = nil
    var feedURL: String? = nil
    var iconURL: String? = nil
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 9

    init(feed: Feed, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = feed
        self.feedTitle = feed.title
        self.siteURL = feed.siteURL
        self.feedURL = feed.url
        self.iconURL = feed.iconURL
        self.size = size
        self.cornerRadius = cornerRadius ?? (size * 0.24)
    }

    init(
        title: String,
        siteURL: String? = nil,
        feedURL: String? = nil,
        iconURL: String? = nil,
        size: CGFloat = 38,
        cornerRadius: CGFloat? = nil
    ) {
        self.feed = nil
        self.feedTitle = title
        self.siteURL = siteURL
        self.feedURL = feedURL
        self.iconURL = iconURL
        self.size = size
        self.cornerRadius = cornerRadius ?? (size * 0.24)
    }

    private var effectiveTitle: String {
        feed?.title ?? feedTitle ?? "RSS"
    }

    private var faviconURL: URL? {
        FaviconFetcher.faviconURL(
            for: feed?.siteURL ?? siteURL,
            feedURLString: feed?.url ?? feedURL ?? "",
            iconURLString: feed?.iconURL ?? iconURL
        )
    }

    private var monogramText: String {
        let words = effectiveTitle.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if let word = words.first, word.count >= 2 {
            return String(word.prefix(2)).uppercased()
        } else if let word = words.first {
            return String(word.prefix(1)).uppercased()
        }
        return "RS"
    }

    private var monogramColor: Color {
        let hash = abs(effectiveTitle.hashValue)
        let colors: [Color] = [.blue, .purple, .teal, .indigo, .orange, .pink, .mint]
        return colors[hash % colors.count]
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
                        monogramFallback
                    }
                }
            } else {
                monogramFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var monogramFallback: some View {
        ZStack {
            monogramColor.opacity(0.14)
            Text(monogramText)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(monogramColor)
        }
    }
}
