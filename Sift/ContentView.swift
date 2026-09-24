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
        .onAppear {
            viewModel.refreshAllFeeds()
        }
    }
}
