import Foundation

/// Shared between the floating pill and the detail panel so tapping a ring
/// on the pill instantly updates the already-open panel's tab — a plain
/// state change, no window repositioning — instead of each owning its own
/// selection and going out of sync.
final class SelectionModel: ObservableObject {
    @Published var selected: ToolUsage.Tool = .claude
}
