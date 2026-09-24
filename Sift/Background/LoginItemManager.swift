import Foundation
import Combine
import ServiceManagement

public final class LoginItemManager: ObservableObject {
    public static let shared = LoginItemManager()
    
    @Published public var isLaunchAtLoginEnabled: Bool = false
    
    private init() {
        checkStatus()
    }
    
    public func checkStatus() {
        if #available(macOS 13.0, *) {
            isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    public func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                checkStatus()
            } catch {
                print("Failed to update launch at login status: \(error)")
                checkStatus()
            }
        }
    }
}
