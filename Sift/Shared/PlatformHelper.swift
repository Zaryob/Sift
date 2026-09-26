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

    public static func pasteboardCandidateURL() -> (url: URL, host: String)? {
        #if os(macOS)
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let url = AppViewModel.normalizedURL(from: text),
              let host = url.host(),
              !host.isEmpty else {
            return nil
        }
        return (url, host)
        #else
        guard UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let url = AppViewModel.normalizedURL(from: text),
              let host = url.host(),
              !host.isEmpty else {
            return nil
        }
        return (url, host)
        #endif
    }

    public static func showMainWindow() {
        #if os(macOS)
        WindowActionTarget.shared.showMainWindow()
        #endif
    }
}
