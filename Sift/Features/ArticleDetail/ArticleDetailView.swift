import SwiftUI
import SwiftData

enum DetailViewMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case web = "Web"

    var id: String { rawValue }
}

struct ArticleDetailView: View {
    @Bindable var viewModel: AppViewModel
    let article: FeedItem?
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: DetailViewMode = .reader

    var body: some View {
        Group {
            if let article = article {
                VStack(spacing: 0) {
                    // Mode Picker Bar
                    HStack {
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(DetailViewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Spacer()

                        Button {
                            article.isStarred.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(article.isStarred ? "Unstar" : "Star", systemImage: article.isStarred ? "star.fill" : "star")
                        }

                        Button {
                            article.isRead.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "circle.fill")
                        }

                        Button {
                            viewModel.openArticleExternally(article)
                        } label: {
                            Label("Browser", systemImage: "safari")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    if viewMode == .web, let linkStr = article.link, let url = URL(string: linkStr) {
                        WebView(url: url)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                // Title
                                Text(article.title)
                                    .font(.title)
                                    .fontWeight(.bold)

                                // Metadata header bar
                                HStack(spacing: 12) {
                                    if let feedTitle = article.feed?.title {
                                        Label(feedTitle, systemImage: "rss")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let author = article.author, !author.isEmpty {
                                        Text("By \(author)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(article.publicationDate, style: .date)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                // Article Body Content / Summary
                                let rawBody = article.content ?? article.summary ?? ""
                                let cleanBody = HTMLSanitizer.stripTags(from: rawBody)
                                
                                if !cleanBody.isEmpty {
                                    Text(cleanBody)
                                        .font(.body)
                                        .lineSpacing(6)
                                        .textSelection(.enabled)
                                } else {
                                    Text("No additional content available for this article.")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }
                            }
                            .padding(24)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Article Selected",
                    systemImage: "sidebar.right",
                    description: Text("Select an article from the list to read.")
                )
            }
        }
        .onChange(of: article) { _, newItem in
            if let newItem = newItem, !newItem.isRead {
                newItem.isRead = true
                try? modelContext.save()
            }
        }
    }
}
