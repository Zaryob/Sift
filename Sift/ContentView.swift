import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<FeedItem> { !$0.isRead }) private var unreadItems: [FeedItem]
    @Query private var feeds: [Feed]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var isShowingOnboarding: Bool = false

    // NavigationSplitView state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    #if os(macOS)
    @State private var macLayoutMode: MacLayoutMode?

    private enum MacLayoutMode: Equatable {
        case singleColumn
        case listAndReader
        case threeColumn

        static let sidebarMinimumWidth: CGFloat = 180
        static let listMinimumWidth: CGFloat = 260
        static let readerMinimumWidth: CGFloat = 480

        init(width: CGFloat) {
            let threeColumnMinimum = Self.sidebarMinimumWidth
                + Self.listMinimumWidth
                + Self.readerMinimumWidth
            let listAndReaderMinimum = Self.listMinimumWidth + Self.readerMinimumWidth

            if width >= threeColumnMinimum {
                self = .threeColumn
            } else if width >= listAndReaderMinimum {
                self = .listAndReader
            } else {
                self = .singleColumn
            }
        }

        var columnVisibility: NavigationSplitViewVisibility {
            switch self {
            case .singleColumn:
                .detailOnly
            case .listAndReader:
                .doubleColumn
            case .threeColumn:
                .all
            }
        }
    }
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            macRootView
            #else
            iosRootView
            #endif
        }
        .background(WindowAccessor())
        .sheet(isPresented: $viewModel.isAddingFeed) {
            AddFeedSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .onOpenURL { url in
            Platform.showMainWindow()
            if url.isFileURL {
                Task {
                    await viewModel.importOPMLFile(at: url, context: modelContext)
                }
            } else {
                DispatchQueue.main.async {
                    viewModel.handleDeepLink(url, context: modelContext)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .siftHandleDeepLink)) { notification in
            if let url = notification.object as? URL {
                Platform.showMainWindow()
                if url.isFileURL {
                    Task {
                        await viewModel.importOPMLFile(at: url, context: modelContext)
                    }
                } else {
                    DispatchQueue.main.async {
                        viewModel.handleDeepLink(url, context: modelContext)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.openArticleNotification)) { notification in
            DispatchQueue.main.async {
                Platform.showMainWindow()
                if let articleID = notification.object as? UUID {
                    let descriptor = FetchDescriptor<FeedItem>(predicate: #Predicate { $0.id == articleID })
                    if let item = try? modelContext.fetch(descriptor).first {
                        if let feed = item.feed {
                            viewModel.selectedSidebarItem = .feed(feed.id)
                        } else {
                            viewModel.selectedSidebarItem = .all
                        }
                        viewModel.selectedArticle = item
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.openFeedNotification)) { notification in
            DispatchQueue.main.async {
                Platform.showMainWindow()
                if let feedID = notification.object as? UUID {
                    viewModel.selectedSidebarItem = .feed(feedID)
                }
            }
        }
        .onAppear {
            if !hasCompletedOnboarding {
                let feedCount = (try? modelContext.fetchCount(FetchDescriptor<Feed>())) ?? 0
                if feedCount == 0 {
                    isShowingOnboarding = true
                }
            }
            Task {
                await WidgetSnapshotManager.shared.updateSnapshot(context: modelContext)
                WidgetCenter.shared.reloadAllTimelines()

                // Check if last refreshed recently (within 5 minutes) before triggering auto-refresh on appear
                let shouldRefresh: Bool
                if let last = viewModel.lastRefreshedAt {
                    shouldRefresh = Date().timeIntervalSince(last) > 300
                } else {
                    shouldRefresh = true
                }
                if shouldRefresh {
                    viewModel.refreshAllFeeds(context: modelContext)
                }

                #if os(macOS)
                if let pending = AppDelegate.pendingURL {
                    AppDelegate.pendingURL = nil
                    if pending.isFileURL {
                        await viewModel.importOPMLFile(at: pending, context: modelContext)
                    } else {
                        viewModel.handleDeepLink(pending, context: modelContext)
                    }
                }
                #endif
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: PersistenceController.storeFailedNotification)) { _ in
            viewModel.errorMessage = String(localized: "Sift could not open its database and is running in temporary mode. Your subscriptions are safe — please restart the app.")
            viewModel.showErrorAlert = true
        }
    }

    // MARK: - iOS Root View
    #if os(iOS)
    private var iosRootView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            ArticleListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            ArticleDetailView(
                viewModel: viewModel,
                article: viewModel.selectedArticle
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

    // MARK: - macOS Root View
    #if os(macOS)
    private var macRootView: some View {
        GeometryReader { proxy in
            let layoutMode = MacLayoutMode(width: proxy.size.width)

            Group {
                if layoutMode == .singleColumn {
                    compactMacSplitView
                } else {
                    regularMacSplitView
                }
            }
            .onAppear {
                updateMacLayoutMode(layoutMode)
            }
            .onChange(of: layoutMode) { _, newMode in
                updateMacLayoutMode(newMode)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .onChange(of: viewModel.selectedArticle?.id) { _, newID in
            preferredCompactColumn = newID == nil ? .content : .detail
        }
    }

    private var regularMacSplitView: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(
                    min: MacLayoutMode.sidebarMinimumWidth,
                    ideal: 220,
                    max: 260
                )
        } content: {
            ArticleListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(
                    min: MacLayoutMode.listMinimumWidth,
                    ideal: 300,
                    max: 360
                )
        } detail: {
            ArticleDetailView(
                viewModel: viewModel,
                article: viewModel.selectedArticle
            )
            .frame(minWidth: MacLayoutMode.readerMinimumWidth)
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    private var compactMacSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(
                    min: MacLayoutMode.sidebarMinimumWidth,
                    ideal: 220,
                    max: 260
                )
        } detail: {
            if let article = viewModel.selectedArticle {
                ArticleDetailView(
                    viewModel: viewModel,
                    article: article,
                    onBackToList: {
                        viewModel.selectedArticle = nil
                    }
                )
            } else {
                ArticleListView(viewModel: viewModel)
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    private func updateMacLayoutMode(_ newMode: MacLayoutMode) {
        guard macLayoutMode != newMode else { return }
        macLayoutMode = newMode
        columnVisibility = newMode.columnVisibility
    }
    #endif
}
