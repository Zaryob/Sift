import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var scheduler = BackgroundFeedScheduler.shared
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext

    @State private var opmlStatusMessage: String?
    @State private var isImporting: Bool = false

    var body: some View {
        Form {
            Section("Startup & Background") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isLaunchAtLoginEnabled },
                    set: { loginItemManager.setLaunchAtLogin(enabled: $0) }
                ))
                .help("Automatically start Sift when you log into macOS.")

                Picker("Background Refresh Interval", selection: $scheduler.refreshIntervalMinutes) {
                    Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes (Default)").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Manual Only").tag(0)
                }
                .help("How frequently Sift checks for new feed articles in the background.")
            }

            Section("OPML Backup & Import") {
                HStack {
                    Button("Import Subscriptions (.opml)...") {
                        importOPML()
                    }
                    .disabled(isImporting)

                    Spacer()

                    Button("Export Subscriptions (.opml)...") {
                        exportOPML()
                    }
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
        .frame(width: 480, height: 280)
        .onAppear {
            NotificationManager.shared.requestAuthorization()
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import OPML File"

        if panel.runModal() == .OK, let url = panel.url {
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
        let panel = NSSavePanel()
        panel.title = "Export Subscriptions (.opml)"
        panel.nameFieldStringValue = "sift_subscriptions.opml"
        panel.allowedContentTypes = [.xml]

        if panel.runModal() == .OK, let url = panel.url {
            let opmlContent = OPMLService.generateOPML(from: feeds)
            do {
                try opmlContent.write(to: url, atomically: true, encoding: .utf8)
                opmlStatusMessage = "Successfully exported \(feeds.count) feeds to OPML."
            } catch {
                opmlStatusMessage = "OPML Export Failed: \(error.localizedDescription)"
            }
        }
    }
}
