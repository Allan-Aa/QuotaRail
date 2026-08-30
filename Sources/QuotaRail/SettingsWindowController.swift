import AppKit
import QuotaRailCore
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(preferences: RailPreferences) {
        let rootView = RailSettingsView(preferences: preferences)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "QuotaRail 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(NSSize(width: 400, height: 610))
        window.minSize = NSSize(width: 400, height: 610)
        window.maxSize = NSSize(width: 400, height: 610)
        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
