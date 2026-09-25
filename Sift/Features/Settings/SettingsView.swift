import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var scheduler = BackgroundFeedScheduler.shared
    @StateObject private var launchAgentManager = LaunchAgentManager.shared
    @Query private var feeds: [Feed]
    @Query private var articles: [FeedItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("readerFontDesign") private var readerFontDesignRaw: String = ReaderFontDesign.system.rawValue

    @State private var opmlStatusMessage: String?
    @State private var isImporting: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingFileExporter: Bool = false
    @State private var exportDocument: OPMLFileDocument?

    var body: some View {
        NavigationStack {
            TabView {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                readingTab
                    .tabItem {
                        Label("Reading", systemImage: "textformat")
                    }

                subscriptionsTab
                    .tabItem {
                        Label("Subscriptions", systemImage: "tray.and.arrow.down")
                    }
            }
            .navigationTitle("Settings")
            #if os(macOS)
            .frame(width: 520, height: 380)
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
            .onAppear {
                NotificationManager.shared.requestAuthorization()
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
                    opmlStatusMessage = "Successfully exported \(feeds.count) feeds to OPML."
                case .failure(let error):
                    opmlStatusMessage = "OPML Export Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            #if os(macOS)
            Section("Startup & Background") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isLaunchAtLoginEnabled },
                    set: { loginItemManager.setLaunchAtLogin(enabled: $0) }
                ))
                .help("Automatically start Sift when you log into macOS.")

                Toggle("Background Service (launchd)", isOn: Binding(
                    get: { launchAgentManager.isEnabled },
                    set: { launchAgentManager.setEnabled($0, intervalMinutes: scheduler.refreshIntervalMinutes > 0 ? scheduler.refreshIntervalMinutes : 15) }
                ))
                .help("Allows macOS launchd daemon to periodically check RSS feeds even when Sift is completely closed.")

                Picker("Background Refresh Interval", selection: Binding(
                    get: { scheduler.refreshIntervalMinutes },
                    set: { newInterval in
                        scheduler.refreshIntervalMinutes = newInterval
                        if launchAgentManager.isEnabled {
                            launchAgentManager.setEnabled(true, intervalMinutes: newInterval > 0 ? newInterval : 15)
                        }
                    }
                )) {
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes (Default)").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Manual Only").tag(0)
                }
                .help("How frequently Sift checks for new feed articles in the background.")
            }
            #else
            Section("Background Refresh") {
                Picker("Refresh Interval", selection: $scheduler.refreshIntervalMinutes) {
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes (Default)").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Manual Only").tag(0)
                }
            }
            #endif

            Section("Notifications") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Article Alerts")
                        Text("Sift notifies you when newly published articles arrive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Permissions") {
                        NotificationManager.shared.requestAuthorization()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var readingTab: some View {
        Form {
            Section("Typography & Display") {
                Picker("Font Family", selection: $readerFontDesignRaw) {
                    ForEach(ReaderFontDesign.allCases) { f in
                        Text(f.rawValue).tag(f.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Font Size")
                    Spacer()
                    Button {
                        if readerFontSize > 12 { readerFontSize -= 1 }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .controlSize(.small)

                    Text("\(Int(readerFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .center)

                    Button {
                        if readerFontSize < 28 { readerFontSize += 1 }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .controlSize(.small)
                }
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 6) {
                    let design: Font.Design = (ReaderFontDesign(rawValue: readerFontDesignRaw) ?? .system).design
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: readerFontSize, weight: .regular, design: design))
                        .foregroundStyle(.primary)
                    Text("Sample text preview reflecting your reading font configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var subscriptionsTab: some View {
        Form {
            Section("Library Statistics") {
                HStack {
                    Text("Subscribed Feeds")
                    Spacer()
                    Text("\(feeds.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Total Stored Articles")
                    Spacer()
                    Text("\(articles.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("OPML Backup & Import") {
                HStack {
                    Button("Import Subscriptions (.opml)...") {
                        isShowingFileImporter = true
                    }
                    .disabled(isImporting)

                    Spacer()

                    Button("Export Subscriptions (.opml)...") {
                        exportOPML()
                    }
                    .disabled(feeds.isEmpty)
                }

                if let message = opmlStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

            isImporting = true
            opmlStatusMessage = "Parsing OPML..."
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    let parser = OPMLService()
                    let items = try parser.parse(data: data)

                    var importedCount = 0
                    for item in items {
                        let targetURL = item.xmlURL
                        let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == targetURL })
                        let existing = try? modelContext.fetch(descriptor).first
                        if existing == nil {
                            let newFeed = Feed(
                                title: item.title,
                                url: item.xmlURL,
                                siteURL: item.htmlURL,
                                category: item.category,
                                dateAdded: Date()
                            )
                            modelContext.insert(newFeed)
                            importedCount += 1
                        }
                    }
                    try modelContext.save()
                    opmlStatusMessage = "Successfully imported \(importedCount) new feeds from OPML."

                    // Refresh newly added feeds
                    Task {
                        await FeedRefreshService().refreshAllFeeds()
                    }
                } catch {
                    opmlStatusMessage = "OPML Import Failed: \(error.localizedDescription)"
                }
                isImporting = false
            }
        }
    }

    private func exportOPML() {
        let opmlContent = OPMLService.generateOPML(from: feeds)
        exportDocument = OPMLFileDocument(text: opmlContent)
        isShowingFileExporter = true
    }
}
