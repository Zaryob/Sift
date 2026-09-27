import SwiftUI
import SwiftData
import AppIntents
import CryptoKit
import NaturalLanguage
import Translation
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

public struct IdentifiableImageURL: Identifiable {
    public let id: String
    public let url: URL

    public init(_ url: URL) {
        self.id = url.absoluteString
        self.url = url
    }
}

struct ArticleDetailView: View {
    @Bindable var viewModel: AppViewModel
    let article: FeedItem?
    var onBackToList: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var speaker = ArticleSpeaker.shared

    @AppStorage(ReadingPreferenceKey.fontSize) private var readerFontSize: Double = 16.0
    @AppStorage(ReadingPreferenceKey.fontDesign) private var readerFontDesignRaw: String = ReaderFontDesign.serif.rawValue
    @AppStorage(ReadingPreferenceKey.readerTheme) private var readerThemeRaw: String = ReaderTheme.system.rawValue
    @AppStorage(ReadingPreferenceKey.readerLineSpacing) private var readerLineSpacingRaw: String = ReaderLineSpacing.normal.rawValue
    @AppStorage(ReadingPreferenceKey.readerContentWidth) private var readerContentWidthRaw: String = ReaderContentWidth.standard.rawValue
    @AppStorage(ReadingPreferenceKey.openLinksInApp) private var openLinksInApp: Bool = true

    @State private var viewMode: DetailViewMode = .reader
    @State private var isLoadingFullText = false
    @State private var fullTextLoadError: String?
    @State private var fullTextLoadRequestID: UUID?
    @State private var isShowingAppearancePopover = false
    @State private var isShowingAISummary = false
    @State private var selectedLightboxImage: IdentifiableImageURL? = nil

    private var fontDesign: Font.Design {
        (ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .serif).design
    }

    private var readerTheme: ReaderTheme {
        ReaderTheme(rawValue: readerThemeRaw) ?? .system
    }

    private var readerLineSpacing: ReaderLineSpacing {
        ReaderLineSpacing(rawValue: readerLineSpacingRaw) ?? .normal
    }

    private var readerContentWidth: ReaderContentWidth {
        ReaderContentWidth(rawValue: readerContentWidthRaw) ?? .standard
    }

    private var isCurrentArticleSpeaking: Bool {
        guard let article else { return false }
        return speaker.isSpeaking && speaker.currentArticleID == article.id
    }

    private var speakerIcon: String {
        if isCurrentArticleSpeaking {
            return speaker.isPaused ? "play.circle.fill" : "pause.circle.fill"
        }
        return "waveform"
    }

    private var speakerLabel: String {
        if isCurrentArticleSpeaking {
            return speaker.isPaused ? "Resume Listening" : "Pause Listening"
        }
        return "Listen to Article"
    }

