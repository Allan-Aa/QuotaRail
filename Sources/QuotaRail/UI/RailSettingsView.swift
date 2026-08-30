import QuotaRailCore
import SwiftUI

struct RailSettingsView: View {
    @ObservedObject var preferences: RailPreferences

    private let providers = ["Codex", "Claude", "Grok", "Cursor"]

    var body: some View {
        ZStack {
            RailTheme.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().overlay(RailTheme.border)

                section("外观") {
                    settingSlider(
                        title: "背景大小",
                        value: $preferences.trackScale,
                        range: 0.75...1.35
                    )
                    settingSlider(
                        title: "图标大小",
                        value: $preferences.iconScale,
                        range: 0.70...1.35
                    )
                    settingSlider(
                        title: "缩小状态",
                        value: $preferences.idleIconScale,
                        range: 0.60...1.00
                    )
                    settingSlider(
                        title: "悬停放大",
                        value: $preferences.hoverMaxScale,
                        range: hoverRange
                    )
                }

                section("显示方式") {
                    Toggle("常驻显示", isOn: $preferences.alwaysVisible)
                        .toggleStyle(.switch)
                        .tint(.white.opacity(0.82))
                    Text("开启后，鼠标移开时侧边栏仍留在屏幕边缘。")
                        .font(.system(size: 11))
                        .foregroundStyle(RailTheme.textMuted)
                }

                section("显示哪些 AI") {
                    ForEach(providers, id: \.self) { provider in
                        Toggle(provider, isOn: providerBinding(for: provider))
                            .toggleStyle(.switch)
                            .tint(.white.opacity(0.82))
                            .disabled(isLastVisibleProvider(provider))
                    }
                }

                HStack {
                    Text("至少保留一个 AI 显示。")
                        .font(.system(size: 11))
                        .foregroundStyle(RailTheme.textMuted)
                    Spacer()
                    Button("恢复默认") {
                        preferences.reset()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(width: 400, height: 610)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("QuotaRail")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(RailTheme.text)
                Text("外观与显示")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RailTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(RailTheme.textSecondary)
        }
    }

    private var hoverRange: ClosedRange<Double> {
        max(1.05, preferences.idleIconScale + 0.05)...1.80
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(RailTheme.textMuted)
            VStack(spacing: 8) {
                content()
            }
            .padding(11)
            .background(RailTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(RailTheme.border, lineWidth: 0.5)
            }
        }
    }

    private func settingSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RailTheme.text)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RailTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(.white.opacity(0.82))
        }
    }

    private func providerBinding(for provider: String) -> Binding<Bool> {
        Binding(
            get: { preferences.isProviderVisible(provider) },
            set: { preferences.setProviderVisible(provider, $0) }
        )
    }

    private func isLastVisibleProvider(_ provider: String) -> Bool {
        preferences.isProviderVisible(provider) && preferences.visibleProviderIDs.count == 1
    }
}
