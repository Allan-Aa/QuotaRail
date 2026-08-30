import SwiftUI

enum StatusColor {
    /// Matches the reference design: green under 50%, amber under 80%, red/orange above.
    static func forPercent(_ p: Double) -> Color {
        switch p {
        case ..<0.5: return Color(red: 0.08, green: 0.95, blue: 0.58)
        case ..<0.8: return Color(red: 0.90, green: 0.94, blue: 0.12)
        default: return Color(red: 1.00, green: 0.30, blue: 0.12)
        }
    }
}

struct RingView: View {
    let percent: Double?
    let tool: ToolUsage.Tool
    var size: CGFloat = 40
    var rotationDegrees: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { max(2, size * 0.078) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(RailTheme.ringTrack, lineWidth: lineWidth)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(1.0, max(0.02, percent)))
                    .stroke(
                        percent > 1.0 ? Color.red : StatusColor.forPercent(percent),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90 + rotationDegrees))
            }
            BrandMark(tool: tool, size: size * 0.46, color: percent == nil ? .white.opacity(0.34) : .white)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: percent)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: rotationDegrees)
    }
}
