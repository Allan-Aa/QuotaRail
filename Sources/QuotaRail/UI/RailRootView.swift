import AppKit
import QuotaRailCore
import SwiftUI

struct RailRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: RailState
    @ObservedObject var preferences: RailPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleTools: [ToolUsage.Tool] {
        ToolUsage.Tool.allCases.filter { preferences.isProviderVisible($0.rawValue) }
    }

    private var layout: RailLayout {
        RailLayout(trackScale: preferences.trackScale, providerCount: visibleTools.count)
    }

    var body: some View {
        Group {
            if state.mode == .collapsed {
                collapsedTab
            } else {
                railExperience(focusedTool: selectedTool)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var collapsedTab: some View {
        Button {
            state.showRail()
        } label: {
            MiniTabShape(corner: 4)
                .fill(RailTheme.background)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailPressButtonStyle())
        .onHover { state.tabHoverChanged($0) }
        .accessibilityLabel("Show QuotaRail")
        .help("Show QuotaRail")
    }

    private var railContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: CGFloat(layout.topInset))

            ForEach(visibleTools, id: \.self) { tool in
                let motion = dockMotion(for: tool)
                ProviderRailButton(
                    tool: tool,
                    item: item(for: tool),
                    isSelected: selectedTool == tool,
                    isHovered: state.hoveredTool == tool,
                    showsInlinePercent: state.isPinned || state.hoveredTool != tool,
                    magnificationScale: CGFloat(motion.scale),
                    iconScale: CGFloat(preferences.iconScale),
                    railWidth: CGFloat(layout.railWidth),
                    cellHeight: CGFloat(layout.cellHeight),
                    action: {
                        if reduceMotion {
                            state.select(tool)
                        } else {
                            withAnimation(.easeOut(duration: 0.14)) {
                                state.select(tool)
                            }
                        }
                        store.refresh()
                    }
                )
                .frame(height: CGFloat(layout.cellHeight))
                .offset(
                    x: CGFloat(motion.horizontalOffset),
                    y: CGFloat(motion.verticalOffset)
                )
                .zIndex(motion.influence)
            }

            Color.clear.frame(height: CGFloat(layout.topInset))
        }
        .frame(width: CGFloat(layout.railWidth), height: CGFloat(layout.railHeight))
    }

    private func railExperience(focusedTool: ToolUsage.Tool?) -> some View {
        ZStack(alignment: .topTrailing) {
            interactiveRail(focusedTool: focusedTool)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(dockAnimation, value: focusedTool)
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.84),
            value: state.isPinned
        )
        .opacity(state.isCollapsing ? 0 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: RailState.overlayDismissDuration),
            value: state.isCollapsing
        )
        .accessibilityElement(children: .contain)
    }

    private func interactiveRail(focusedTool: ToolUsage.Tool?) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            railContent
                .background(alignment: .trailing) {
                    railGlassBackground(focusedTool: focusedTool)
                }
        }
        .frame(
            width: CGFloat(layout.interactiveWidth),
            height: CGFloat(layout.railHeight),
            alignment: .topTrailing
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard state.mode != .collapsed else { return }
            handleContinuousHover(phase)
        }
        .onAppear { traceHover("rail-appear") }
        .onDisappear { traceHover("rail-disappear") }
    }

    private func railGlassBackground(focusedTool: ToolUsage.Tool?) -> some View {
        let focusY = focusedTool.map { state.hoverY ?? toolCenterY($0) }
            ?? CGFloat(layout.railHeight / 2)
        let bulgeDepth = focusedTool == nil ? 0 : CGFloat(layout.liquidBulgeDepth)
        let shape = LiquidRailShape(
            focusY: focusY,
            bulgeDepth: bulgeDepth,
            railWidth: CGFloat(layout.railWidth)
        )

        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(RailTheme.railGlassTint)
            shape.stroke(RailTheme.glassEdge, lineWidth: 0.55)
        }
            .frame(
                width: CGFloat(layout.glassBackgroundWidth),
                height: CGFloat(layout.railHeight)
            )
            .shadow(color: .black.opacity(0.22), radius: 14, x: -6, y: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var dockAnimation: Animation? {
        reduceMotion
            ? nil
            : .interactiveSpring(response: 0.22, dampingFraction: 0.74, blendDuration: 0.08)
    }

    private func handleContinuousHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            traceHover("hover-active")
            state.continuousHoverMoved(y: location.y, nearest: nearestTool(to: location.y))
        case .ended:
            traceHover("hover-ended")
            state.continuousHoverEnded()
        }
    }

    private func traceHover(_ event: String) {
        guard ProcessInfo.processInfo.environment["QUOTARAIL_PREVIEW_TRACE_HOVER"] == "1" else {
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        FileHandle.standardOutput.write(Data("QR_HOVER \(uptime) \(event)\n".utf8))
    }

    private func nearestTool(to y: CGFloat) -> ToolUsage.Tool {
        visibleTools.min { lhs, rhs in
            abs(toolCenterY(lhs) - y) < abs(toolCenterY(rhs) - y)
        } ?? visibleTools.first ?? .codex
    }

    private func dockMotion(for tool: ToolUsage.Tool) -> DockMagnificationTransform {
        let pointerY: CGFloat?
        if state.isPinned, let selectedTool {
            pointerY = toolCenterY(selectedTool)
        } else if let hoverY = state.hoverY {
            pointerY = hoverY
        } else if let selectedTool {
            pointerY = toolCenterY(selectedTool)
        } else {
            pointerY = nil
        }

        guard let pointerY else {
            return DockMagnificationTransform(
                influence: 0,
                scale: preferences.idleIconScale,
                horizontalOffset: 0,
                verticalOffset: 0
            )
        }
        return DockMagnificationCurve.transform(
            pointerY: Double(pointerY),
            itemCenterY: Double(toolCenterY(tool)),
            reduceMotion: reduceMotion,
            configuration: DockMagnificationConfiguration(
                idleScale: preferences.idleIconScale,
                hoverMaxScale: preferences.hoverMaxScale,
                trackScale: preferences.trackScale
            )
        )
    }

    private var selectedTool: ToolUsage.Tool? {
        if case .detail(let tool) = state.mode { return tool }
        return nil
    }

    private func item(for tool: ToolUsage.Tool) -> ToolUsage? {
        store.items.first { $0.tool == tool }
    }

    private func toolCenterY(_ tool: ToolUsage.Tool) -> CGFloat {
        let index = CGFloat(visibleTools.firstIndex(of: tool) ?? 0)
        return CGFloat(layout.topInset)
            + CGFloat(layout.cellHeight) * index
            + CGFloat(layout.cellHeight / 2)
    }

}

