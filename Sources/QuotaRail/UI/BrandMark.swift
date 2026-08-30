import SwiftUI
import AppKit

/// Each provider's actual mark, loaded from bundled PNGs (Resources/Brand) —
/// sourced from lobehub/lobe-icons (MIT licensed), which ships these exact
/// monochrome marks specifically for representing AI providers in UI like this.
/// The bundled marks are raster assets, which keeps rendering deterministic in
/// a tiny non-activating panel without depending on SVG support differences.
struct BrandMark: View {
    let tool: ToolUsage.Tool
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        Group {
            if tool == .grok {
                Text("x")
                    .font(.system(size: size * 0.78, weight: .semibold, design: .monospaced))
            } else if let nsImage = Self.image(for: tool) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback if the bundled asset is somehow missing.
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }

    private static var cache: [ToolUsage.Tool: NSImage] = [:]

    private static func image(for tool: ToolUsage.Tool) -> NSImage? {
        if let cached = cache[tool] { return cached }
        let name: String
        switch tool {
        case .codex: name = "openai"
        case .claude: name = "claude"
        case .grok: return nil
        case .cursor: name = "cursor"
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache[tool] = image
        return image
    }
}
