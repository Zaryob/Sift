import SwiftUI
import SwiftData
#if os(macOS)
import AppKit

public final class WindowActionTarget: NSObject {
    public static let shared = WindowActionTarget()
    public weak var mainWindow: NSWindow?

    @objc public func hideWindow(_ sender: Any?) {
        mainWindow?.orderOut(nil)
        try? PersistenceController.shared.container.mainContext.save()
        DispatchQueue.main.async {
            // Hide from Dock and Cmd+Tab app switcher, becoming a background menu bar accessory
            NSApp.setActivationPolicy(.accessory)
        }
    }

    public func showMainWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        for window in NSApp.windows where window.canBecomeMain {
            mainWindow = window
            setupCloseButton(on: window)
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
    }

    public func setupCloseButton(on window: NSWindow) {
        self.mainWindow = window
        window.tabbingMode = .disallowed
        
        // Intercept close button WITHOUT replacing SwiftUI's internal window delegate
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(hideWindow(_:))
        }
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowActionTarget.shared.setupCloseButton(on: window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window, WindowActionTarget.shared.mainWindow == nil {
            WindowActionTarget.shared.setupCloseButton(on: window)
        }
    }
}
#else
public final class WindowActionTarget: NSObject {
    public static let shared = WindowActionTarget()
    public func showMainWindow() {}
}

public struct WindowAccessor: View {
    public init() {}
    public var body: some View {
        EmptyView()
    }
}
#endif
