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
    @State private var windowWidth: CGFloat = 1100

    // On iOS: NavigationSplitView state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    #if os(macOS)
    // On macOS: Responsive 3-tier drawer state
    @State private var isSidebarDrawerOpen: Bool = false
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

    // MARK: - macOS Adaptive Multi-Tier Layout
    #if os(macOS)
    private var macRootView: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Group {
                if width < 600 {
                    // Tier 1: Ultra-Compact iOS-like Single-Column Stack
                    compactMacLayout
                } else if width < 900 {
                    // Tier 2: Medium Focus Mode (Article List + Full Reader, Sidebar Drawer Overlay)
                    mediumMacLayout(windowWidth: width)
                } else {
                    // Tier 3: Wide Full Desktop (Sidebar + Article List + Full Reader)
                    wideMacLayout(windowWidth: width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                windowWidth = width
                // In wide mode, sidebar is visible by default; in medium/compact, collapsed by default
                isSidebarDrawerOpen = (width >= 900)
            }
            .onChange(of: width) { _, newWidth in
                handleWidthChange(newWidth)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if windowWidth < 600 && viewModel.selectedArticle != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedArticle = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                            Text("Articles")
                        }
                    }
                    .help("Back to Articles")
                } else {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            isSidebarDrawerOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help(isSidebarDrawerOpen ? "Hide Sidebar (⌘⌃S)" : "Show Sidebar (⌘⌃S)")
                    .keyboardShortcut("s", modifiers: [.command, .control])
                }
            }
        }
        .onChange(of: viewModel.selectedSidebarItem) { _, _ in
            // When user picks a feed from drawer overlay in compact or medium mode, close drawer
            if windowWidth < 900 && isSidebarDrawerOpen {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarDrawerOpen = false
                }
            }
        }
        .onChange(of: viewModel.selectedArticle?.id) { _, newID in
            if windowWidth < 600 && newID != nil && isSidebarDrawerOpen {
                isSidebarDrawerOpen = false
            }
        }
    }

    // MARK: - Tier 1: Ultra-Compact (< 600px)
    private var compactMacLayout: some View {
        ZStack {
            if let article = viewModel.selectedArticle {
                ArticleDetailView(
                    viewModel: viewModel,
                    article: article,
                    onBackToList: nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .trailing)
                ))
            } else {
                ZStack(alignment: .leading) {
                    ArticleListView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isSidebarDrawerOpen {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSidebarDrawerOpen = false
                                }
                            }

                        SidebarView(viewModel: viewModel)
                            .frame(width: 250)
                            .background(.ultraThickMaterial)
                            .overlay(alignment: .trailing) { Divider() }
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 3, y: 0)
                            .transition(.move(edge: .leading))
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .leading)
                ))
            }
        }
    }

    // MARK: - Tier 2: Medium (600px ..< 900px)
    private func mediumMacLayout(windowWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                ArticleListView(viewModel: viewModel)
                    .frame(width: 280)

                if isSidebarDrawerOpen {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSidebarDrawerOpen = false
                            }
                        }

                    SidebarView(viewModel: viewModel)
                        .frame(width: 250)
                        .background(.ultraThickMaterial)
                        .overlay(alignment: .trailing) { Divider() }
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 2, y: 0)
                        .transition(.move(edge: .leading))
                }
            }

            Divider()

            ArticleDetailView(
                viewModel: viewModel,
                article: viewModel.selectedArticle,
                onBackToList: nil
            )
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Tier 3: Wide (>= 900px)
    private func wideMacLayout(windowWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if isSidebarDrawerOpen {
                SidebarView(viewModel: viewModel)
                    .frame(width: 220)
                    .transition(.move(edge: .leading))

                Divider()
            }

            ArticleListView(viewModel: viewModel)
                .frame(width: 300)

            Divider()

            ArticleDetailView(
                viewModel: viewModel,
                article: viewModel.selectedArticle,
                onBackToList: nil
            )
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleWidthChange(_ width: CGFloat) {
        let previousWidth = windowWidth
        windowWidth = width

        if previousWidth >= 900 && width < 900 {
            // Shrinking from wide to medium: close drawer to protect reading space
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarDrawerOpen = false
            }
        } else if previousWidth < 900 && width >= 900 {
            // Expanding to wide: open sidebar as a permanent column
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarDrawerOpen = true
            }
        }
    }
    #endif
}
