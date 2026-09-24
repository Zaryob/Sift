import SwiftUI

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var scheduler = BackgroundFeedScheduler.shared

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
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 200)
    }
}
