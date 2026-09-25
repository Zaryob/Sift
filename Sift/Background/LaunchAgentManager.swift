import Foundation
import Combine

public final class LaunchAgentManager: ObservableObject {
    public static let shared = LaunchAgentManager()
    
    public static let label = "com.sift.backgroundfetch"
    
    @Published public var isEnabled: Bool = false
    @Published public var intervalSeconds: Int = 900 // Default 15 minutes (900s)

    private var plistURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let launchAgentsURL = libraryURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        try? FileManager.default.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
        return launchAgentsURL.appendingPathComponent("\(Self.label).plist")
    }

    private init() {
        let storedInterval = UserDefaults.standard.integer(forKey: "launchAgentIntervalSeconds")
        self.intervalSeconds = storedInterval > 0 ? storedInterval : 900
        self.isEnabled = FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Automatically validates and synchronizes the LaunchAgent whenever a new app version or build launches.
    /// If the executable binary path, interval, or app version has changed, it updates the plist
    /// and safely re-registers with launchctl.
    public func syncOnLaunch() {
        guard isEnabled || FileManager.default.fileExists(atPath: plistURL.path) else {
            return
        }

        let appBundleURL = Bundle.main.bundleURL
        let executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/Sift")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        var needsUpdate = false

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            
            let currentArgs = plist["ProgramArguments"] as? [String] ?? []
            let registeredPath = currentArgs.first ?? ""
            let registeredInterval = plist["StartInterval"] as? Int ?? 0
            let registeredVersion = plist["Comment"] as? String ?? ""
            let currentVersionTag = "Sift v\(appVersion) (\(buildNumber))"

            if registeredPath != executableURL.path || registeredInterval != intervalSeconds || registeredVersion != currentVersionTag {
                needsUpdate = true
            }
        } else {
            needsUpdate = true
        }

        if needsUpdate {
            print("[LaunchAgentManager] Synchronizing LaunchAgent for updated app version/path...")
            installLaunchAgent(intervalSeconds: intervalSeconds)
        }
    }

    public func setEnabled(_ enabled: Bool, intervalMinutes: Int = 15) {
        let seconds = max(300, intervalMinutes * 60) // Minimum 5 minutes
        self.intervalSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "launchAgentIntervalSeconds")
        UserDefaults.standard.set(enabled, forKey: "launchAgentEnabled")

        if enabled {
            installLaunchAgent(intervalSeconds: seconds)
        } else {
            removeLaunchAgent()
        }
    }

    private func installLaunchAgent(intervalSeconds: Int) {
        let appBundleURL = Bundle.main.bundleURL
        let executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/Sift")
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        let plistDict: [String: Any] = [
            "Label": Self.label,
            "Comment": "Sift v\(appVersion) (\(buildNumber))",
            "ProgramArguments": [
                executableURL.path,
                "--background-refresh"
            ],
            "StartInterval": intervalSeconds,
            "RunAtLoad": false,
            "ProcessType": "Background",
            "StandardErrorPath": "/tmp/\(Self.label).err.log",
            "StandardOutPath": "/tmp/\(Self.label).out.log"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) else {
            return
        }

        do {
            try data.write(to: plistURL, options: .atomic)
            self.isEnabled = true
            
            // Reload service with launchctl: unload first to avoid 'service already loaded' collision, then load
            let unloadProcess = Process()
            unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProcess.arguments = ["unload", "-w", plistURL.path]
            try? unloadProcess.run()
            unloadProcess.waitUntilExit()

            let loadProcess = Process()
            loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            loadProcess.arguments = ["load", "-w", plistURL.path]
            try? loadProcess.run()
            loadProcess.waitUntilExit()
            
            print("[LaunchAgentManager] Successfully registered LaunchAgent at \(plistURL.path)")
        } catch {
            print("[LaunchAgentManager] Failed to write LaunchAgent plist: \(error)")
        }
    }

    private func removeLaunchAgent() {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", plistURL.path]
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: plistURL)
        }
        self.isEnabled = false
        print("[LaunchAgentManager] LaunchAgent removed.")
    }
}
