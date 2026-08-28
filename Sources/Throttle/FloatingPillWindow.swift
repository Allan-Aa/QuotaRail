import AppKit
import SwiftUI

/// Borderless always-on-top panel pinned to the right-middle edge of the
/// screen, showing the same ring strip as the menu bar popover so usage is
/// visible at a glance without clicking anything. Draggable; position persists.
final class FloatingPillWindow {
    private let panel: NSPanel
    private var hosting: NSHostingController<FloatingPillView>!
    private let store: UsageStore
    private let selection: SelectionModel
    private var didSizeAndPosition = false
    var onRingTapped: ((ToolUsage.Tool, NSView) -> Void)?

    private static let originKey = "throttle.pillOrigin"

    init(store: UsageStore, selection: SelectionModel) {
        self.store = store
        self.selection = selection

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // AppKit's window-level shadow follows the rectangular window frame,
        // not our clipped rounded shape — it drew a faint square edge behind
        // the pill. SwiftUI's own .shadow() on the content respects the real
        // alpha-masked shape instead, so the window shadow is off entirely.
        panel.hasShadow = false
        // .statusBar sits above regular floating overlays (other menu-bar-style
        // widgets, revealed system menu bar) so this pill doesn't get covered.
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let binding = Binding<ToolUsage.Tool>(
            get: { [weak selection] in selection?.selected ?? .claude },
            set: { [weak self, weak selection] newValue in
                selection?.selected = newValue
                if let self, let view = self.panel.contentView {
                    self.onRingTapped?(newValue, view)
                }
            }
        )

        let content = FloatingPillView(store: store, selected: binding, onSelectRing: {})
        hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        // NSHostingView paints its own opaque background layer independent of
        // whatever SwiftUI draws — clipShape only affects SwiftUI's content, not
        // this layer, so without this the window bounds show through as a
        // square behind the rounded card.
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        panel.contentViewController = hosting
    }

    /// SwiftUI can't report a real fittingSize until the view has actually been
    /// laid out inside a shown window, so size/position (falling back to a
    /// sane default) only after the first `show()`, not at construction time —
    /// reading fittingSize too early silently produces a zero-size, invisible window.
    private func sizeAndPositionIfNeeded() {
        guard !didSizeAndPosition else { return }
        var size = hosting.view.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 60, height: 200)
        }
        panel.setContentSize(size)
        didSizeAndPosition = true
        positionPanel()
        panel.alphaValue = 1
    }

    private func positionPanel() {
        let size = panel.frame.size

        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved)
            panel.setFrameOrigin(point)
            return
        }

        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - size.width - 6
        let y = frame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        if !didSizeAndPosition { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        sizeAndPositionIfNeeded()
        observeMoves()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func observeMoves() {
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(NSStringFromPoint(self.panel.frame.origin), forKey: Self.originKey)
        }
    }
}
