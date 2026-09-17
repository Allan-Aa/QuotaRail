import AppKit
import Combine
import QuartzCore
import QuotaRailCore
import SwiftUI

private final class RailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RailHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class RailWindowController {
    private enum Metrics {
        static let collapsed = NSSize(width: 8, height: 28)
        static let verticalFraction = 0.56
    }

    private let panel: RailPanel
    private let overlayPanel: RailPanel
    private let store: UsageStore
    private let state: RailState
    private let preferences: RailPreferences
    private var cancellables = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var collapseFrameWorkItem: DispatchWorkItem?
    private var anchorScreen: NSScreen?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        store: UsageStore,
        state: RailState,
        preferences: RailPreferences,
        suppressOutsideClick: Bool
    ) {
        self.store = store
        self.state = state
        self.preferences = preferences
        panel = RailPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.collapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel = RailPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 1, height: 1)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        state.setPointerInsideRailResolver { [weak panel, weak preferences] in
            guard let panel, let preferences else { return false }
            let layout = RailLayout(
                trackScale: preferences.trackScale,
                providerCount: preferences.visibleProviderIDs.count
            )
            let interactiveRect = NSRect(
                x: panel.frame.maxX - layout.interactiveWidth,
                y: panel.frame.minY,
                width: layout.interactiveWidth,
                height: panel.frame.height
            )
            return interactiveRect.contains(NSEvent.mouseLocation)
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        let rootView = RailRootView(store: store, state: state, preferences: preferences)
        let hosting = RailHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        overlayPanel.isFloatingPanel = true
        overlayPanel.becomesKeyOnlyIfNeeded = true
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.worksWhenModal = false
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.collectionBehavior = panel.collectionBehavior
        let overlayRoot = RailOverlayRootView(store: store, state: state)
        let overlayHosting = RailHostingView(rootView: overlayRoot)
        overlayHosting.sizingOptions = []
        overlayHosting.wantsLayer = true
        overlayHosting.layer?.backgroundColor = .clear
        overlayPanel.contentView = overlayHosting
        panel.title = "QuotaRail Rail"
        overlayPanel.title = "QuotaRail Overlay"
        if ProcessInfo.processInfo.environment["QUOTARAIL_PREVIEW_WINDOW_NAMES"] == "1" {
            panel.title = "QuotaRail Preview Rail"
            overlayPanel.title = "QuotaRail Preview Overlay"
        }

        Publishers.CombineLatest3(state.$mode, state.$isPinned, state.$isCollapsing)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, isCollapsing in
                self?.stateChanged(isCollapsing: isCollapsing)
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateFrame(animated: false)
                    self?.updateOverlay(animated: false)
                }
            }
            .store(in: &cancellables)

        store.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateOverlay(animated: false) }
            .store(in: &cancellables)

        if !suppressOutsideClick {
            installEventMonitors()
        }
        installScreenObservers()
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        collapseFrameWorkItem?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func show() {
        anchorToPointerScreen()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        updateFrame(animated: false)
        panel.alphaValue = 1
        updateOverlay(animated: false)
    }

    func toggle() {
        anchorToPointerScreen()
        state.toggleRail()
    }

    func showRail() {
        anchorToPointerScreen()
        state.showRail()
    }

    func isPresentedFrameSettled(tolerance: CGFloat = 1) -> Bool {
        let expected = size(
            for: state.mode,
            isCollapsing: state.isCollapsing
        )
        let windowID = CGWindowID(panel.windowNumber)
        guard let info = (CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]])?.first,
        let bounds = info[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? NSNumber,
        let height = bounds["Height"] as? NSNumber else {
            return false
        }
        return abs(width.doubleValue - expected.width) <= tolerance
            && abs(height.doubleValue - expected.height) <= tolerance
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapseIfClickWasOutside()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.collapseIfClickWasOutside()
            return event
        }
    }

    private func stateChanged(isCollapsing: Bool) {
        collapseFrameWorkItem?.cancel()
        collapseFrameWorkItem = nil

        guard isCollapsing else {
            updateFrame()
            updateOverlay()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isCollapsing else { return }
            self.overlayPanel.ignoresMouseEvents = true
            self.overlayPanel.alphaValue = 0
            self.overlayPanel.orderOut(nil)
            self.updateFrame(animated: false)
            self.state.finishCollapse()
            self.collapseFrameWorkItem = nil
        }
        collapseFrameWorkItem = work
        let delay = RailState.collapseVisualDelay(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if delay == 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func collapseIfClickWasOutside() {
        guard state.mode != .collapsed else { return }
        let pointer = NSEvent.mouseLocation
        let insideSensor = panel.frame.contains(pointer)
        let insidePinnedOverlay = state.isPinned
            && overlayPanel.isVisible
            && overlayPanel.frame.contains(pointer)
        if !insideSensor && !insidePinnedOverlay {
            state.collapse()
        }
    }

    private func installScreenObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateAllFrames(animated: false) })
        observers.append(center.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in self?.updateAllFrames(animated: false) })
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateAllFrames(animated: false) })
    }

    private func updateAllFrames(animated: Bool) {
        updateFrame(animated: animated)
        updateOverlay(animated: animated)
    }

    private func updateFrame(animated: Bool = true) {
        guard let screen = targetScreen() else { return }
        let size = size(
            for: state.mode,
            isCollapsing: state.isCollapsing
        )
        let visible = screen.visibleFrame
        let x = visible.maxX - size.width
        let unclampedY = visible.minY + (visible.height - size.height) * Metrics.verticalFraction
        let y = min(max(unclampedY, visible.minY), visible.maxY - size.height)
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if abs(panel.frame.minX - frame.minX) < 0.5,
           abs(panel.frame.minY - frame.minY) < 0.5,
           abs(panel.frame.width - frame.width) < 0.5,
           abs(panel.frame.height - frame.height) < 0.5 {
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = RailState.frameAnimationDuration
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22,
                    1.0,
                    0.36,
                    1.0
                )
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func updateOverlay(animated: Bool = true) {
        guard !state.isCollapsing,
              case .detail(let tool) = state.mode,
              let screen = targetScreen() else {
            overlayPanel.ignoresMouseEvents = true
            overlayPanel.alphaValue = 0
            overlayPanel.orderOut(nil)
            return
        }

        let layout = RailLayout(
            trackScale: preferences.trackScale,
            providerCount: preferences.visibleProviderIDs.count
        )
        let usage = store.items.first { $0.tool == tool }
        let overlaySize: NSSize
        let top: CGFloat
        let gap: CGFloat
        if state.isPinned {
            let height = cardHeight(for: usage)
            overlaySize = NSSize(width: layout.cardWidth, height: height)
            top = cardTop(for: tool, height: height, layout: layout)
            gap = layout.cardGap
        } else {
            overlaySize = NSSize(
                width: layout.hoverLabelWidth,
                height: layout.hoverLabelHeight
            )
            top = hoverLabelTop(for: tool, layout: layout)
            gap = layout.hoverLabelGap
        }

        let visible = screen.visibleFrame
        let railLeft = visible.maxX - layout.railWidth
        let frame = NSRect(
            x: railLeft - gap - overlaySize.width,
            y: panel.frame.maxY - top - overlaySize.height,
            width: overlaySize.width,
            height: overlaySize.height
        )
        overlayPanel.ignoresMouseEvents = !state.isPinned

        if !overlayPanel.isVisible {
            overlayPanel.setFrame(frame, display: true)
            overlayPanel.alphaValue = 1
            overlayPanel.orderFrontRegardless()
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22,
                    1.0,
                    0.36,
                    1.0
                )
                overlayPanel.animator().setFrame(frame, display: true)
            }
        } else {
            overlayPanel.setFrame(frame, display: true)
        }
    }

    private func hoverLabelTop(for tool: ToolUsage.Tool, layout: RailLayout) -> CGFloat {
        min(
            max(8, toolCenterY(tool, layout: layout) - layout.hoverLabelHeight / 2),
            layout.railHeight - layout.hoverLabelHeight - 8
        )
    }

    private func cardTop(
        for tool: ToolUsage.Tool,
        height: CGFloat,
        layout: RailLayout
    ) -> CGFloat {
        min(
            max(6, toolCenterY(tool, layout: layout) - height / 2),
            layout.railHeight - height - 6
        )
    }

    private func toolCenterY(_ tool: ToolUsage.Tool, layout: RailLayout) -> CGFloat {
        let tools = ToolUsage.Tool.allCases.filter {
            preferences.visibleProviderIDs.contains($0.rawValue)
        }
        let index = CGFloat(tools.firstIndex(of: tool) ?? 0)
        return layout.topInset + layout.cellHeight * index + layout.cellHeight / 2
    }

    private func cardHeight(for item: ToolUsage?) -> CGFloat {
        guard let item, item.available else {
            return 62
        }
        return item.weeklyPercent == nil ? 64 : 94
    }

    private func size(
        for mode: RailState.Mode,
        isCollapsing: Bool
    ) -> NSSize {
        if isCollapsing { return Metrics.collapsed }
        let layout = RailLayout(
            trackScale: preferences.trackScale,
            providerCount: preferences.visibleProviderIDs.count
        )
        switch mode {
        case .collapsed: return Metrics.collapsed
        case .rail, .detail:
            return NSSize(width: layout.sensorWidth, height: layout.railHeight)
        }
    }

    private func targetScreen() -> NSScreen? {
        if let anchorScreen,
           NSScreen.screens.contains(where: { $0 === anchorScreen }) {
            return anchorScreen
        }
        let mouse = NSEvent.mouseLocation
        let resolved = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        anchorScreen = resolved
        return resolved
    }

    private func anchorToPointerScreen() {
        let pointer = NSEvent.mouseLocation
        anchorScreen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
