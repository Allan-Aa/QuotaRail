import CoreGraphics
import Darwin
import Foundation

guard [3, 5].contains(CommandLine.arguments.count),
      let target = Int32(CommandLine.arguments[1]),
      let duration = Double(CommandLine.arguments[2]),
      duration > 0
else {
    exit(2)
}

let railName = CommandLine.arguments.count == 5
    ? CommandLine.arguments[3]
    : "QuotaRail Preview Rail"
let overlayName = CommandLine.arguments.count == 5
    ? CommandLine.arguments[4]
    : "QuotaRail Preview Overlay"

func size(named name: String, in windows: [[String: Any]]) -> (Int, Int) {
    guard let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == target
            && ($0[kCGWindowName as String] as? String) == name
    }), let bounds = window[kCGWindowBounds as String] as? [String: Any],
    let width = bounds["Width"] as? Int,
    let height = bounds["Height"] as? Int else {
        return (0, 0)
    }
    return (width, height)
}

let deadline = ProcessInfo.processInfo.systemUptime + duration
while ProcessInfo.processInfo.systemUptime < deadline {
    let now = ProcessInfo.processInfo.systemUptime
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    let rail = size(named: railName, in: windows)
    let overlay = size(named: overlayName, in: windows)
    print(String(format: "%.6f %d %d %d %d", now, rail.0, rail.1, overlay.0, overlay.1))
    fflush(stdout)
    usleep(10_000)
}
