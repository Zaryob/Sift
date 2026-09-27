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
    var onBackToList: (() -> Void)? = nil
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
        Group {
            if let article {
                Group {
                    if viewMode == .web, let url = article.originalURL {
                        WebView(url: url)
                    } else {
                        ArticleReaderScrollView(
                            article: article,
                            readerFontSize: readerFontSize,
                            fontDesign: fontDesign,
                            isLoadingFullText: isLoadingFullText
                        )
                    }
                }
                .navigationTitle(article.feed?.title ?? "")
                .task(id: article.id) {
                    isLoadingFullText = article.extractedArticleData == nil
                    await viewModel.loadFullTextIfNeeded(for: article, context: modelContext)
                    isLoadingFullText = false
                }
                .popover(isPresented: $isShowingAppearancePopover) {
                    ReadingAppearancePopover()
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

                        ArticleMoreMenu(
                            article: article,
                            onShowAppearance: { isShowingAppearancePopover = true },
                            onPrint: { printArticle(article) }
                        )
                    }
                }
                .onOpenURL(prefersInApp: openLinksInApp)
                #endif
            } else {
                EmptyArticleDetailView()
            }
        }
        #if os(macOS)
        .toolbar {
            macOSToolbarItems(for: article)
        }
        #endif
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private func macOSToolbarItems(for article: FeedItem?) -> some ToolbarContent {
        if article != nil {
            activeArticleToolbarItems(for: article)
        } else {
            ToolbarSpacer(.flexible, placement: .automatic)
        }
    }

    @ToolbarContentBuilder
    private func activeArticleToolbarItems(for article: FeedItem?) -> some ToolbarContent {
        if let onBackToList {
            ToolbarItem(placement: .navigation) {
                Button(action: onBackToList) {
                    Label("Articles", systemImage: "chevron.backward")
                }
                .help("Back to Articles")
            }
        }

        ToolbarItem(placement: .automatic) {
            Picker("View Mode", selection: $viewMode) {
                ForEach(DetailViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(article == nil)
        }
        .visibilityPriority(.high)

        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                Button {
                    if let article {
                        article.isRead.toggle()
                        try? modelContext.save()
                    }
                } label: {
                    Label(article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                          systemImage: article?.isRead == true ? "envelope.badge" : "envelope.open")
                        .font(.system(size: 16, weight: .medium))
                        .frame(minWidth: 30, minHeight: 30)
                }
                .help(article?.isRead == true ? "Mark as Unread (M)" : "Mark as Read (M)")
                .disabled(article == nil)

                Button {
                    if let article {
                        article.isStarred.toggle()
                        try? modelContext.save()
                    }
                } label: {
                    Label(article?.isStarred == true ? "Unstar" : "Star",
                          systemImage: article?.isStarred == true ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .medium))
                        .frame(minWidth: 30, minHeight: 30)
                }
                .foregroundStyle(article?.isStarred == true ? Color.siftStarred : .secondary)
                .help(article?.isStarred == true ? "Remove Star (S)" : "Star Article (S)")
                .disabled(article == nil)
            }
        }
        .visibilityPriority(.high)

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isShowingAppearancePopover = true
                } label: {
                    Label("Reading Appearance", systemImage: "textformat.size")
                }
                .disabled(article == nil)

                Divider()

                if let article, article.originalURL != nil {
                    Button {
                        viewModel.openArticleExternally(article)
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }

                    Divider()
                }

                if let url = article?.originalURL {
                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        Platform.copyToPasteboard(url.absoluteString)
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                }

                Button {
                    if let article {
                        printArticle(article)
                    }
                } label: {
                    Label("Print…", systemImage: "printer")
                }
                .disabled(article == nil)

                Divider()

                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .help("More Actions")
        }
        .visibilityPriority(.high)
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

// MARK: - Extracted Independent Section Views (swiftui-specialist-ref-structure)

struct EmptyArticleDetailView: View {
    var body: some View {
        #if os(macOS)
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No Article Selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Select an article from the list to read it.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        ContentUnavailableView(
            "No Article Selected",
            systemImage: "doc.text",
            description: Text("Select an article from the list to read it.")
        )
        #endif
    }
}