struct RailOverlayRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: RailState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if case .detail(let tool) = state.mode {
                if state.isPinned {
                    UsageCard(item: item(for: tool), tool: tool)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity
                                    .combined(with: .offset(x: -8))
                                    .combined(with: .scale(scale: 0.94, anchor: .trailing))
                        )
                } else {
                    UsageHoverLabel(item: item(for: tool), tool: tool)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity.combined(with: .scale(scale: 0.94, anchor: .trailing))
                        )
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(state.isCollapsing ? 0 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: RailState.overlayDismissDuration),
            value: state.isCollapsing
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: state.interactionID
        )
        .accessibilityElement(children: .contain)
    }

    private func item(for tool: ToolUsage.Tool) -> ToolUsage? {
        store.items.first { $0.tool == tool }
    }
}

private struct ProviderRailButton: View {
    let tool: ToolUsage.Tool
    let item: ToolUsage?
    let isSelected: Bool
    let isHovered: Bool
    let showsInlinePercent: Bool
    let magnificationScale: CGFloat
    let iconScale: CGFloat
    let railWidth: CGFloat
    let cellHeight: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arcTurn = 0.0

    var body: some View {
        Button {
            if !reduceMotion { arcTurn += 360 }
            action()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    statusColor.opacity(isHovered ? 0.28 : 0),
                                    statusColor.opacity(isHovered ? 0.08 : 0),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 18
                            )
                        )
                        .frame(width: 36 * iconScale, height: 36 * iconScale)
                        .scaleEffect(isHovered ? 1 : 0.72)

                    Circle()
                        .fill(isSelected ? RailTheme.surface : Color.clear)
                        .frame(width: 32 * iconScale, height: 32 * iconScale)

                    RingView(
                        percent: item?.sessionPercent,
                        tool: tool,
                        size: 28 * iconScale,
                        rotationDegrees: arcTurn + (isHovered ? 18 : 0)
                    )
                }
                .frame(width: 36 * iconScale, height: 34 * iconScale)
                .scaleEffect(magnificationScale)

                Text(percentLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.1)
                    .foregroundStyle(
                        isShowingCachedValue
                            ? Color.orange
                            : item?.available == true
                            ? RailTheme.text.opacity(0.88)
                            : RailTheme.textMuted
                    )
                    .frame(width: 38, height: 13)
                    .opacity(showsInlinePercent ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.10),
                        value: showsInlinePercent
                    )
            }
            .frame(width: railWidth, height: cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RailPressButtonStyle())
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.72), value: isSelected)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.68), value: isHovered)
        .accessibilityLabel(tool.rawValue)
        .accessibilityValue(accessibilityValue)
    }

    private var statusColor: Color {
        guard item?.available == true, let percent = item?.sessionPercent else {
            return Color.white.opacity(0.20)
        }
        return StatusColor.forPercent(percent)
    }

    private var percentLabel: String {
        guard item?.available == true, let percent = item?.sessionPercent else { return "—" }
        return "\(Int((percent * 100).rounded()))%"
    }

    private var isShowingCachedValue: Bool {
        item?.refreshState.isShowingCachedValue == true
    }

    private var accessibilityValue: String {
        guard isShowingCachedValue else { return percentLabel }
        let status = item?.refreshState.status == .stale ? "更新失败" : "正在刷新"
        return "\(percentLabel)，上次数据，\(status)"
    }
}

private struct UsageHoverLabel: View {
    let item: ToolUsage?
    let tool: ToolUsage.Tool

