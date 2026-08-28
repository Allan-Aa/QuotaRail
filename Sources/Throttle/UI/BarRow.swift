import SwiftUI

struct BarRow: View {
    let title: String
    let percent: Double?
    let resetsLabel: String?
    var cost: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if let resetsLabel {
                    Text("Resets \(resetsLabel)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    if let percent {
                        Capsule()
                            .fill(percent > 1.0 ? .red : StatusColor.forPercent(percent))
                            .frame(width: max(4, geo.size.width * min(1.0, percent)))
                    }
                }
            }
            .frame(height: 5)
            Text(usedLabel)
                .font(.system(size: 11))
                .foregroundStyle(percent.map { $0 > 1.0 } == true ? .red.opacity(0.85) : .white.opacity(0.45))
        }
    }

    private var usedLabel: String {
        guard let percent else { return "Not available" }
        let pctText = "\(Int(percent * 100))% used"
        if let cost {
            return "\(pctText) · $\(String(format: "%.2f", cost))"
        }
        return pctText
    }
}
