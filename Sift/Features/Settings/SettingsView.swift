import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct OPMLFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var scheduler = BackgroundFeedScheduler.shared
    @StateObject private var launchAgentManager = LaunchAgentManager.shared
    @Query private var feeds: [Feed]
    @Query private var articles: [FeedItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(ReadingPreferenceKey.density) private var densityRaw: String = ArticleDensity.comfortable.rawValue
    @AppStorage(ReadingPreferenceKey.markReadBehavior) private var markReadRaw: String = MarkReadBehavior.whenOpened.rawValue
    @AppStorage(ReadingPreferenceKey.openLinksInApp) private var openLinksInApp: Bool = true
    @AppStorage(ReadingPreferenceKey.fontSize) private var fontSize: Double = 16.0
    @AppStorage(ReadingPreferenceKey.fontDesign) private var fontDesignRaw: String = ReaderFontDesign.serif.rawValue
    @AppStorage(ReadingPreferenceKey.showFeedIcons) private var showFeedIcons: Bool = true
    @AppStorage(ReadingPreferenceKey.showArticlePreviews) private var showArticlePreviews: Bool = true
    @AppStorage(ReadingPreferenceKey.readerTheme) private var readerThemeRaw: String = ReaderTheme.system.rawValue
    @AppStorage(ReadingPreferenceKey.readerLineSpacing) private var readerLineSpacingRaw: String = ReaderLineSpacing.normal.rawValue
    @AppStorage(ReadingPreferenceKey.readerContentWidth) private var readerContentWidthRaw: String = ReaderContentWidth.standard.rawValue
    @AppStorage(NotificationManager.articleAlertsEnabledKey) private var articleAlertsEnabled: Bool = true
    @AppStorage("articleRetentionDays") private var articleRetentionDays: Int = 30

    @State private var isPruning: Bool = false
    @State private var pruningFeedbackMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var opmlStatusMessage: String?
    @State private var isImporting: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingFileExporter: Bool = false
    @State private var exportDocument: OPMLFileDocument?

    private var fontDesign: ReaderFontDesign {
        ReaderFontDesign(rawValue: fontDesignRaw) ?? .serif
    }

    /// Preview with the reader's own latest article rather than a sample sentence.
    private var previewText: String {
        guard let latest = articles.max(by: { $0.publicationDate < $1.publicationDate }) else {
            return String(localized: "Articles you open in Sift will use this font and size.")
        }
        let excerpt = HTMLSanitizer.stripTags(from: latest.summary ?? latest.content ?? "")
        return excerpt.isEmpty ? latest.title : String(excerpt.prefix(120))
    }

    var body: some View {
        content
            .task(id: scenePhase) {
                // Re-read on becoming active so returning from System Settings updates the switch.
                await refreshNotificationStatus()
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.xml, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .fileExporter(
                isPresented: $isShowingFileExporter,
                document: exportDocument,
                contentType: .xml,
                defaultFilename: "sift_subscriptions.opml"
            ) { result in
                switch result {
                case .success:
                    opmlStatusMessage = "Exported \(feeds.count) subscriptions."
                case .failure(let error):
                    opmlStatusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        TabView {
            Form {
                refreshSection
                notificationsSection
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                readingSection
                articleTextSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Reading", systemImage: "text.book.closed") }

            Form {
                librarySection
                opmlSection
            }
            .formStyle(.grouped)
            .tabItem { Label("Subscriptions", systemImage: "tray.and.arrow.down") }
        }
        .frame(width: 520, height: 420)
        #else
        Form {
            readingSection
            articleTextSection
            refreshSection
            notificationsSection
            librarySection
            opmlSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Reading

    private var readingSection: some View {
        Section {
            Picker("Article List", selection: $densityRaw) {
                ForEach(ArticleDensity.allCases) { density in
                    Text(density.rawValue).tag(density.rawValue)
                }
            }
            Picker("Mark as Read", selection: $markReadRaw) {
                ForEach(MarkReadBehavior.allCases) { behavior in
                    Text(behavior.rawValue).tag(behavior.rawValue)
                }
            }
            Toggle("Show Feed Icons", isOn: $showFeedIcons)
            Toggle("Show Article Previews", isOn: $showArticlePreviews)
            #if os(iOS)
            Picker("Open Original Article", selection: $openLinksInApp) {
                Text("In Sift").tag(true)
                Text("In Safari").tag(false)
            }
            #endif
        } header: {
            Text("Reading")
        } footer: {
            #if os(iOS)
            Text("“In Sift” shows the publisher’s page in a browser view without leaving the app.")
            #else
            Text("Compact shows only headlines and source, so more articles fit on screen.")
            #endif
        }
    }

    private var articleTextSection: some View {
        Section("Reader Appearance") {
            Picker("Theme", selection: $readerThemeRaw) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }

            Picker("Font", selection: $fontDesignRaw) {
                ForEach(ReaderFontDesign.allCases) { design in
                    Text(design.rawValue).tag(design.rawValue)
                }
            }

            Stepper(value: $fontSize, in: 12...28, step: 1) {
                LabeledContent("Text Size") {
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                }
            }

            Picker("Line Spacing", selection: $readerLineSpacingRaw) {
                ForEach(ReaderLineSpacing.allCases) { spacing in
                    Text(spacing.rawValue).tag(spacing.rawValue)
                }
            }

            Picker("Column Width", selection: $readerContentWidthRaw) {
                ForEach(ReaderContentWidth.allCases) { width in
                    Text(width.rawValue).tag(width.rawValue)
                }
            }

            Text(previewText)
                .font(.system(size: fontSize, design: fontDesign.design))
                .lineSpacing(fontSize * (ReaderLineSpacing(rawValue: readerLineSpacingRaw) ?? .normal).multiplier)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.vertical, 2)
        }
    }

    // MARK: - Refresh

    @ViewBuilder
    private var refreshSection: some View {
        #if os(macOS)
        Section {
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItemManager.isLaunchAtLoginEnabled },
                set: { loginItemManager.setLaunchAtLogin(enabled: $0) }
            ))

            Picker("Refresh Frequency", selection: $scheduler.refreshIntervalMinutes) {
                Text("Every 5 Minutes").tag(5)
                Text("Every 15 Minutes").tag(15)
                Text("Every 30 Minutes").tag(30)
                Text("Every Hour").tag(60)
                Text("Manually").tag(0)
            }
        } header: {
            Text("Background Refresh")
        } footer: {
            Text("Sift continues refreshing your feeds while open or running in the menu bar, and schedules background updates using native macOS scheduling.")
        }
        #else
        Section {
            Picker("Preferred Frequency", selection: $scheduler.refreshIntervalMinutes) {
                Text("Every 15 Minutes").tag(15)
                Text("Every 30 Minutes").tag(30)
                Text("Every Hour").tag(60)
                Text("Manually").tag(0)
            }
        } header: {
            Text("Background Refresh")
        } footer: {
            Text("Background updates are scheduled by iOS based on system activity, battery level, and network availability.")
        }
        #endif
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("New Article Alerts", isOn: articleAlertsBinding)
        } header: {
            Text("Notifications")
        } footer: {
            if notificationStatus == .denied {
                Text("Notifications for Sift are turned off in System Settings. Turning this on opens them.")
            } else {
                Text("Get notified when new articles arrive in the background.")
            }
        }
    }

    private var isNotificationPermissionGranted: Bool {
        switch notificationStatus {
        case .authorized, .provisional:
            return true
        #if os(iOS)
        case .ephemeral:
            return true
        #endif
        default:
            return false
        }
    }

    /// A real switch: it reflects both Sift's own preference and the system permission, and asks
    /// for (or points to) the permission when needed instead of showing a status label.
    private var articleAlertsBinding: Binding<Bool> {
        Binding(
            get: { articleAlertsEnabled && isNotificationPermissionGranted },
            set: { isOn in
                guard isOn else {
                    articleAlertsEnabled = false
                    return
                }
                switch notificationStatus {
                case .denied:
                    openSystemNotificationSettings()
                case .notDetermined:
                    Task {
                        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                        articleAlertsEnabled = granted
                        await refreshNotificationStatus()
                    }
                default:
                    articleAlertsEnabled = true
                }
            }
        )
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSystemNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
        }
        #endif
    }

    // MARK: - Subscriptions & Storage

    private var librarySection: some View {
        Section {
            LabeledContent("Subscriptions", value: feeds.count.formatted())
            LabeledContent("Stored Articles", value: articles.count.formatted())

            Picker("Keep Read Articles", selection: $articleRetentionDays) {
                Text("7 Days").tag(7)
                Text("14 Days").tag(14)
                Text("30 Days (Recommended)").tag(30)
                Text("90 Days").tag(90)
                Text("Keep All").tag(0)
            }

            Button {
                Task {
                    isPruning = true
                    let pruningService = DataPruningService(modelContainer: modelContext.container)
                    let result = try? await pruningService.prune(readRetentionDays: articleRetentionDays)
                    isPruning = false
                    if let result {
                        pruningFeedbackMessage = "Cleaned \(result.totalPruned) expired articles."
                    }
                }
            } label: {
                if isPruning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Pruning articles…")
                    }
                } else {
                    settingsActionLabel("Clean Old Articles Now", systemImage: "trash")
                }
            }
            .disabled(isPruning)
        } header: {
            Text("Storage & Retention")
        } footer: {
            if let msg = pruningFeedbackMessage {
                Text(msg)
                    .foregroundStyle(Color.siftAccent)
            } else {
                Text("Starred articles are never removed. Read articles older than the chosen retention period are automatically cleaned up to keep Sift fast.")
            }
        }
    }

    private var opmlSection: some View {
        Section {
            Button {
                isShowingFileImporter = true
            } label: {
                settingsActionLabel("Import OPML File", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)

            Button {
                exportOPML()
            } label: {
                settingsActionLabel("Export OPML File", systemImage: "square.and.arrow.up")
            }
            .disabled(feeds.isEmpty)
        } header: {
            Text("OPML")
        } footer: {
            if let message = opmlStatusMessage {
                Text(message)
            } else {
                Text("Move your subscriptions between Sift and other RSS readers.")
            }
        }
    }

    private func settingsActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            opmlStatusMessage = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let items = try OPMLService().parse(data: try Data(contentsOf: url))
                var importedCount = 0
                for item in items {
                    let targetURL = item.xmlURL
                    let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == targetURL })
                    if (try? modelContext.fetch(descriptor).first) == nil {
                        modelContext.insert(Feed(
                            title: item.title,
                            url: item.xmlURL,
                            siteURL: item.htmlURL,
                            category: item.category,
                            dateAdded: Date()
                        ))
                        importedCount += 1
                    }
                }
                try modelContext.save()
                opmlStatusMessage = "Imported \(importedCount) new subscriptions."

                isImporting = true
                Task {
                    await FeedRefreshService().refreshAllFeeds()
                    isImporting = false
                }
            } catch {
                opmlStatusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportOPML() {
        exportDocument = OPMLFileDocument(text: OPMLService.generateOPML(from: feeds))
        isShowingFileExporter = true
    }
}