    private var speakerHelp: String {
        if isCurrentArticleSpeaking {
            return speaker.isPaused ? "Resume reading aloud" : "Pause reading aloud"
        }
        return "Read article aloud with text-to-speech"
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
                            readerTheme: readerTheme,
                            readerLineSpacing: readerLineSpacing,
                            readerContentWidth: readerContentWidth,
                            isLoadingFullText: isLoadingFullText,
                            isShowingAISummary: $isShowingAISummary,
                            onImageTap: { imageURL in
                                selectedLightboxImage = IdentifiableImageURL(imageURL)
                            }
                        )
                    }
                }
                .navigationTitle(article.feed?.title ?? "")
                .task(id: "\(article.id.uuidString)-\(viewModel.articleOpenRequestID.uuidString)") {
                    isShowingAISummary = false
                    fullTextLoadError = nil
                    await loadFullText(for: article)
                }
                .alert("Article Couldn’t Be Downloaded", isPresented: Binding(
                    get: { fullTextLoadError != nil },
                    set: { if !$0 { fullTextLoadError = nil } }
                )) {
                    Button("Try Again") {
                        Task { await loadFullText(for: article, force: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(fullTextLoadError ?? "An unknown error occurred.")
                }
                .popover(isPresented: $isShowingAppearancePopover) {
                    ReadingAppearancePopover()
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isShowingAISummary.toggle()
                            }
                        } label: {
                            Image(systemName: isShowingAISummary ? "sparkles" : "sparkle")
                                .foregroundStyle(isShowingAISummary ? Color.siftAccent : .primary)
                        }
                        .help("Apple Intelligence Summary")

                        Button {
                            toggleSpeech(for: article)
                        } label: {
                            Image(systemName: speakerIcon)
                                .foregroundStyle(isCurrentArticleSpeaking ? Color.siftAccent : .primary)
                        }
                        .help(speakerHelp)

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
                            isSpeaking: isCurrentArticleSpeaking,
                            speakerIcon: speakerIcon,
                            speakerLabel: speakerLabel,
                            onToggleAISummary: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isShowingAISummary.toggle()
                                }
                            },
                            onToggleSpeech: { toggleSpeech(for: article) },
                            onShowAppearance: { isShowingAppearancePopover = true },
                            onPrint: { printArticle(article) }
                        )
                    }
                }
                .fullScreenCover(item: $selectedLightboxImage) { item in
                    ArticleImageLightboxView(imageURL: item.url)
                }
                .onOpenURL(prefersInApp: openLinksInApp)
                #elseif os(macOS)
                .sheet(item: $selectedLightboxImage) { item in
                    ArticleImageLightboxView(imageURL: item.url)
                        .frame(minWidth: 700, minHeight: 520)
                }
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

    @MainActor
    private func loadFullText(for article: FeedItem, force: Bool = false) async {
        fullTextLoadError = nil
        let shouldLoad = article.extractedArticleData == nil && (force || article.feedWordCount < 400)
        guard shouldLoad else { return }

        let requestID = UUID()
        fullTextLoadRequestID = requestID
        isLoadingFullText = true
        let error = await viewModel.loadFullTextIfNeeded(
            for: article,
            force: force,
            context: modelContext
        )

        guard fullTextLoadRequestID == requestID else { return }
        fullTextLoadRequestID = nil
        isLoadingFullText = false
        guard !Task.isCancelled else { return }
        fullTextLoadError = error
    }

    private func toggleSpeech(for article: FeedItem?) {
        guard let article else { return }
        let text = printableBody(for: article)
        speaker.speak(articleID: article.id, title: article.title, text: text)
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
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isShowingAISummary.toggle()
                }
            } label: {
                Label("AI Summary", systemImage: isShowingAISummary ? "sparkles" : "sparkle")
            }
            .foregroundStyle(isShowingAISummary ? Color.siftAccent : .secondary)
            .help("Summarize with Apple Intelligence")
            .disabled(article == nil)
        }
        .visibilityPriority(.high)

        ToolbarItem(placement: .primaryAction) {
            Button {
                toggleSpeech(for: article)
            } label: {
                Label(speakerLabel, systemImage: speakerIcon)
            }
            .foregroundStyle(isCurrentArticleSpeaking ? Color.siftAccent : .secondary)
            .help(speakerHelp)
            .disabled(article == nil)
        }
        .visibilityPriority(.high)

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isShowingAISummary.toggle()
                    }
                } label: {
                    Label("Apple Intelligence Summary", systemImage: "sparkles")
                }
                .disabled(article == nil)

                Button {
                    isShowingAppearancePopover = true
                } label: {
                    Label("Reading Appearance", systemImage: "textformat.size")
                }
                .disabled(article == nil)

                Button {
                    toggleSpeech(for: article)
                } label: {
                    Label(speakerLabel, systemImage: speakerIcon)
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

// MARK: - Extracted Independent Section Views

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

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.clear
                Rectangle()
                    .fill(Color.siftAccent)
                    .frame(width: max(0, min(CGFloat(progress) * proxy.size.width, proxy.size.width)))
            }
        }
        .frame(height: 2.5)
    }
}

struct AISummaryCard: View {
    let article: FeedItem
    let textColor: Color
    let secondaryColor: Color
    var onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var intelligence = ArticleIntelligenceService.shared
    @State private var summaryText: String?
    @State private var keyPoints: [String] = []
    @State private var topics: [String] = []
    @State private var modelKind: IntelligenceModelKind?
    @State private var isCached: Bool = false
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.siftAccent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Intelligence")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textColor)
                    Text("Summary")
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(secondaryColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing with \(intelligence.activeModelKind?.displayName ?? String(localized: "Apple Intelligence"))…")
                        .font(.system(size: 13))
                        .foregroundStyle(secondaryColor)
                }
                .padding(.vertical, 6)
            } else if let summaryText {
                Text(summaryText)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(textColor)

                AISummaryDetailsView(
                    keyPoints: keyPoints,
                    topics: topics,
                    textColor: textColor,
                    secondaryColor: secondaryColor
                )

                if let modelKind {
                    Text(isCached ? "\(modelKind.displayName) · Saved" : modelKind.displayName)
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                }
            }
        }
        .padding(18)
        .glassEffect(
            .regular.tint(Color.siftAccent.opacity(0.13)),
            in: .rect(cornerRadius: 24)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .task {
            guard summaryText == nil else { return }
            isLoading = true
            let output = await intelligence.summarize(
                article: article,
                context: modelContext
            )
            summaryText = output.text
            keyPoints = output.keyPoints
            topics = output.topics
            modelKind = output.modelKind
            isCached = output.isCached
            isLoading = false
        }
    }
}

