import AppKit
import SwiftUI

/// Replaces NSPopover: NSPopover always paints its own rounded chrome + arrow
/// underneath whatever content you give it, which doubled up with our own
/// rounded card and looked like a square frame behind a rounded one. A plain
/// transparent NSPanel gives full control over the shape with nothing behind it.
final class DetailPanelWindow {
    private let panel: NSPanel
    private let hosting: NSHostingController<ContentView>
    private var outsideClickMonitor: Any?

    init(store: UsageStore, selection: SelectionModel) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // See FloatingPillWindow: AppKit's window-level shadow follows the
        // rectangular frame, not our clipped rounded shape, so it's off here
        // too — SwiftUI's own .shadow() modifier draws it instead.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        hosting = NSHostingController(rootView: ContentView(store: store, selection: selection))
        hosting.sizingOptions = [.preferredContentSize]
        // NSHostingView paints its own opaque background layer independent of
        // whatever SwiftUI draws — clipShape only affects SwiftUI's content, not
        // this layer, so without this the window bounds show through as a
        // square behind the rounded card.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        panel.contentViewController = hosting
    }

    var isShown: Bool { panel.isVisible }

    /// Switching tools while already open goes through `SelectionModel`
    /// directly (see main.swift) — this is only for opening/repositioning
    /// the window itself, so it's never called on every tab switch.
    func show(relativeTo rect: NSRect, of view: NSView, preferOnLeft: Bool) {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }

        // Order front (invisibly) first so SwiftUI actually lays the content
        // out — fittingSize is unreliable before that happens — then reveal
        // once positioned, so there's no flash at the wrong spot.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        var size = hosting.view.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 320, height: 240)
        }
        panel.setContentSize(size)

        let screenRect = window.convertToScreen(view.convert(rect, to: nil))
        var origin: NSPoint
        if preferOnLeft {
            origin = NSPoint(x: screenRect.minX - size.width - 10, y: screenRect.midY - size.height / 2)
        } else {
            origin = NSPoint(x: screenRect.midX - size.width / 2, y: screenRect.minY - size.height - 8)
        }

        // Keep it fully on-screen.
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - size.height - 8)

        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        installOutsideClickMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}
