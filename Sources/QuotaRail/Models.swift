import Foundation
import QuotaRailCore

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
    let refreshState: ProviderRefreshState

    init(
        tool: Tool,
        sessionPercent: Double?,
        sessionResetsLabel: String?,
        weeklyPercent: Double?,
        weeklyResetsLabel: String?,
        available: Bool,
        source: String,
        note: String?,
        actionTitle: String? = nil,
        actionURL: URL? = nil,
        refreshState: ProviderRefreshState = .unavailable
    ) {
        self.tool = tool
        self.sessionPercent = sessionPercent
        self.sessionResetsLabel = sessionResetsLabel
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsLabel = weeklyResetsLabel
        self.available = available
        self.source = source
        self.note = note
        self.actionTitle = actionTitle
        self.actionURL = actionURL
        self.refreshState = refreshState
    }

    func with(refreshState: ProviderRefreshState) -> ToolUsage {
        ToolUsage(
            tool: tool,
            sessionPercent: sessionPercent,
            sessionResetsLabel: sessionResetsLabel,
            weeklyPercent: weeklyPercent,
            weeklyResetsLabel: weeklyResetsLabel,
            available: available,
            source: source,
            note: note,
            actionTitle: actionTitle,
            actionURL: actionURL,
            refreshState: refreshState
        )
    }
}
