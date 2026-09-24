import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = AppViewModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } content: {
            ArticleListView(viewModel: viewModel)
        } detail: {
            ArticleDetailView(viewModel: viewModel, article: viewModel.selectedArticle)
        }
        .sheet(isPresented: $viewModel.isAddingFeed) {
            AddFeedSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .onOpenURL { url in
            viewModel.handleDeepLink(url, context: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.openArticleNotification)) { notification in
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
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.openFeedNotification)) { notification in
            if let feedID = notification.object as? UUID {
                viewModel.selectedSidebarItem = .feed(feedID)
            }
        }
        .onAppear {
            viewModel.refreshAllFeeds()
        }
    }
}
