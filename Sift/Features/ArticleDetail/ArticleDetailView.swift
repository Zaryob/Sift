import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("readerFontDesign") private var readerFontDesignRaw: String = ReaderFontDesign.system.rawValue
    @State private var viewMode: DetailViewMode = .reader
    @State private var showTypographyPopover = false

    private var currentFontDesign: ReaderFontDesign {
        ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .system
    }

    var body: some View {
        Group {
            if let article = article {
                VStack(spacing: 0) {
                    #if os(macOS)
                    headerBar(for: article)
                    Divider()
                    #endif

                    // Main Content: Reader or Web View
                    if viewMode == .web, let linkStr = article.link, let url = URL(string: linkStr) {
                        WebView(url: url)
                    } else {
                        readerScrollView(for: article)
                    }
                }
                .navigationTitle(article.feed?.title ?? "")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // Switch between Reader and Web mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = (viewMode == .reader) ? .web : .reader
                            }
                        } label: {
                            Image(systemName: viewMode == .reader ? "safari" : "doc.plaintext")
                        }
                        .help(viewMode == .reader ? "Switch to Web View" : "Switch to Reader View")

                        // Star Article
                        Button {
                            article.isStarred.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: article.isStarred ? "star.fill" : "star")
                                .foregroundStyle(article.isStarred ? Color.orange : Color.primary)
                        }
                        .help(article.isStarred ? "Remove Star" : "Star Article")

                        // Overflow Action Menu
                        Menu {
                            if viewMode == .reader {
                                Button {
                                    showTypographyPopover.toggle()
                                } label: {
                                    Label("Text Formatting", systemImage: "textformat.size")
                                }
                            }

                            Button {
                                article.isRead.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle")
                            }

                            Button {
                                viewModel.openArticleExternally(article)
                            } label: {
                                Label("Open in Browser", systemImage: "arrow.up.right.square")
                            }

                            if let link = article.link, let url = URL(string: link) {
                                Button {
                                    Platform.copyToPasteboard(url.absoluteString)
                                } label: {
                                    Label("Copy Link", systemImage: "doc.on.doc")
                                }

                                ShareLink(item: url) {
                                    Label("Share...", systemImage: "square.and.arrow.up")
                                }
                            }

                            Divider()

                            Button {
                                printArticle(article)
                            } label: {
                                Label("Print Article", systemImage: "printer")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showTypographyPopover) {
                    NavigationStack {
                        typographyPopoverContent
                            .navigationTitle("Typography")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        showTypographyPopover = false
                                    }
                                }
                            }
                    }
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
                }
                #endif
            } else {
                emptySelectionView
            }
        }
    }

    private var emptySelectionView: some View {
        ContentUnavailableView(
            "No Article Selected",
            systemImage: "doc.text",
            description: Text("Select an article from the list to read its content.")
        )
    }

    #if os(macOS)
    private func headerBar(for article: FeedItem) -> some View {
        HStack(spacing: 12) {
            Picker("View Mode", selection: $viewMode) {
                ForEach(DetailViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Spacer()

            if viewMode == .reader {
                Button {
                    showTypographyPopover.toggle()
                } label: {
                    Label("Text Formatting", systemImage: "textformat.size")
                }
                .help("Adjust font size and style")
                .popover(isPresented: $showTypographyPopover) {
                    typographyPopoverContent
                }
            }

            Button {
                article.isStarred.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isStarred ? "Starred" : "Star", systemImage: article.isStarred ? "star.fill" : "star")
                    .foregroundStyle(article.isStarred ? Color.orange : Color.secondary)
            }
            .help(article.isStarred ? "Remove Star" : "Star Article")

            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isRead ? "Mark Unread" : "Mark Read", systemImage: article.isRead ? "circle" : "checkmark.circle")
            }
            .help(article.isRead ? "Mark as Unread" : "Mark as Read")

            Button {
                viewModel.openArticleExternally(article)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .help("Open original article in default browser")

            Menu {
                Button {
                    printArticle(article)
                } label: {
                    Label("Print Article", systemImage: "printer")
                }

                if let link = article.link, let url = URL(string: link) {
                    Button {
                        Platform.copyToPasteboard(url.absoluteString)
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                }

                Divider()

                ShareLink(item: URL(string: article.link ?? "") ?? URL(string: "https://apple.com")!) {
                    Label("Share...", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif

    private func readerScrollView(for article: FeedItem) -> some View {
        ScrollView {
            let rawContent = article.content ?? article.summary ?? ""
            let cleanBody = HTMLSanitizer.stripTags(from: rawContent)
            let readingTime = estimatedReadingTime(text: cleanBody)

            VStack(alignment: .leading, spacing: 18) {
                // Feed Title & Category & Estimated Reading Time
                HStack(alignment: .center) {
                    if let feed = article.feed {
                        FeedFaviconView(feed: feed)
                        Text(feed.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

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

                if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Rectangle()
                                .fill(Color.secondary.opacity(0.08))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var typographyPopoverContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Typography")
                .font(.headline)

            HStack {
                Text("Text Size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        if readerFontSize > 12 { readerFontSize -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(readerFontSize <= 12)

                    Text("\(Int(readerFontSize)) pt")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .center)

                    Button {
                        if readerFontSize < 28 { readerFontSize += 1 }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(readerFontSize >= 28)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Family")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Font Family", selection: $readerFontDesignRaw) {
                    ForEach(ReaderFontDesign.allCases) { f in
                        Text(f.rawValue).tag(f.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(18)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func estimatedReadingTime(text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return max(1, Int(ceil(Double(words.count) / 200.0)))
    }

    private func printArticle(_ article: FeedItem) {
        #if os(macOS)
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let body = HTMLSanitizer.stripTags(from: article.content ?? article.summary ?? "")
        printView.string = "\(article.title)\n\n\(body)"
        
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        
        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.run()
        #elseif os(iOS)
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = article.title
        printController.printInfo = printInfo
        let body = HTMLSanitizer.stripTags(from: article.content ?? article.summary ?? "")
        let formatter = UIMarkupTextPrintFormatter(markupText: "<h1>\(article.title)</h1><p>\(body)</p>")
        printController.printFormatter = formatter
        printController.present(animated: true, completionHandler: nil)
        #endif
    }
}
