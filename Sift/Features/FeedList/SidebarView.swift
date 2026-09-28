import SwiftUI
import SwiftData

/// The "Mailboxes" screen: Library scopes + Feeds/folders. This is the navigation root; the
/// timeline (ArticleListView) is pushed on top of it and backs out to here, the same way Mail's
/// unified inbox backs out to its Mailboxes list.
struct SidebarView: View {
    @Bindable var viewModel: AppViewModel

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(filter: #Predicate<FeedItem> { !$0.isRead }) private var unreadArticles: [FeedItem]
    @Query(filter: #Predicate<FeedItem> { $0.isStarred }) private var starredArticles: [FeedItem]
    @Environment(\.modelContext) private var modelContext

    @State private var editingFeedForCategory: Feed?
    @State private var categoryInputText: String = ""
    @State private var isShowingCategoryPrompt: Bool = false
    @State private var collapsedFolders: Set<String> = []

    private var todayCount: Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return unreadArticles.filter { $0.publicationDate >= startOfToday }.count
    }

    private var unreadCount: Int {
        unreadArticles.count
    }

    private var starredCount: Int {
        starredArticles.count
    }

    private var smartUnreadCount: Int {
        SmartFeedFilter.filteredArticles(from: unreadArticles).count
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

    private var feedUnreadCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in unreadArticles {
            if let feedID = item.feed?.id {
                counts[feedID, default: 0] += 1
            }
        }
        return counts
    }

    private func categoryUnreadCount(_ categoryName: String) -> Int {
        let counts = feedUnreadCounts
        return (categorizedFeeds[categoryName] ?? []).reduce(0) { $0 + (counts[$1.id] ?? 0) }
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
                libraryRow("SIFT Feed", systemImage: "sparkles", item: .smart, count: smartUnreadCount > 0 ? smartUnreadCount : nil)
                libraryRow("All Articles", systemImage: "tray.full", item: .all, count: unreadCount > 0 ? unreadCount : nil)
                libraryRow("Today", systemImage: "sun.max", item: .today, count: todayCount > 0 ? todayCount : nil)
                libraryRow("Unread", systemImage: "circlebadge", item: .unread, count: unreadCount)
                libraryRow("Starred", systemImage: "star", item: .starred, count: starredCount)

                Button {
                    viewModel.isShowingDailyBriefing = true
                } label: {
                    Label {
                        HStack {
                            Text("Daily Briefing")
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.siftAccent)
                        }
                    } icon: {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.purple)
                    }
                }
                .buttonStyle(.plain)
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
        .alert("Set Folder / Category", isPresented: $isShowingCategoryPrompt) {
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
        .onAppear {
            NotificationManager.shared.updateBadgeCount(unreadArticles.count)
        }
        .onChange(of: unreadArticles.count) { _, newCount in
            NotificationManager.shared.updateBadgeCount(newCount)
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
        case .smart:
            return Color.purple
        case .all:
            return Color.siftAccent
        case .today:
            return Color.orange
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
                if feed.refreshError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(feed.refreshError ?? "")
                }
                let unread = feedUnreadCounts[feed.id] ?? 0
                if unread > 0 {
                    countText(unread)
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
                isShowingCategoryPrompt = true
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