private struct AISummaryDetailsView: View {
    let keyPoints: [String]
    let topics: [String]
    let textColor: Color
    let secondaryColor: Color

    var body: some View {
        if !keyPoints.isEmpty || !topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !keyPoints.isEmpty {
                    Text("Key Points")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryColor)

                    ForEach(Array(keyPoints.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(Color.siftAccent)
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(textColor)
                        }
                    }
                }

                if !topics.isEmpty {
                    Text("Topics: \(topics.formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                }
            }
            .padding(.top, 2)
        }
    }
}

struct ArticleReaderScrollView: View {
    let article: FeedItem
    let readerFontSize: Double
    let fontDesign: Font.Design
    let readerTheme: ReaderTheme
    let readerLineSpacing: ReaderLineSpacing
    let readerContentWidth: ReaderContentWidth
    let isLoadingFullText: Bool
    @Binding var isShowingAISummary: Bool
    var onImageTap: ((URL) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @State private var scrollProgress: Double = 0
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var isShowingOriginal = false
    @State private var translationError: String?
    @State private var progressiveTranslation: ExtractedArticle?
    @State private var translationProgress: Double = 0

    private static let translationVersion = 3

    private var textColor: Color {
        readerTheme.textColor(colorScheme: colorScheme)
    }

    private var secondaryColor: Color {
        readerTheme.secondaryTextColor(colorScheme: colorScheme)
    }

    private var targetLanguageCode: String {
        locale.language.languageCode?.identifier
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
    }

    private var cachedTranslation: ExtractedArticle? {
        guard article.translationTargetLanguage == targetLanguageCode,
              article.translationVersion == Self.translationVersion,
              article.translationSourceContentHash == sourceContentHash() else { return nil }
        return article.translatedArticle
    }

    private var isTranslationActive: Bool {
        displayedTranslation != nil && !isShowingOriginal
    }

    private var displayedTranslation: ExtractedArticle? {
        progressiveTranslation ?? cachedTranslation
    }

    private var hasTranslatedTitle: Bool {
        article.translationTargetLanguage == targetLanguageCode
            && article.translatedTitle?.isEmpty == false
            && article.translatedTitle != article.title
    }

    private var displayedTitle: String {
        if !isShowingOriginal, hasTranslatedTitle, let translatedTitle = article.translatedTitle {
            return translatedTitle
        }
        return article.title
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    #if os(macOS)
                    MacArticleHeaderView(
                        article: article,
                        displayTitle: displayedTitle,
                        textColor: textColor,
                        secondaryColor: secondaryColor
                    )
                    Divider().opacity(0.35)
                    #else
                    IOSArticleHeaderView(
                        article: article,
                        displayTitle: displayedTitle,
                        readerFontSize: readerFontSize,
                        fontDesign: fontDesign,
                        textColor: textColor,
                        secondaryColor: secondaryColor
                    )
                    #endif

                    if isTranslating || cachedTranslation != nil || hasTranslatedTitle || translationError != nil {
                        ArticleTranslationStatusView(
                            isTranslating: isTranslating,
                            isShowingOriginal: isShowingOriginal,
                            hasTranslation: displayedTranslation != nil || hasTranslatedTitle,
                            progress: translationProgress,
                            errorMessage: translationError,
                            onToggleOriginal: {
                                withAnimation(.smooth(duration: 0.3)) {
                                    isShowingOriginal.toggle()
                                }
                            }
                        )
                    }

                    if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString) {
                        ArticleHeroImageView(url: imageURL) {
                            onImageTap?(imageURL)
                        }
                    }

                    if isShowingAISummary {
                        AISummaryCard(
                            article: article,
                            textColor: textColor,
                            secondaryColor: secondaryColor,
                            onDismiss: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isShowingAISummary = false
                                }
                            }
                        )
                    }

                    ArticleBodyContentView(
                        article: article,
                        translatedArticle: isTranslationActive ? displayedTranslation : nil,
                        readerFontSize: readerFontSize,
                        fontDesign: fontDesign,
                        lineSpacingMultiplier: readerLineSpacing.multiplier,
                        textColor: textColor,
                        secondaryTextColor: secondaryColor,
                        isLoadingFullText: isLoadingFullText
                    )
                }
                .textSelection(.enabled)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 48)
                .frame(maxWidth: readerContentWidth.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("readerScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "readerScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { minY in
                let scrolled = max(0, -minY)
                let estimatedTotal = max(600, CGFloat(article.readingMinutes ?? 3) * 450)
                let newProgress = min(1.0, Double(scrolled / estimatedTotal))

                // Preference changes are delivered as part of layout. Starting an
                // animation here can ask AppKit to lay out the hierarchy recursively.
                if abs(newProgress - scrollProgress) > 0.001 {
                    scrollProgress = newProgress
                }
            }

            if scrollProgress > 0.02 {
                ReadingProgressBar(progress: scrollProgress)
                    .transition(.opacity)
            }
        }
        .background(readerTheme.backgroundColor(colorScheme: colorScheme).ignoresSafeArea())
        .appEntityIdentifier(
            EntityIdentifier(for: ArticleEntity.self, identifier: article.id)
        )
        .task(id: "\(article.id.uuidString)-\(article.extractedArticleData?.count ?? 0)-\(isLoadingFullText)-\(targetLanguageCode)") {
            prepareAutomaticTranslation()
        }
        .translationTask(translationConfiguration) { session in
            await translateArticle(using: session)
        }
    }

    private func prepareAutomaticTranslation() {
        translationError = nil
        isShowingOriginal = false
        progressiveTranslation = nil
        translationProgress = 0
        guard !isLoadingFullText else { return }
        guard cachedTranslation == nil else { return }

        let blocks = sourceBlocks()
        let sample = blocks.map(\.text).joined(separator: " ").prefix(2_000)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample))
        guard let language = recognizer.dominantLanguage else { return }

        let sourceCode = language.rawValue
        guard sourceCode != targetLanguageCode else { return }

        article.translationSourceLanguage = sourceCode
        if translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: sourceCode),
                target: Locale.Language(identifier: targetLanguageCode),
                preferredStrategy: .highFidelity
            )
        } else {
            translationConfiguration?.invalidate()
        }
    }

    @MainActor
    private func translateArticle(using session: TranslationSession) async {
        let blocks = sourceBlocks()
        guard !blocks.isEmpty else { return }
        let sourceHash = sourceContentHash(for: blocks)
        isTranslating = true
        translationError = nil
        translationProgress = 0
        defer { isTranslating = false }

        var translatedBlocks = blocks
        let chunks = blocks.enumerated().flatMap { blockIndex, block in
            translationChunks(for: block.text).enumerated().map { chunkIndex, text in
                TranslationChunk(
                    blockIndex: blockIndex,
                    chunkIndex: chunkIndex,
                    text: text
                )
            }
        }
        var translatedChunks: [Int: [Int: String]] = [:]

        do {
            for (completedCount, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                let translatedText = try await translateReliably(
                    chunk.text,
                    using: session
                )
                translatedChunks[chunk.blockIndex, default: [:]][chunk.chunkIndex] = translatedText

                let blockChunks = chunks
                    .filter { $0.blockIndex == chunk.blockIndex }
                    .sorted { $0.chunkIndex < $1.chunkIndex }
                translatedBlocks[chunk.blockIndex].text = blockChunks.map { blockChunk in
                    translatedChunks[chunk.blockIndex]?[blockChunk.chunkIndex] ?? blockChunk.text
                }
                .joined(separator: " ")

                translationProgress = Double(completedCount + 1) / Double(max(chunks.count, 1))
                withAnimation(.smooth(duration: 0.35)) {
                    progressiveTranslation = ExtractedArticle(
                        blocks: translatedBlocks,
                        leadImageURL: article.extractedArticle?.leadImageURL
                    )
                }
            }

            let translatedTitle: String
            if let titleResponse = try? await session.translate(article.title) {
                translatedTitle = titleResponse.targetText
            } else {
                translatedTitle = article.title
            }
            let translated = ExtractedArticle(
                blocks: translatedBlocks,
                leadImageURL: article.extractedArticle?.leadImageURL
            )
            // Full-text extraction may have replaced an RSS excerpt while this
            // translation was running. Never cache a result for stale input.
            guard sourceContentHash() == sourceHash else {
                progressiveTranslation = nil
                translationProgress = 0
                return
            }
            article.translatedArticleData = try JSONEncoder().encode(translated)
            article.translatedTitle = translatedTitle
            article.translationTargetLanguage = targetLanguageCode
            article.translationVersion = Self.translationVersion
            article.translationSourceContentHash = sourceHash
            try modelContext.save()
            progressiveTranslation = translated
            translationProgress = 1
        } catch is CancellationError {
            progressiveTranslation = nil
            return
        } catch {
            progressiveTranslation = nil
            translationProgress = 0
            translationError = error.localizedDescription
        }
    }

    private func sourceBlocks() -> [ExtractedArticle.Block] {
        if let extracted = article.extractedArticle {
            return extracted.blocks
        }
        return HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "")
            .map { .init(kind: .paragraph, text: $0) }
    }

    private func sourceContentHash() -> String {
        sourceContentHash(for: sourceBlocks())
    }

    private func sourceContentHash(for blocks: [ExtractedArticle.Block]) -> String {
        let material = ([article.title] + blocks.map(\.text)).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func translationChunks(for text: String, maximumLength: Int = 1_200) -> [String] {
        guard text.count > maximumLength else { return [text] }

        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            sentences.append(String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences where !sentence.isEmpty {
            if sentence.count > maximumLength {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                var remaining = sentence[...]
                while remaining.count > maximumLength {
                    let end = remaining.index(remaining.startIndex, offsetBy: maximumLength)
                    chunks.append(String(remaining[..<end]))
                    remaining = remaining[end...]
                }
                if !remaining.isEmpty { current = String(remaining) }
            } else if current.count + sentence.count + 1 > maximumLength {
                chunks.append(current)
                current = sentence
            } else {
                current += current.isEmpty ? sentence : " " + sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }

    private func translateReliably(
        _ text: String,
        using session: TranslationSession
    ) async throws -> String {
        do {
            return try await session.translate(text).targetText
        } catch {
            guard text.count > 350 else {
                try await Task.sleep(for: .milliseconds(180))
                return try await session.translate(text).targetText
            }

            let smallerChunks = translationChunks(for: text, maximumLength: 350)
            var translated: [String] = []
            translated.reserveCapacity(smallerChunks.count)
            for chunk in smallerChunks {
                try Task.checkCancellation()
                translated.append(try await session.translate(chunk).targetText)
            }
            return translated.joined(separator: " ")
        }
    }
}

private struct TranslationChunk {
    let blockIndex: Int
    let chunkIndex: Int
    let text: String
}

private struct ArticleTranslationStatusView: View {
    let isTranslating: Bool
    let isShowingOriginal: Bool
    let hasTranslation: Bool
    let progress: Double
    let errorMessage: String?
    let onToggleOriginal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTranslating ? "character.book.closed" : "translate")
                .foregroundStyle(Color.siftAccent)
                .symbolEffect(.pulse, isActive: isTranslating)

            VStack(alignment: .leading, spacing: 1) {
                Text(isTranslating ? "Translating article…" : statusTitle)
                    .font(.subheadline.weight(.semibold))
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if hasTranslation {
                    Text("Translated on device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if hasTranslation {
                Button(isShowingOriginal ? "Show Translation" : "View Original", action: onToggleOriginal)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottomLeading) {
            if isTranslating {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.siftAccent)
                        .frame(width: proxy.size.width * progress, height: 2.5)
                        .animation(.smooth(duration: 0.3), value: progress)
                }
                .frame(height: 2.5)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
            }
        }
        .glassEffect(
            .regular.tint(Color.siftAccent.opacity(0.1)),
            in: .rect(cornerRadius: 18)
        )
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: LocalizedStringResource {
        if errorMessage != nil {
            return "Translation unavailable"
        }
        return isShowingOriginal ? "Original article" : "Translation active"
    }
}

#if os(macOS)
struct MacArticleHeaderView: View {
    let article: FeedItem
    let displayTitle: String
    var textColor: Color = .primary
    var secondaryColor: Color = .secondary

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
                        .foregroundStyle(textColor)

                    Spacer()

                    HStack(spacing: 6) {
                        if let category = article.feed?.category, !category.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(category)
                                    .font(.system(size: 11.5))
                            }
                            .foregroundStyle(secondaryColor)
                        }

                        Text(article.publicationDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11.5))
                            .foregroundStyle(secondaryColor)
                    }
                }

                Text(displayTitle.isEmpty ? "Untitled" : displayTitle)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(textColor)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let author = article.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
                        Text("By \(author)")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryColor.opacity(0.6))
                    }

                    if let minutes = article.knownReadingMinutes {
                        Text("\(minutes) min read")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryColor)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryColor.opacity(0.6))
                    }

                    Text(article.publicationDate, format: .dateTime.day().month(.wide).year())
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryColor)
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
    let displayTitle: String
    let readerFontSize: Double
    let fontDesign: Font.Design
    var textColor: Color = .primary
    var secondaryColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayTitle)
                .font(.system(size: min(readerFontSize * 1.25, 23), weight: .semibold, design: fontDesign))
                .foregroundStyle(textColor)
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
            .foregroundStyle(secondaryColor)

            Divider().opacity(0.4)
        }
        .padding(.bottom, 2)
    }
}
#endif

