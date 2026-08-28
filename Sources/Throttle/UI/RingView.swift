import SwiftUI

enum StatusColor {
    /// Matches the reference design: green under 50%, amber under 80%, red/orange above.
    static func forPercent(_ p: Double) -> Color {
        switch p {
        case ..<0.5: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case ..<0.8: return Color(red: 0.98, green: 0.80, blue: 0.20)
        default: return Color(red: 0.98, green: 0.35, blue: 0.20)
        }
    }
}

struct RingView: View {
    let percent: Double?
    let tool: ToolUsage.Tool
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 3)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(1.0, max(0.02, percent)))
                    .stroke(
                        percent > 1.0 ? Color.red : StatusColor.forPercent(percent),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            BrandMark(tool: tool, size: size * 0.5, color: percent == nil ? .white.opacity(0.35) : .white)
        }
        .frame(width: size, height: size)
    }
}
