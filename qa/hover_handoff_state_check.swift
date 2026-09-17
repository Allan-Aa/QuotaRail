import Combine
import Foundation

struct ToolUsage {
    enum Tool: String, CaseIterable {
        case codex = "Codex"
        case claude = "Claude"
        case grok = "Grok"
        case cursor = "Cursor"
    }
}

@discardableResult
func wait(_ seconds: TimeInterval) -> Bool {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    return true
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
    exit(1)
}

@main
struct HoverHandoffStateCheck {
    static let handoffTimeout: TimeInterval = 0.20

    static func reveal(_ state: RailState) {
        state.tabHoverChanged(true)
        wait(0.07)
        guard state.mode == .rail else { fail("tab hover must reveal the rail") }
    }

    static func main() {
        guard RailState.collapseVisualDelay(reduceMotion: false) == RailState.overlayDismissDuration,
              RailState.collapseVisualDelay(reduceMotion: true) == 0 else {
            fail("collapse visual delay must honor Reduce Motion")
        }
        print("PASS collapse visual delay honors Reduce Motion")

        let state = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(state)

        state.tabHoverChanged(false)
        wait(RailState.hoverExitDelay + 0.03)

        if state.isCollapsing || state.mode == .collapsed {
            fail("old tab hover false collapsed the rail before its first continuous hover")
        }

        print("PASS old tab handoff remains open before continuous hover")

        let endedBeforeActive = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(endedBeforeActive)
        endedBeforeActive.tabHoverChanged(false)
        endedBeforeActive.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.03)
        if endedBeforeActive.isCollapsing || endedBeforeActive.mode == .collapsed {
            fail("continuous hover end before its first active event must preserve the tab handoff")
        }
        endedBeforeActive.continuousHoverMoved(y: 55, nearest: .codex)
        print("PASS end-before-active preserves the pending handoff")

        var handoffPointerInside = true
        let insideHandoffState = RailState(
            mode: .collapsed,
            alwaysVisible: false,
            isPointerInsideRail: { handoffPointerInside }
        )
        reveal(insideHandoffState)
        insideHandoffState.tabHoverChanged(false)
        wait(handoffTimeout + RailState.hoverExitDelay + 0.04)
        guard insideHandoffState.mode == .rail, !insideHandoffState.isCollapsing else {
            fail("pointer resolver must preserve rail during handoff without an active event")
        }

        handoffPointerInside = false
        let outsideHandoffState = RailState(
            mode: .collapsed,
            alwaysVisible: false,
            isPointerInsideRail: { handoffPointerInside }
        )
        reveal(outsideHandoffState)
        outsideHandoffState.tabHoverChanged(false)
        wait(handoffTimeout + RailState.hoverExitDelay + 0.04)
        guard outsideHandoffState.isCollapsing else {
            fail("pointer resolver must collapse after handoff when outside")
        }
        outsideHandoffState.finishCollapse()
        guard outsideHandoffState.mode == .collapsed, !outsideHandoffState.isCollapsing else {
            fail("explicit collapse finish must settle the handoff state")
        }
        print("PASS handoff resolves against the real pointer")

        var collapsedPointerInside = true
        let collapsedState = RailState(
            mode: .collapsed,
            alwaysVisible: false,
            isPointerInsideRail: { collapsedPointerInside }
        )
        collapsedState.tabHoverChanged(false)
        wait(RailState.hoverExitDelay + 0.03)
        guard collapsedState.mode == .collapsed, !collapsedState.isCollapsing else {
            fail("collapsed tab false must remain collapsed regardless of pointer resolver")
        }
        collapsedPointerInside = false
        reveal(collapsedState)
        collapsedState.tabHoverChanged(false)
        wait(handoffTimeout + RailState.hoverExitDelay + 0.04)
        guard collapsedState.isCollapsing else {
            fail("collapsed tab false must not leave a stale pointer that blocks the next collapse")
        }
        collapsedState.finishCollapse()

