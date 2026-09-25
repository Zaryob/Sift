import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<FeedItem> { !$0.isRead }) private var unreadItems: [FeedItem]

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            ArticleListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 480)
        } detail: {
            ArticleDetailView(viewModel: viewModel, article: viewModel.selectedArticle)
        }
        #if os(macOS)
        .frame(minWidth: 880, minHeight: 520)
        #endif
        .background(WindowAccessor())
        .sheet(isPresented: $viewModel.isAddingFeed) {
            AddFeedSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingSettings) {
            SettingsView()
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
    }
}
