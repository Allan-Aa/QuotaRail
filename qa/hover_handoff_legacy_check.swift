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

func wait(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
    exit(1)
}

@main
struct HoverHandoffLegacyCheck {
    static func main() {
        let state = RailState(mode: .collapsed, alwaysVisible: false)
        state.tabHoverChanged(true)
        wait(0.07)
        guard state.mode == .rail else { fail("tab hover must reveal the rail") }

        state.tabHoverChanged(false)
        wait(0.09)
        guard state.mode != .collapsed, !state.isCollapsing else {
            fail("old tab false must not collapse before new rail hover becomes active")
        }
        print("PASS legacy tab-to-rail handoff remains open")
    }
}
