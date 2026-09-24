import SwiftUI
import SwiftData

enum DetailViewMode: String, CaseIterable, Identifiable {
    case reader = "Reader"
    case web = "Web"

    var id: String { rawValue }
}

enum ReaderFontDesign: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case monospace = "Monospace"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .monospace: return .monospaced
        }
    }
}

struct ArticleDetailView: View {
    @Bindable var viewModel: AppViewModel
    let article: FeedItem?
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: DetailViewMode = .reader

    @AppStorage("readerFontSize") private var readerFontSize: Double = 15.0
    @AppStorage("readerFontDesign") private var readerFontDesignRaw: String = ReaderFontDesign.system.rawValue
    @State private var showTypographyPopover: Bool = false

    private var currentFontDesign: ReaderFontDesign {
        ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .system
    }

    var body: some View {
        Group {
            if let article = article {
                VStack(spacing: 0) {
                    // Mode & Action Picker Bar
                    HStack {
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(DetailViewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Spacer()

                        if viewMode == .reader {
                            Button {
                                showTypographyPopover.toggle()
                            } label: {
                                Label("Text", systemImage: "textformat.size")
                            }
                            .popover(isPresented: $showTypographyPopover) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Typography")
                                        .font(.headline)

                                    HStack {
                                        Text("Size")
                                        Spacer()
                                        Button("-") {
                                            if readerFontSize > 11 { readerFontSize -= 1 }
                                        }
                                        Text("\(Int(readerFontSize)) pt")
                                            .monospacedDigit()
                                        Button("+") {
                                            if readerFontSize < 28 { readerFontSize += 1 }
                                        }
                                    }

                                    Picker("Font", selection: $readerFontDesignRaw) {
                                        ForEach(ReaderFontDesign.allCases) { f in
                                            Text(f.rawValue).tag(f.rawValue)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .padding(14)
                                .frame(width: 220)
                            }

                            Button {
                                printArticle(article)
                            } label: {
                                Label("Print / PDF", systemImage: "printer")
                            }
                        }

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
                                    .font(.system(size: readerFontSize * 1.5, weight: .bold, design: currentFontDesign.design))

                                let rawBody = article.content ?? article.summary ?? ""
                                let cleanBody = HTMLSanitizer.stripTags(from: rawBody)
                                let readingTime = estimatedReadingTime(text: cleanBody)

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

                                    HStack(spacing: 4) {
                                        Image(systemName: "clock")
                                        Text("\(readingTime) min read")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                    Spacer()

                                    Text(article.publicationDate, style: .date)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()

                                // Article Body Content / Summary
                                if !cleanBody.isEmpty {
                                    Text(cleanBody)
                                        .font(.system(size: readerFontSize, weight: .regular, design: currentFontDesign.design))
                                        .lineSpacing(readerFontSize * 0.4)
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

    private func estimatedReadingTime(text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return max(1, Int(ceil(Double(words.count) / 200.0)))
    }

    private func printArticle(_ article: FeedItem) {
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let body = HTMLSanitizer.stripTags(from: article.content ?? article.summary ?? "")
        printView.string = "\(article.title)\n\n\(body)"
        
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        
        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.run()
    }
}
