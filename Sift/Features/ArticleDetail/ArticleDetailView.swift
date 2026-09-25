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

    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("readerFontDesign") private var readerFontDesignRaw: String = ReaderFontDesign.system.rawValue
    @State private var showTypographyPopover: Bool = false

    private var currentFontDesign: ReaderFontDesign {
        ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .system
    }

    var body: some View {
        Group {
            if let article = article {
                Group {
                    if viewMode == .web, let linkStr = article.link, let url = URL(string: linkStr) {
                        WebView(url: url)
                    } else {
                        readerContent(article: article)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(DetailViewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .help("Switch between Clean Reader and Web View")

                        if viewMode == .reader {
                            Button {
                                showTypographyPopover.toggle()
                            } label: {
                                Image(systemName: "textformat.size")
                            }
                            .popover(isPresented: $showTypographyPopover) {
                                typographyPopoverContent
                            }
                            .help("Reading Appearance")

                            Button {
                                printArticle(article)
                            } label: {
                                Image(systemName: "printer")
                            }
                            .help("Print or Export Article as PDF")
                        }

                        Button {
                            article.isStarred.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: article.isStarred ? "star.fill" : "star")
                                .foregroundStyle(article.isStarred ? Color.orange : Color.secondary)
                        }
                        .help(article.isStarred ? "Unstar Article" : "Star Article")

                        Button {
                            article.isRead.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: article.isRead ? "circle" : "circle.fill")
                                .foregroundStyle(article.isRead ? Color.secondary : Color.blue)
                        }
                        .help(article.isRead ? "Mark as Unread" : "Mark as Read")

                        if let linkStr = article.link, let url = URL(string: linkStr) {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .help("Share Article")

                            Button {
                                viewModel.openArticleExternally(article)
                            } label: {
                                Image(systemName: "safari")
                            }
                            .help("Open in Web Browser")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Article Selected",
                    systemImage: "newspaper",
                    description: Text("Select an article from the list to start reading.")
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

    @ViewBuilder
    private func readerContent(article: FeedItem) -> some View {
        let rawBody = article.content ?? article.summary ?? ""
        let cleanBody = HTMLSanitizer.stripTags(from: rawBody)
        let readingTime = estimatedReadingTime(text: cleanBody)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header: Feed & Category badge + Metadata
                HStack(spacing: 8) {
                    if let feed = article.feed {
                        FeedFaviconView(feed: feed)
                        Text(feed.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let category = feed.category, !category.isEmpty {
                            Text(category)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text("\(readingTime) min read")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Article Title
                Text(article.title)
                    .font(.system(size: readerFontSize * 1.6, weight: .bold, design: currentFontDesign.design))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Byline & Publication Date
                HStack(spacing: 12) {
                    if let author = article.author, !author.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle")
                            Text(author)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(article.publicationDate, style: .date)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                Divider()

                // Article Body
                if !cleanBody.isEmpty {
                    Text(cleanBody)
                        .font(.system(size: readerFontSize, weight: .regular, design: currentFontDesign.design))
                        .lineSpacing(readerFontSize * 0.38)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 8) {
                        Text("No full text preview available.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .padding(.vertical, 20)
                }

                // Bottom Footer Card
                if let linkStr = article.link, let url = URL(string: linkStr) {
                    Divider()
                        .padding(.top, 16)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Original Source")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(url.host ?? url.absoluteString)
                                .font(.subheadline.weight(.medium))
                        }

                        Spacer()

                        Button {
                            viewModel.openArticleExternally(article)
                        } label: {
                            Label("Open in Browser", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var typographyPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Typography")
                .font(.headline)

            HStack {
                Text("Size")
                    .font(.subheadline)
                Spacer()
                Button {
                    if readerFontSize > 12 { readerFontSize -= 1 }
                } label: {
                    Image(systemName: "minus")
                }
                .controlSize(.small)

                Text("\(Int(readerFontSize)) pt")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .center)

                Button {
                    if readerFontSize < 28 { readerFontSize += 1 }
                } label: {
                    Image(systemName: "plus")
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Font Family")
                    .font(.subheadline)

                Picker("Font", selection: $readerFontDesignRaw) {
                    ForEach(ReaderFontDesign.allCases) { f in
                        Text(f.rawValue).tag(f.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .frame(width: 240)
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
