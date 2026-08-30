import AppKit
import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 3,
      let target = Int32(CommandLine.arguments[1]),
      let duration = Double(CommandLine.arguments[2]),
      duration > 0
else {
    exit(2)
}

let deadline = ProcessInfo.processInfo.systemUptime + duration
while ProcessInfo.processInfo.systemUptime < deadline {
    let now = ProcessInfo.processInfo.systemUptime
    let pointer = NSEvent.mouseLocation
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    if let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? Int32) == target
    }), let bounds = window[kCGWindowBounds as String] as? [String: Any],
       let x = bounds["X"] as? Int,
       let y = bounds["Y"] as? Int,
       let width = bounds["Width"] as? Int,
       let height = bounds["Height"] as? Int {
        print(String(
            format: "%.6f %.2f %.2f %d %d %d %d",
            now,
            pointer.x,
            pointer.y,
            x,
            y,
            width,
            height
        ))
    }
    usleep(10_000)
}
