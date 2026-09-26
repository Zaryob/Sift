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

struct ArticleDetailView: View {
    @Bindable var viewModel: AppViewModel
    let article: FeedItem?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @AppStorage(ReadingPreferenceKey.fontSize) private var readerFontSize: Double = 16.0
    @AppStorage(ReadingPreferenceKey.fontDesign) private var readerFontDesignRaw: String = ReaderFontDesign.serif.rawValue
    @AppStorage(ReadingPreferenceKey.openLinksInApp) private var openLinksInApp: Bool = true
    @State private var viewMode: DetailViewMode = .reader
    @State private var isLoadingFullText = false
    @State private var isShowingAppearancePopover = false

    private var fontDesign: Font.Design {
        (ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .serif).design
    }

    var body: some View {
        if let article {
            VStack(spacing: 0) {
                #if os(macOS)
                headerBar(for: article)
                Divider()
                #endif

                if viewMode == .web, let url = article.originalURL {
                    WebView(url: url)
                } else {
                    reader(for: article)
                }
            }
            .navigationTitle(article.feed?.title ?? "")
            .task(id: article.id) {
                isLoadingFullText = article.extractedArticleData == nil
                await viewModel.loadFullTextIfNeeded(for: article, context: modelContext)
                isLoadingFullText = false
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        article.isStarred.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: article.isStarred ? "star.fill" : "star")
                            .foregroundStyle(article.isStarred ? Color.siftStarred : .primary)
                    }
                    .help(article.isStarred ? "Remove Star" : "Star Article")

                    moreMenu(for: article)
                }
            }
            .popover(isPresented: $isShowingAppearancePopover) {
                ReadingAppearancePopover()
            }
            // Applies to the Open Original button and in-article links: Safari view vs. Safari app.
            .onOpenURL(prefersInApp: openLinksInApp)
            #endif
        } else {
            ContentUnavailableView(
                "No Article Selected",
                systemImage: "doc.text",
                description: Text("Select an article from the list to read it.")
            )
        }
    }

    // MARK: - Reader

    private func reader(for article: FeedItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metadataLine(for: article)

                Text(article.title)
                    .font(.system(size: min(readerFontSize * 1.3, 24), weight: .bold, design: fontDesign))
                    .lineSpacing(readerFontSize * 0.08)
                    .fixedSize(horizontal: false, vertical: true)

                if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .overlay {
                            AsyncImage(url: imageURL) { phase in
                                if case .success(let image) = phase {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.vertical, 2)
                }

                articleBody(for: article)
            }
            .textSelection(.enabled)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 44)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Editorial hierarchy: Author/Source · Publication Date · Reading Time
    private func metadataLine(for article: FeedItem) -> some View {
        HStack(spacing: 5) {
            if let author = article.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                Text(author)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("·")
            } else if let feed = article.feed {
                Text(feed.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("·")
            }

            Text(article.publicationDate, format: .dateTime.day().month(.wide).year())

            if let minutes = article.knownReadingMinutes {
                Text("·")
                Text("\(minutes) min read")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func articleBody(for article: FeedItem) -> some View {
        let spacing = readerFontSize * 0.75
        if let extracted = article.extractedArticle {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(extracted.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "").enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(bodyFont)
                        .lineSpacing(readerFontSize * 0.32)
                }

                if isLoadingFullText {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading the full article…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else if let url = article.originalURL {
                    Link(destination: url) {
                        Label("Continue reading on \(url.host() ?? "the website")", systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .font(.body.weight(.medium))
                    .padding(.top, 4)
                }
            }
        }
    }

    private var bodyFont: Font {
        .system(size: readerFontSize, design: fontDesign)
    }

    @ViewBuilder
    private func blockView(_ block: ExtractedArticle.Block) -> some View {
        switch block.kind {
        case .paragraph:
            Text(block.text)
                .font(bodyFont)
                .lineSpacing(readerFontSize * 0.32)
        case .heading:
            Text(block.text)
                .font(.system(size: readerFontSize * 1.2, weight: .bold, design: fontDesign))
                .padding(.top, readerFontSize * 0.4)
                .padding(.bottom, readerFontSize * 0.06)
        case .quote:
            Text(block.text)
                .font(.system(size: readerFontSize * 0.96, design: fontDesign).italic())
                .lineSpacing(readerFontSize * 0.32)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .padding(.vertical, 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 3)
                }
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(block.text)
                    .lineSpacing(readerFontSize * 0.28)
            }
            .font(bodyFont)
        case .code:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.text)
                    .font(.system(size: max(12, readerFontSize * 0.82), design: .monospaced))
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Actions

    #if os(iOS)
    private func moreMenu(for article: FeedItem) -> some View {
        Menu {
            Button {
                isShowingAppearancePopover = true
            } label: {
                Label("Text Size & Font…", systemImage: "textformat.size")
            }

            if let url = article.originalURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }

                ShareLink(item: url) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }

                Button {
                    Platform.copyToPasteboard(url.absoluteString)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }

            Divider()

            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isRead ? "Mark as Unread" : "Mark as Read", systemImage: article.isRead ? "circlebadge" : "checkmark.circle")
            }

            Button {
                printArticle(article)
            } label: {
                Label("Print", systemImage: "printer")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    #endif

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

            Button {
                isShowingAppearancePopover.toggle()
            } label: {
                Label("Appearance", systemImage: "textformat.size")
            }
            .popover(isPresented: $isShowingAppearancePopover) {
                ReadingAppearancePopover()
            }
            .help("Reading Appearance")

            Button {
                article.isStarred.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isStarred ? "Starred" : "Star", systemImage: article.isStarred ? "star.fill" : "star")
                    .foregroundStyle(article.isStarred ? Color.siftStarred : Color.secondary)
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
            .help("Open the original article in your browser")

            Menu {
                Button {
                    printArticle(article)
                } label: {
                    Label("Print Article", systemImage: "printer")
                }

                if let url = article.originalURL {
                    Button {
                        Platform.copyToPasteboard(url.absoluteString)
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }

                    Divider()

                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
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

    private func printableBody(for article: FeedItem) -> String {
        if let extracted = article.extractedArticle {
            return extracted.blocks.map(\.text).joined(separator: "\n\n")
        }
        return HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "").joined(separator: "\n\n")
    }

    private func printArticle(_ article: FeedItem) {
        let body = printableBody(for: article)
        #if os(macOS)
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        printView.string = "\(article.title)\n\n\(body)"

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        NSPrintOperation(view: printView, printInfo: printInfo).run()
        #elseif os(iOS)
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = article.title
        printController.printInfo = printInfo
        let paragraphs = body.components(separatedBy: "\n\n").map { "<p>\(escapeHTML($0))</p>" }.joined()
        printController.printFormatter = UIMarkupTextPrintFormatter(markupText: "<h1>\(escapeHTML(article.title))</h1>\(paragraphs)")
        printController.present(animated: true, completionHandler: nil)
        #endif
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Floating popover for in-article typography and appearance adjustments
struct ReadingAppearancePopover: View {
    @AppStorage(ReadingPreferenceKey.fontSize) private var readerFontSize: Double = 16.0
    @AppStorage(ReadingPreferenceKey.fontDesign) private var readerFontDesignRaw: String = ReaderFontDesign.serif.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker("Font Design", selection: $readerFontDesignRaw) {
                ForEach(ReaderFontDesign.allCases) { design in
                    Text(design.rawValue).tag(design.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 12) {
                Button {
                    if readerFontSize > 13 {
                        readerFontSize -= 1
                    }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .frame(maxWidth: .infinity)
                }
                .disabled(readerFontSize <= 13)

                Text("\(Int(readerFontSize)) pt")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .frame(minWidth: 46)

                Button {
                    if readerFontSize < 26 {
                        readerFontSize += 1
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .frame(maxWidth: .infinity)
                }
                .disabled(readerFontSize >= 26)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 210)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}

extension FeedItem {
    var originalURL: URL? {
        link.flatMap(URL.init(string:))
    }
}
