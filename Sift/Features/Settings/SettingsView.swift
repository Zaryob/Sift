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

    @AppStorage(ReadingPreferenceKey.density) private var densityRaw: String = ArticleDensity.comfortable.rawValue
    @AppStorage(ReadingPreferenceKey.markReadOnOpen) private var markReadOnOpen: Bool = true
    @AppStorage(ReadingPreferenceKey.openLinksInApp) private var openLinksInApp: Bool = true
    @AppStorage(ReadingPreferenceKey.fontSize) private var fontSize: Double = 16.0
    @AppStorage(ReadingPreferenceKey.fontDesign) private var fontDesignRaw: String = ReaderFontDesign.system.rawValue

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var opmlStatusMessage: String?
    @State private var isImporting: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingFileExporter: Bool = false
    @State private var exportDocument: OPMLFileDocument?

    private var fontDesign: ReaderFontDesign {
        ReaderFontDesign(rawValue: fontDesignRaw) ?? .system
    }

    var body: some View {
        content
            .task {
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
            Toggle("Mark as Read When Opened", isOn: $markReadOnOpen)
            #if os(iOS)
            Toggle("Open Links in Sift", isOn: $openLinksInApp)
            #endif
        } header: {
            Text("Reading")
        } footer: {
            Text("Compact shows only headlines and source, so more articles fit on screen.")
        }
    }

    private var articleTextSection: some View {
        Section("Article Text") {
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

            Text("Sift keeps the signal and lets the noise fall through.")
                .font(.system(size: fontSize, design: fontDesign.design))
                .lineSpacing(fontSize * 0.3)
                .padding(.vertical, 4)
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

            Toggle("Refresh While Sift Is Closed", isOn: Binding(
                get: { launchAgentManager.isEnabled },
                set: { launchAgentManager.setEnabled($0, intervalMinutes: scheduler.refreshIntervalMinutes > 0 ? scheduler.refreshIntervalMinutes : 15) }
            ))

            Picker("Check for New Articles", selection: Binding(
                get: { scheduler.refreshIntervalMinutes },
                set: { newInterval in
                    scheduler.refreshIntervalMinutes = newInterval
                    if launchAgentManager.isEnabled {
                        launchAgentManager.setEnabled(true, intervalMinutes: newInterval > 0 ? newInterval : 15)
                    }
                }
            )) {
                Text("Every 5 Minutes").tag(5)
                Text("Every 15 Minutes").tag(15)
                Text("Every 30 Minutes").tag(30)
                Text("Every Hour").tag(60)
                Text("Manually").tag(0)
            }
        } header: {
            Text("Background Refresh")
        }
        #else
        Section {
            Picker("Check for New Articles", selection: $scheduler.refreshIntervalMinutes) {
                Text("Every 15 Minutes").tag(15)
                Text("Every 30 Minutes").tag(30)
                Text("Every Hour").tag(60)
                Text("Manually").tag(0)
            }
        } header: {
            Text("Background Refresh")
        } footer: {
            Text("iOS decides the exact timing based on how often you use Sift and your battery level.")
        }
        #endif
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent("New Article Alerts") {
                notificationStatusControl
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Sift can notify you when new articles arrive in the background.")
        }
    }

    @ViewBuilder
    private var notificationStatusControl: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            Text("On")
                .foregroundStyle(.secondary)
        case .denied:
            Button("Turn On in Settings") {
                openSystemNotificationSettings()
            }
        case .notDetermined:
            Button("Turn On") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await refreshNotificationStatus()
                }
            }
        @unknown default:
            EmptyView()
        }
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

    // MARK: - Subscriptions

    private var librarySection: some View {
        Section("Library") {
            LabeledContent("Subscriptions", value: feeds.count.formatted())
            LabeledContent("Stored Articles", value: articles.count.formatted())
        }
    }

    private var opmlSection: some View {
        Section {
            Button {
                isShowingFileImporter = true
            } label: {
                settingsActionLabel("Import from OPML…", systemImage: "square.and.arrow.down")
            }
            .disabled(isImporting)

            Button {
                exportOPML()
            } label: {
                settingsActionLabel("Export as OPML…", systemImage: "square.and.arrow.up")
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
                .foregroundStyle(Color.accentColor)
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