struct ArticleHeroImageView: View {
    let url: URL
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
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
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(8)
                }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

struct ArticleBodyContentView: View {
    let article: FeedItem
    let translatedArticle: ExtractedArticle?
    let readerFontSize: Double
    let fontDesign: Font.Design
    let lineSpacingMultiplier: CGFloat
    let textColor: Color
    let secondaryTextColor: Color
    let isLoadingFullText: Bool
    @State private var cachedParagraphs: [String] = []

    private var paragraphs: [String] {
        if !cachedParagraphs.isEmpty {
            return cachedParagraphs
        }
        return HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "")
    }

    private var irrelevantBlockIDs: Set<Int> {
        let latest = article.intelligenceResults.max { $0.generatedAt < $1.generatedAt }
        return Set(latest?.irrelevantBlockIDs ?? [])
    }

    var body: some View {
        let spacing = readerFontSize * 0.75
        if let extracted = translatedArticle ?? article.extractedArticle {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(extracted.blocks.enumerated()), id: \.offset) { index, block in
                    FilterableArticleBlockView(
                        block: block,
                        isIrrelevant: irrelevantBlockIDs.contains(index),
                        readerFontSize: readerFontSize,
                        fontDesign: fontDesign,
                        lineSpacingMultiplier: lineSpacingMultiplier,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.system(size: readerFontSize, design: fontDesign))
                        .lineSpacing(readerFontSize * lineSpacingMultiplier)
                        .foregroundStyle(textColor)
                }

                if isLoadingFullText {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading the full article…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                } else if article.isExcerpt, let url = article.originalURL {
                    Link(destination: url) {
                        Label("Continue reading on \(url.host() ?? "the website")", systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .font(.body.weight(.medium))
                    .padding(.top, 4)
                }
            }
            .task(id: article.id) {
                cachedParagraphs = HTMLSanitizer.paragraphs(from: article.content ?? article.summary ?? "")
            }
        }
    }
}

