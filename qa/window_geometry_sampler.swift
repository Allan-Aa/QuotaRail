import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 2,
      let target = Int32(CommandLine.arguments[1])
else {
    exit(2)
}

let deadline = ProcessInfo.processInfo.systemUptime + 3.0
while ProcessInfo.processInfo.systemUptime < deadline {
    let now = ProcessInfo.processInfo.systemUptime
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    if let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == target
    }), let bounds = window[kCGWindowBounds as String] as? [String: Any],
       let width = bounds["Width"] as? Int,
       let height = bounds["Height"] as? Int {
        print(String(format: "%.6f %d %d", now, width, height))
        fflush(stdout)
    }
    usleep(10_000)
}
