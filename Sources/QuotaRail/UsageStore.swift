import Combine
import Foundation

final class UsageStore: ObservableObject {
    @Published private(set) var items: [ToolUsage] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let previewMode: Bool
    private let providerQueue = DispatchQueue(
        label: "app.quotarail.refresh.providers",
        qos: .utility,
        attributes: .concurrent
    )
    private var timer: Timer?
    private var activeRefreshID: UUID?
    private var completedProviders = 0
    private var refreshPending = false

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
        refresh()
        if !previewMode {
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }

        if isRefreshing {
            // A manual refresh during a slow provider request is not dropped.
            // Coalesce any number of requests into one run immediately after it.
            refreshPending = true
            return
        }

        isRefreshing = true

        if previewMode {
            items = Self.previewItems
            lastUpdated = Date()
            isRefreshing = false
            return
        }

        let refreshID = UUID()
        activeRefreshID = refreshID
        completedProviders = 0
        ensureStableProviderOrder()

        for tool in ToolUsage.Tool.allCases {
            providerQueue.async { [weak self] in
                let item = Self.loadItem(for: tool)
                DispatchQueue.main.async {
                    self?.receive(item, for: tool, refreshID: refreshID)
                }
            }
        }
    }

    private func receive(_ item: ToolUsage, for tool: ToolUsage.Tool, refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        replace(item, for: tool)
        completedProviders += 1
        lastUpdated = Date()

        guard completedProviders == ToolUsage.Tool.allCases.count else { return }
        activeRefreshID = nil
        isRefreshing = false

        if refreshPending {
            refreshPending = false
            refresh()
        }
    }

    private func ensureStableProviderOrder() {
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.tool, $0) })
        items = ToolUsage.Tool.allCases.map { existing[$0] ?? Self.loadingItem(for: $0) }
    }

    private func replace(_ item: ToolUsage, for tool: ToolUsage.Tool) {
        var updated = Dictionary(uniqueKeysWithValues: items.map { ($0.tool, $0) })
        updated[tool] = item
        items = ToolUsage.Tool.allCases.compactMap { updated[$0] }
    }

    private static func loadingItem(for tool: ToolUsage.Tool) -> ToolUsage {
        ToolUsage(
            tool: tool,
            sessionPercent: nil,
            sessionResetsLabel: nil,
            weeklyPercent: nil,
            weeklyResetsLabel: nil,
            available: false,
            source: "正在刷新",
            note: "正在读取用量。"
        )
    }

    private static func loadItem(for tool: ToolUsage.Tool) -> ToolUsage {
        switch tool {
        case .codex:
            if let snapshot = CodexUsageEngine.computeSnapshot() {
                return ToolUsage(
                tool: .codex,
                sessionPercent: snapshot.primaryPercent,
                sessionResetsLabel: snapshot.primaryResetsLabel,
                weeklyPercent: snapshot.secondaryPercent,
                weeklyResetsLabel: snapshot.secondaryResetsLabel,
                available: true,
                source: "Codex 本地 rate_limits",
                note: snapshot.planType.map { "套餐：\($0)" }
                    ?? (snapshot.secondaryPercent == nil ? "当前套餐没有返回每周窗口。" : nil)
                )
            }
            return ToolUsage(
                tool: .codex,
                sessionPercent: nil,
                sessionResetsLabel: nil,
                weeklyPercent: nil,
                weeklyResetsLabel: nil,
                available: false,
                source: "本地只读",
                note: "没有找到包含 rate_limits 的 Codex rollout。先运行一次 Codex 任务。"
            )

        case .claude:
            switch ClaudeOAuthEngine.computeSnapshot() {
            case .success(let snapshot):
                return ToolUsage(
                tool: .claude,
                sessionPercent: snapshot.sessionPercent,
                sessionResetsLabel: snapshot.sessionResetsLabel,
                weeklyPercent: snapshot.weeklyPercent,
                weeklyResetsLabel: snapshot.weeklyResetsLabel,
                available: true,
                source: "Claude Code 登录状态",
                note: snapshot.planLabel.map { "套餐：\($0)" }
                )
            case .failure(let failure):
                return ToolUsage(
                tool: .claude,
                sessionPercent: nil,
                sessionResetsLabel: nil,
                weeklyPercent: nil,
                weeklyResetsLabel: nil,
                available: false,
                source: "本地凭据 + Anthropic",
                note: failure.userMessage
                )
            }

        case .grok:
            let grokStatus = GrokUsageEngine.status()
            switch GrokUsageEngine.computeSnapshot() {
            case .success(let snapshot):
                return ToolUsage(
                tool: .grok,
                sessionPercent: snapshot.weeklyPercent,
                sessionResetsLabel: snapshot.weeklyResetsLabel,
                weeklyPercent: nil,
                weeklyResetsLabel: nil,
                available: true,
                source: "Grok Build 登录状态",
                note: grokStatus.note
                )
            case .failure(let failure):
                return ToolUsage(
                tool: .grok,
                sessionPercent: nil,
                sessionResetsLabel: nil,
                weeklyPercent: nil,
                weeklyResetsLabel: nil,
                available: false,
                source: "Grok Build 登录状态",
                note: failure.userMessage,
                actionTitle: grokStatus.actionTitle,
                actionURL: grokStatus.actionURL
                )
            }

        case .cursor:
            let cursorStatus = CursorUsageEngine.status()
            switch CursorUsageEngine.computeSnapshot() {
            case .success(let snapshot):
                return ToolUsage(
                tool: .cursor,
                sessionPercent: snapshot.grokBotWeeklyPercent,
                sessionResetsLabel: snapshot.grokBotWeeklyResetsLabel,
                weeklyPercent: snapshot.monthlyPercent,
                weeklyResetsLabel: snapshot.monthlyResetsLabel,
                available: true,
                source: "Cursor 本机登录状态 + Grok Bot",
                note: cursorNote(snapshot)
                )
            case .failure(let failure):
                return ToolUsage(
                tool: .cursor,
                sessionPercent: nil,
                sessionResetsLabel: nil,
                weeklyPercent: nil,
                weeklyResetsLabel: nil,
                available: false,
                source: "Cursor 本机登录状态",
                note: failure.userMessage,
                actionTitle: cursorStatus.actionTitle,
                actionURL: cursorStatus.actionURL
                )
            }
        }
    }

    private static let previewItems: [ToolUsage] = [
        ToolUsage(
            tool: .codex,
            sessionPercent: 0.68,
            sessionResetsLabel: "1h 42m",
            weeklyPercent: 0.31,
            weeklyResetsLabel: "4d 6h",
            available: true,
            source: "预览数据",
            note: "套餐：Pro"
        ),
        ToolUsage(
            tool: .claude,
            sessionPercent: 0.42,
            sessionResetsLabel: "3h 12m",
            weeklyPercent: 0.57,
            weeklyResetsLabel: "2d 8h",
            available: true,
            source: "预览数据",
            note: "套餐：Max 20x"
        ),
        ToolUsage(
            tool: .grok,
            sessionPercent: 0.18,
            sessionResetsLabel: "3d 14h",
            weeklyPercent: nil,
            weeklyResetsLabel: nil,
            available: true,
            source: "预览数据",
            note: "SuperGrok 周额度"
        ),
        ToolUsage(
            tool: .cursor,
            sessionPercent: 0.42,
            sessionResetsLabel: "4d 6h",
            weeklyPercent: 0.33,
            weeklyResetsLabel: "12d 4h",
            available: true,
            source: "预览数据",
            note: "Grok Bot 周额度 · 套餐：Pro"
        )
    ]

    private static func cursorNote(_ snapshot: CursorUsageEngine.Snapshot) -> String? {
        var parts: [String] = []
        if snapshot.grokBotWeeklyPercent == nil {
            parts.append("Grok Bot 周额度暂不可用")
        }
        if let planLabel = snapshot.planLabel {
            parts.append("套餐：\(planLabel)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
