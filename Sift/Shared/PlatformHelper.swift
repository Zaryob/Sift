import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum Platform {
    public static func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    public static func copyToPasteboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    public static func showMainWindow() {
        #if os(macOS)
        WindowActionTarget.shared.showMainWindow()
        #endif
    }
}
