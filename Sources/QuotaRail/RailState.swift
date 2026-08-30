import Foundation

final class RailState: ObservableObject {
    static let overlayDismissDuration: TimeInterval = 0.10
    static let frameAnimationDuration: TimeInterval = 0.22
    static let hoverExitDelay: TimeInterval = 0.06
    static let collapseSequenceDuration = overlayDismissDuration + frameAnimationDuration

    enum Mode: Equatable {
        case collapsed
        case rail
        case detail(ToolUsage.Tool)
    }

    @Published var mode: Mode
    @Published private(set) var interactionID = 0
    @Published private(set) var hoveredTool: ToolUsage.Tool?
    @Published private(set) var isPinned: Bool
    @Published private(set) var hoverY: CGFloat? = nil
    @Published private(set) var isCollapsing = false
    @Published private(set) var alwaysVisible: Bool

    let hoverEnabled: Bool

    private var pointerInside = false
    private var tabHovered = false
    private var revealWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var collapseFinalizeWorkItem: DispatchWorkItem?

    init(
        mode: Mode = .collapsed,
        hoverEnabled: Bool = true,
        initiallyPinned: Bool? = nil,
        initialHoverY: CGFloat? = nil,
        alwaysVisible: Bool = false
    ) {
        self.mode = mode
        self.hoverEnabled = hoverEnabled
        self.hoverY = initialHoverY
        self.alwaysVisible = alwaysVisible
        if case .detail(let tool) = mode {
            self.hoveredTool = tool
            self.isPinned = initiallyPinned ?? true
        } else {
            self.hoveredTool = nil
            self.isPinned = initiallyPinned ?? false
        }
    }

    deinit {
        revealWorkItem?.cancel()
        collapseWorkItem?.cancel()
        collapseFinalizeWorkItem?.cancel()
    }

    func toggleRail() {
        if alwaysVisible {
            showRail()
        } else {
            mode == .collapsed || isCollapsing ? showRail() : collapse()
        }
    }

    func select(_ tool: ToolUsage.Tool) {
        cancelPendingWork()
        isCollapsing = false
        hoveredTool = tool
        hoverY = nil
        isPinned = true
        mode = .detail(tool)
        interactionID += 1
    }

    func showRail() {
        cancelPendingWork()
        isCollapsing = false
        hoverY = nil
        isPinned = false
        mode = .rail
    }

    func collapse() {
        if alwaysVisible {
            returnToRail()
        } else {
            beginCollapse()
        }
    }

    func setAlwaysVisible(_ enabled: Bool) {
        guard alwaysVisible != enabled else { return }
        alwaysVisible = enabled
        if enabled, mode == .collapsed || isCollapsing {
            showRail()
        }
    }

    func reconcileVisibleTools(_ visibleTools: [ToolUsage.Tool]) {
        guard !visibleTools.isEmpty else { return }
        let visible = Set(visibleTools)
        if let hoveredTool, !visible.contains(hoveredTool) {
            self.hoveredTool = nil
            hoverY = nil
        }
        if case .detail(let tool) = mode, !visible.contains(tool) {
            returnToRail()
        }
    }

    func tabHoverChanged(_ inside: Bool) {
        guard hoverEnabled else { return }
        tabHovered = inside

        if inside {
            cancelCollapseTransition()
            collapseWorkItem?.cancel()
            revealWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.tabHovered, self.mode == .collapsed else { return }
                self.isPinned = false
                self.mode = .rail
            }
            revealWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        } else {
            revealWorkItem?.cancel()
            scheduleCollapse()
        }
    }

    func continuousHoverMoved(y: CGFloat, nearest tool: ToolUsage.Tool) {
        guard hoverEnabled, !isPinned else { return }
        cancelCollapseTransition()
        pointerInside = true
        hoverY = y
        collapseWorkItem?.cancel()
        revealWorkItem?.cancel()
        if hoveredTool != tool {
            hoveredTool = tool
        }

        let nextMode = Mode.detail(tool)
        if mode != nextMode {
            mode = nextMode
            interactionID += 1
        }
    }

    func continuousHoverEnded() {
        guard hoverEnabled, !isPinned else { return }
        pointerInside = false
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        guard hoverEnabled, !isPinned else { return }
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.pointerInside,
                  !self.tabHovered,
                  !self.isPinned else { return }
            if self.alwaysVisible {
                self.returnToRail()
            } else {
                self.beginCollapse()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverExitDelay,
            execute: work
        )
    }

    private func cancelPendingWork() {
        revealWorkItem?.cancel()
        collapseWorkItem?.cancel()
        collapseFinalizeWorkItem?.cancel()
        revealWorkItem = nil
        collapseWorkItem = nil
        collapseFinalizeWorkItem = nil
    }

    private func cancelCollapseTransition() {
        guard isCollapsing else { return }
        collapseFinalizeWorkItem?.cancel()
        collapseFinalizeWorkItem = nil
        isCollapsing = false
    }

    private func beginCollapse() {
        guard !alwaysVisible else {
            returnToRail()
            return
        }
        guard mode != .collapsed, !isCollapsing else { return }
        revealWorkItem?.cancel()
        collapseWorkItem?.cancel()
        revealWorkItem = nil
        collapseWorkItem = nil
        pointerInside = false
        tabHovered = false
        isCollapsing = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCollapsing else { return }
            self.mode = .collapsed
            self.isPinned = false
            self.hoveredTool = nil
            self.hoverY = nil
            self.isCollapsing = false
            self.collapseFinalizeWorkItem = nil
        }
        collapseFinalizeWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.collapseSequenceDuration,
            execute: work
        )
    }

    private func returnToRail() {
        cancelPendingWork()
        isCollapsing = false
        pointerInside = false
        tabHovered = false
        isPinned = false
        hoveredTool = nil
        hoverY = nil
        mode = .rail
    }
}