struct ArticleReaderScrollView: View {
    let article: FeedItem
    let readerFontSize: Double
    let fontDesign: Font.Design
    let isLoadingFullText: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if os(macOS)
                MacArticleHeaderView(article: article)
                Divider().opacity(0.35)
                #else
                IOSArticleHeaderView(
                    article: article,
                    readerFontSize: readerFontSize,
                    fontDesign: fontDesign
                )
                #endif

                if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString) {
                    ArticleHeroImageView(url: imageURL)
                }

                ArticleBodyContentView(
                    article: article,
                    readerFontSize: readerFontSize,
                    fontDesign: fontDesign,
                    isLoadingFullText: isLoadingFullText
                )
            }
            .textSelection(.enabled)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 48)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

#if os(macOS)
struct MacArticleHeaderView: View {
    let article: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let feed = article.feed {
                FeedFaviconView(feed: feed, size: 34, cornerRadius: 7)
            } else {
                FeedFaviconView(title: article.feed?.title ?? article.author ?? "Feed", size: 34, cornerRadius: 7)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(article.feed?.title ?? article.author ?? "Feed")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 6) {
                        if let category = article.feed?.category, !category.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(category)
                                    .font(.system(size: 11.5))
                            }
                            .foregroundStyle(.secondary)
                        }

                        Text(article.publicationDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(article.title.isEmpty ? "Untitled" : article.title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let author = article.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                        Text("By \(author)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    if let minutes = article.knownReadingMinutes {
                        Text("\(minutes) min read")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Text(article.publicationDate, format: .dateTime.day().month(.wide).year())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.bottom, 4)
    }
}
#endif

#if os(iOS)
struct IOSArticleHeaderView: View {
    let article: FeedItem
    let readerFontSize: Double
    let fontDesign: Font.Design

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(article.title)
                .font(.system(size: min(readerFontSize * 1.25, 23), weight: .semibold, design: fontDesign))
                .lineSpacing(readerFontSize * 0.12)
                .fixedSize(horizontal: false, vertical: true)

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

            Divider().opacity(0.4)
        }
        .padding(.bottom, 2)
    }
}
#endif

struct ArticleHeroImageView: View {
    let url: URL

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.vertical, 2)
    }
}

struct ArticleBodyContentView: View {
    let article: FeedItem
    let readerFontSize: Double
    let fontDesign: Font.Design
    let isLoadingFullText: Bool

    private var paragraphs: [String] {
        HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "")
    }

    var body: some View {
        let spacing = readerFontSize * 0.75
        if let extracted = article.extractedArticle {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(extracted.blocks, id: \.self) { block in
                    ArticleBlockRowView(
                        block: block,
                        readerFontSize: readerFontSize,
                        fontDesign: fontDesign
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.system(size: readerFontSize, design: fontDesign))
                        .lineSpacing(readerFontSize * 0.32)
                }

                if isLoadingFullText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
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
}

/// Unary container row view for article blocks to preserve List fast path
struct ArticleBlockRowView: View {
    let block: ExtractedArticle.Block
    let readerFontSize: Double
    let fontDesign: Font.Design

    private var bodyFont: Font {
        .system(size: readerFontSize, design: fontDesign)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    Text("•").foregroundStyle(.secondary)
                    Text(block.text).lineSpacing(readerFontSize * 0.28)
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
    }
}

#if os(iOS)
struct ArticleMoreMenu: View {
    let article: FeedItem
    let onShowAppearance: () -> Void
    let onPrint: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button(action: onShowAppearance) {
                Label("Reading Appearance", systemImage: "textformat.size")
            }

            Divider()

            Button {
                article.isRead.toggle()
                try? modelContext.save()
            } label: {
                Label(article.isRead ? "Mark as Unread" : "Mark as Read",
                      systemImage: article.isRead ? "circle" : "checkmark.circle")
            }

            Divider()

            if let url = article.originalURL {
                ShareLink(item: url) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }

                Button {
                    Platform.copyToPasteboard(url.absoluteString)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }

                Button {
                    openURL(url)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
            }

            Button(action: onPrint) {
                Label("Print…", systemImage: "printer")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
#endif

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
        guard let link else { return nil }
        return URL(string: link)
    }
}
