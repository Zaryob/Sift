import SwiftUI
import AppKit

public final class WindowCloseHandler: NSObject, NSWindowDelegate {
    public static let shared = WindowCloseHandler()
    public weak var mainWindow: NSWindow?

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Hide the window instead of destroying it
    }

    public func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        for window in NSApp.windows where window.canBecomeMain {
            mainWindow = window
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = WindowCloseHandler.shared
                WindowCloseHandler.shared.mainWindow = window
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window, WindowCloseHandler.shared.mainWindow == nil {
            window.delegate = WindowCloseHandler.shared
            WindowCloseHandler.shared.mainWindow = window
        }
    }
}