    var body: some View {
        HStack(spacing: 5) {
            BrandMark(tool: tool, size: 9)
            Text(tool.rawValue)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(percentLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isShowingCachedValue ? Color.orange : RailTheme.textSecondary)
                .lineLimit(1)
                .overlay(alignment: .topTrailing) {
                    if isShowingCachedValue {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 4, height: 4)
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .foregroundStyle(RailTheme.text)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(RailTheme.labelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(RailTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.rawValue) hover label, \(accessibilityValue)")
        .accessibilityIdentifier("quota-label-\(tool.rawValue.lowercased())")
    }

    private var percentLabel: String {
        guard item?.available == true, let percent = item?.sessionPercent else { return "—" }
        return "\(Int((percent * 100).rounded()))%"
    }

    private var isShowingCachedValue: Bool {
        item?.refreshState.isShowingCachedValue == true
    }

    private var accessibilityValue: String {
        guard isShowingCachedValue else { return percentLabel }
        let status = item?.refreshState.status == .stale ? "更新失败" : "正在刷新"
        return "\(percentLabel)，上次数据，\(status)"
    }
}

private struct UsageCard: View {
    let item: ToolUsage?
    let tool: ToolUsage.Tool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RailTheme.cardBackground)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    BrandMark(tool: tool, size: 11)
                    Text("\(tool.rawValue) Usage")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(RailTheme.text)
                    Spacer(minLength: 0)
                    refreshStatus
                        .font(.system(size: 7.2, weight: .medium))
                        .lineLimit(1)
                }

                if let item, item.available {
                    UsageLine(
                        label: primaryUsageLabel,
                        percent: item.sessionPercent,
                        reset: item.sessionResetsLabel
                    )
                    if item.weeklyPercent != nil {
                        UsageLine(
                            label: secondaryUsageLabel,
                            percent: item.weeklyPercent,
                            reset: item.weeklyResetsLabel
                        )
                    }
                } else {
                    unavailableContent
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .id(tool)
            .transition(
                reduceMotion
                    ? .identity
                    : .opacity.combined(with: .offset(y: 2))
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RailTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: 3, y: 5)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: tool
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tool.rawValue) usage card")
        .accessibilityIdentifier("quota-card-\(tool.rawValue.lowercased())")
    }

    @ViewBuilder
    private var unavailableContent: some View {
        HStack(spacing: 6) {
            Text(unavailableReason)
                .font(.system(size: 8.5))
                .foregroundStyle(RailTheme.textSecondary)
                .lineLimit(2)
                .help(unavailableReason)
            Spacer(minLength: 0)
            if let url = item?.actionURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 3) {
                        Text(item?.actionTitle ?? "Open")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(RailTheme.text)
                }
                .buttonStyle(RailPressButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var refreshStatus: some View {
        if let item {
            switch item.refreshState.status {
            case .refreshing:
                Text("刷新中")
                    .foregroundStyle(RailTheme.textMuted)
            case .fresh:
                if let date = item.refreshState.lastSuccess {
                    Text(date, style: .time)
                        .foregroundStyle(RailTheme.textMuted)
                } else {
                    Text("已更新")
                        .foregroundStyle(RailTheme.textMuted)
                }
            case .stale:
                HStack(spacing: 2) {
                    Text("失败")
                    if let date = item.refreshState.lastSuccess {
                        Text(date, style: .time)
                    }
                }
                .foregroundStyle(.orange)
                .help(item.refreshState.error ?? "刷新失败")
            case .unavailable:
                Text("不可用")
                    .foregroundStyle(RailTheme.textMuted)
            }
        }
    }

    private var unavailableReason: String {
        item?.refreshState.error ?? item?.note ?? "Usage unavailable"
    }

    private var primaryUsageLabel: String {
        switch tool {
        case .grok: return "Weekly limit"
        case .cursor: return "Grok Bot weekly"
        case .codex, .claude: return "Current session"
        }
    }

    private var secondaryUsageLabel: String {
        switch tool {
        case .claude: return "All models"
        case .cursor: return "Monthly total"
        case .codex, .grok: return "Weekly limit"
        }
    }
}

private struct UsageLine: View {
    let label: String
    let percent: Double?
    let reset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(RailTheme.textSecondary)
                Spacer(minLength: 2)
                if let reset {
                    Text("Resets \(reset)")
                        .font(.system(size: 7.2))
                        .foregroundStyle(RailTheme.textMuted)
                        .lineLimit(1)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    if let percent {
                        Capsule()
                            .fill(percent > 1 ? Color.red : StatusColor.forPercent(percent))
                            .frame(width: max(3, proxy.size.width * min(1, percent)))
                    }
                }
            }
            .frame(height: 3)

            Text(usedLabel)
                .font(.system(size: 8.2, weight: .medium))
                .foregroundStyle(RailTheme.textSecondary)
        }
    }

    private var usedLabel: String {
        guard let percent else { return "Not available" }
        return "\(Int((percent * 100).rounded()))% Used"
    }
}

private struct RailPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}