        var revealedPointerInside = true
        let revealedState = RailState(
            mode: .collapsed,
            alwaysVisible: false,
            isPointerInsideRail: { revealedPointerInside }
        )
        revealedState.tabHoverChanged(false)
        wait(RailState.hoverExitDelay + 0.03)
        reveal(revealedState)
        revealedState.tabHoverChanged(false)
        wait(handoffTimeout + RailState.hoverExitDelay + 0.03)
        guard revealedState.mode == .rail, !revealedState.isCollapsing else {
            fail("revealed tab handoff must stay rail while pointer resolver is inside")
        }
        revealedPointerInside = false
        revealedState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.03)
        guard revealedState.isCollapsing else {
            fail("revealed handoff must collapse after pointer leaves and hover ends")
        }
        print("PASS collapsed resolver never leaves stale pointer state")

        var activePointerInside = true
        let activeState = RailState(
            mode: .rail,
            alwaysVisible: false,
            isPointerInsideRail: { activePointerInside }
        )
        activeState.continuousHoverMoved(y: 55, nearest: .codex)
        activeState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.03)
        guard activeState.mode != .collapsed, !activeState.isCollapsing else {
            fail("pointer resolver must reject an ended event while still inside")
        }
        activePointerInside = false
        activeState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.03)
        guard activeState.isCollapsing else {
            fail("pointer resolver must collapse after the next ended event outside")
        }
        print("PASS active exit resolves against the real pointer")

        let alwaysVisibleResolverState = RailState(
            mode: .rail,
            alwaysVisible: true,
            isPointerInsideRail: { false }
        )
        alwaysVisibleResolverState.continuousHoverMoved(y: 55, nearest: .codex)
        alwaysVisibleResolverState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.03)
        guard alwaysVisibleResolverState.mode == .rail,
              !alwaysVisibleResolverState.isCollapsing else {
            fail("always-visible rail must return to rail instead of collapsing")
        }
        print("PASS always-visible exit remains rail with pointer resolver")

        state.continuousHoverMoved(y: 55, nearest: .codex)
        state.continuousHoverEnded()
        state.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.02)
        guard state.isCollapsing else {
            fail("continuous hover end must initiate one collapse")
        }
        state.finishCollapse()
        guard state.mode == .collapsed, !state.isCollapsing else {
            fail("explicit collapse finish must complete one collapse")
        }
        print("PASS active continuous hover ends with one collapse")

        let timeoutState = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(timeoutState)
        timeoutState.tabHoverChanged(false)
        wait(handoffTimeout + RailState.hoverExitDelay + 0.04)
        guard timeoutState.isCollapsing else {
            fail("missing continuous hover must collapse after handoff timeout")
        }
        timeoutState.finishCollapse()
        print("PASS missing continuous hover eventually collapses")

        let showRailState = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(showRailState)
        showRailState.tabHoverChanged(false)
        showRailState.showRail()
        showRailState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.02)
        guard showRailState.isCollapsing else {
            fail("showRail must clear a pending handoff")
        }

        let selectState = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(selectState)
        selectState.tabHoverChanged(false)
        selectState.select(.codex)
        selectState.collapse()
        selectState.finishCollapse()
        guard selectState.mode == .collapsed else {
            fail("select must clear a pending handoff")
        }

        let alwaysVisibleState = RailState(mode: .collapsed, alwaysVisible: false)
        reveal(alwaysVisibleState)
        alwaysVisibleState.tabHoverChanged(false)
        alwaysVisibleState.setAlwaysVisible(true)
        alwaysVisibleState.setAlwaysVisible(false)
        alwaysVisibleState.continuousHoverEnded()
        wait(RailState.hoverExitDelay + 0.02)
        guard alwaysVisibleState.isCollapsing else {
            fail("always-visible transition must clear a pending handoff")
        }

        let reentryState = RailState(mode: .rail, alwaysVisible: false)
        reentryState.collapse()
        guard reentryState.isCollapsing else {
            fail("collapse must enter the controller-owned finishing state")
        }
        reentryState.showRail()
        reentryState.finishCollapse()
        guard reentryState.mode == .rail, !reentryState.isCollapsing else {
            fail("re-entry during fade must cancel a pending finish")
        }

        let hoverReentryState = RailState(mode: .rail, alwaysVisible: false)
        hoverReentryState.collapse()
        hoverReentryState.continuousHoverMoved(y: 55, nearest: .codex)
        hoverReentryState.finishCollapse()
        guard hoverReentryState.mode == .detail(.codex), !hoverReentryState.isCollapsing else {
            fail("active hover during fade must cancel the controller finish")
        }

        let explicitFinishState = RailState(mode: .rail, alwaysVisible: false)
        explicitFinishState.collapse()
        explicitFinishState.finishCollapse()
        explicitFinishState.finishCollapse()
        guard explicitFinishState.mode == .collapsed, !explicitFinishState.isCollapsing else {
            fail("finishCollapse must be idempotent")
        }
        print("PASS explicit state transitions clear pending handoff")
    }
}