private struct FilterableArticleBlockView: View {
    let block: ExtractedArticle.Block
    let isIrrelevant: Bool
    let readerFontSize: Double
    let fontDesign: Font.Design
    let lineSpacingMultiplier: CGFloat
    let textColor: Color
    let secondaryTextColor: Color

    @State private var isRevealed = false

    var body: some View {
        if isIrrelevant && !isRevealed {
            Button {
                withAnimation(.smooth(duration: 0.35)) {
                    isRevealed = true
                }
            } label: {
                IrrelevantContentBand()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Promotional content hidden. Double-tap to reveal.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ArticleBlockRowView(
                    block: block,
                    readerFontSize: readerFontSize,
                    fontDesign: fontDesign,
                    lineSpacingMultiplier: lineSpacingMultiplier,
                    textColor: textColor,
                    secondaryTextColor: secondaryTextColor
                )

                if isIrrelevant {
                    Button("Hide promotional content") {
                        withAnimation(.smooth(duration: 0.3)) {
                            isRevealed = false
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct IrrelevantContentBand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 16, weight: .semibold))

            Text("Promotional content hidden")
                .font(.subheadline.weight(.medium))

            Spacer()

            Image(systemName: "eye")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.82),
                            Color.siftAccent.opacity(0.34),
                            Color.black.opacity(0.76)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Unary container row view for article blocks to preserve List fast path
struct ArticleBlockRowView: View {
    let block: ExtractedArticle.Block
    let readerFontSize: Double
    let fontDesign: Font.Design
    let lineSpacingMultiplier: CGFloat
    let textColor: Color
    let secondaryTextColor: Color

    private var bodyFont: Font {
        .system(size: readerFontSize, design: fontDesign)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch block.kind {
            case .paragraph:
                Text(block.text)
                    .font(bodyFont)
                    .lineSpacing(readerFontSize * lineSpacingMultiplier)
                    .foregroundStyle(textColor)
            case .heading:
                Text(block.text)
                    .font(.system(size: readerFontSize * 1.2, weight: .bold, design: fontDesign))
                    .foregroundStyle(textColor)
                    .padding(.top, readerFontSize * 0.4)
                    .padding(.bottom, readerFontSize * 0.06)
            case .quote:
                Text(block.text)
                    .font(.system(size: readerFontSize * 0.96, design: fontDesign).italic())
                    .lineSpacing(readerFontSize * lineSpacingMultiplier)
                    .foregroundStyle(secondaryTextColor)
                    .padding(.leading, 14)
                    .padding(.vertical, 3)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.siftAccent.opacity(0.6))
                            .frame(width: 3)
                    }
            case .listItem:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(secondaryTextColor)
                    Text(block.text)
                        .lineSpacing(readerFontSize * (lineSpacingMultiplier * 0.85))
                        .foregroundStyle(textColor)
                }
                .font(bodyFont)
            case .code:
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.text)
                        .font(.system(size: max(12, readerFontSize * 0.82), design: .monospaced))
                        .padding(10)
                        .foregroundStyle(textColor)
                }
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

#if os(iOS)
struct ArticleMoreMenu: View {
    let article: FeedItem
    var isSpeaking: Bool = false
    var speakerIcon: String = "waveform"
    var speakerLabel: String = "Listen to Article"
    var onToggleAISummary: () -> Void = {}
    let onToggleSpeech: () -> Void
    let onShowAppearance: () -> Void
    let onPrint: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button(action: onToggleAISummary) {
                Label("Apple Intelligence Summary", systemImage: "sparkles")
            }

            Button(action: onToggleSpeech) {
                Label(speakerLabel, systemImage: speakerIcon)
            }

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
    @AppStorage(ReadingPreferenceKey.readerTheme) private var readerThemeRaw: String = ReaderTheme.system.rawValue
    @AppStorage(ReadingPreferenceKey.readerLineSpacing) private var readerLineSpacingRaw: String = ReaderLineSpacing.normal.rawValue
    @AppStorage(ReadingPreferenceKey.readerContentWidth) private var readerContentWidthRaw: String = ReaderContentWidth.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Theme Palette
            VStack(alignment: .leading, spacing: 6) {
                Text("Theme")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    ForEach(ReaderTheme.allCases) { theme in
                        themeButton(theme)
                    }
                }
            }

            Divider()

            // Typography Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Font")
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

                HStack(spacing: 10) {
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

            Divider()

            // Spacing & Width Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Line Spacing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("Line Spacing", selection: $readerLineSpacingRaw) {
                    ForEach(ReaderLineSpacing.allCases) { spacing in
                        Text(spacing.rawValue).tag(spacing.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Column Width")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("Column Width", selection: $readerContentWidthRaw) {
                    ForEach(ReaderContentWidth.allCases) { width in
                        Text(width.rawValue).tag(width.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(16)
        .frame(width: 250)
    }

    private func themeButton(_ theme: ReaderTheme) -> some View {
        let isSelected = readerThemeRaw == theme.rawValue
        return Button {
            readerThemeRaw = theme.rawValue
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(theme.backgroundColor(colorScheme: colorScheme))
                    .overlay {
                        Circle()
                            .stroke(isSelected ? Color.siftAccent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                    }
                    .overlay {
                        Text("Aa")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(theme.textColor(colorScheme: colorScheme))
                    }
                    .frame(width: 32, height: 32)

                Text(theme.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
