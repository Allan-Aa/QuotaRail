import SwiftUI

/// Compact always-visible pill anchored to the edge of the screen.
/// Drag anywhere on it to reposition; click a ring to open the full panel.
struct FloatingPillView: View {
    @ObservedObject var store: UsageStore
    @Binding var selected: ToolUsage.Tool
    var onSelectRing: () -> Void

    var body: some View {
        RingStripView(store: store, selected: $selected, ringSize: 40)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.035, green: 0.035, blue: 0.038).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.09))
            )
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 4)
    }
}
