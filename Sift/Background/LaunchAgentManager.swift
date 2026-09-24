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

    public func setEnabled(_ enabled: Bool, intervalMinutes: Int = 15) {
        let seconds = max(300, intervalMinutes * 60) // Minimum 5 minutes
        self.intervalSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "launchAgentIntervalSeconds")

        if enabled {
            installLaunchAgent(intervalSeconds: seconds)
        } else {
            removeLaunchAgent()
        }
    }

    private func installLaunchAgent(intervalSeconds: Int) {
        let appBundleURL = Bundle.main.bundleURL
        let executableURL = appBundleURL.appendingPathComponent("Contents/MacOS/Sift")
        
        let plistDict: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [
                executableURL.path,
                "--background-refresh"
            ],
            "StartInterval": intervalSeconds,
            "RunAtLoad": false,
            "ProcessType": "Background"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0) else {
            return
        }

        do {
            try data.write(to: plistURL, options: .atomic)
            self.isEnabled = true
            
            // Register with launchctl
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", "-w", plistURL.path]
            try? process.run()
        } catch {
            print("Failed to write LaunchAgent plist: \(error)")
        }
    }

    private func removeLaunchAgent() {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", "-w", plistURL.path]
            try? process.run()
            try? FileManager.default.removeItem(at: plistURL)
        }
        self.isEnabled = false
    }
}
