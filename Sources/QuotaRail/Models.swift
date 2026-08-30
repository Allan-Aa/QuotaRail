import Foundation

struct ToolUsage: Identifiable, Equatable {
    enum Tool: String, CaseIterable {
        case codex = "Codex"
        case claude = "Claude"
        case grok = "Grok"
        case cursor = "Cursor"
    }

    var id: String { tool.rawValue }
    let tool: Tool
    /// 0...1, nil when the provider does not expose a trustworthy value.
    let sessionPercent: Double?
    let sessionResetsLabel: String?
    let weeklyPercent: Double?
    let weeklyResetsLabel: String?
    let available: Bool
    let source: String
    let note: String?
    var actionTitle: String? = nil
    var actionURL: URL? = nil
}
