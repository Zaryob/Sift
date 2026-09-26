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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowWidth: CGFloat = 1100
    // On iPhone the app should open on something to read, not on a filter picker.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            ArticleListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            ArticleDetailView(
                viewModel: viewModel,
                article: viewModel.selectedArticle,
                onBackToList: windowWidth < 560 ? {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedArticle = nil
                        columnVisibility = .doubleColumn
                    }
                } : nil
            )
        }
        .navigationSplitViewStyle(.prominentDetail)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        handleWidthChange(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        handleWidthChange(newWidth)
                    }
            }
        }
        #endif
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
            if !hasCompletedOnboarding && feeds.isEmpty {
                isShowingOnboarding = true
            }
            NotificationManager.shared.updateBadgeCount(unreadItems.count)
            DispatchQueue.main.async {
                WidgetSnapshotManager.shared.updateSnapshot(context: modelContext)
                WidgetCenter.shared.reloadAllTimelines()
                viewModel.refreshAllFeeds(context: modelContext)

                #if os(macOS)
                if let pending = AppDelegate.pendingURL {
                    AppDelegate.pendingURL = nil
                    if pending.isFileURL {
                        Task {
                            await viewModel.importOPMLFile(at: pending, context: modelContext)
                        }
                    } else {
                        viewModel.handleDeepLink(pending, context: modelContext)
                    }
                }
                #endif
            }
        }
        .onChange(of: unreadItems.count) { _, newCount in
            NotificationManager.shared.updateBadgeCount(newCount)
        }
        .onChange(of: viewModel.selectedArticle?.id) { _, newArticleID in
            #if os(macOS)
            if windowWidth < 560 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    columnVisibility = (newArticleID != nil) ? .detailOnly : .doubleColumn
                }
            }
            #endif
        }
    }

    #if os(macOS)
    private func handleWidthChange(_ width: CGFloat) {
        windowWidth = width
        withAnimation(.easeInOut(duration: 0.2)) {
            if width < 560 {
                columnVisibility = (viewModel.selectedArticle != nil) ? .detailOnly : .doubleColumn
            } else if width < 900 {
                columnVisibility = .doubleColumn
            } else {
                columnVisibility = .all
            }
        }
    }
    #endif
}
