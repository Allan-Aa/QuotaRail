import SwiftUI

enum RailTheme {
    static let background = Color(red: 5 / 255, green: 5 / 255, blue: 6 / 255)
    static let railGlassTint = Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255).opacity(0.82)
    static let labelBackground = Color(red: 7 / 255, green: 8 / 255, blue: 11 / 255).opacity(0.94)
    static let cardBackground = Color(red: 7 / 255, green: 8 / 255, blue: 11 / 255).opacity(0.96)
    static let surface = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.08)
    static let glassEdge = Color.white.opacity(0.12)
    static let ringTrack = Color.white.opacity(0.16)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.66)
    static let textMuted = Color.white.opacity(0.40)
}

struct MiniTabShape: Shape {
    var corner: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let radius = min(corner, rect.width, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct LiquidRailShape: Shape {
    var focusY: CGFloat
    var bulgeDepth: CGFloat
    var railWidth: CGFloat = 58
    var corner: CGFloat = 28
    var bulgeHalfHeight: CGFloat = 48

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(focusY, bulgeDepth) }
        set {
            focusY = newValue.first
            bulgeDepth = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let baseX = rect.maxX - min(railWidth, rect.width)
        let depth = min(max(0, bulgeDepth), baseX - rect.minX)
        let outwardX = baseX - depth
        let radius = min(corner, rect.height / 3)
        let halfHeight = min(bulgeHalfHeight, rect.height / 3)
        let centerY = min(
            max(focusY, radius + halfHeight / 2),
            rect.maxY - radius - halfHeight / 2
        )
        let topJoin = max(radius, centerY - halfHeight)
        let bottomJoin = min(rect.maxY - radius, centerY + halfHeight)

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: baseX, y: rect.maxY - radius),
            control1: CGPoint(x: rect.maxX - radius * 0.40, y: rect.maxY),
            control2: CGPoint(x: baseX, y: rect.maxY - radius * 0.42)
        )
        path.addLine(to: CGPoint(x: baseX, y: bottomJoin))
        path.addCurve(
            to: CGPoint(x: outwardX, y: centerY),
            control1: CGPoint(x: baseX, y: centerY + halfHeight * 0.56),
            control2: CGPoint(x: outwardX, y: centerY + halfHeight * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: baseX, y: topJoin),
            control1: CGPoint(x: outwardX, y: centerY - halfHeight * 0.34),
            control2: CGPoint(x: baseX, y: centerY - halfHeight * 0.56)
        )
        path.addLine(to: CGPoint(x: baseX, y: radius))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: baseX, y: radius * 0.42),
            control2: CGPoint(x: rect.maxX - radius * 0.40, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct UsageBubbleShape: Shape {
    var pointerY: CGFloat
    var corner: CGFloat = 11
    var pointerDepth: CGFloat = 10
    var pointerHalfHeight: CGFloat = 6

    var animatableData: CGFloat {
        get { pointerY }
        set { pointerY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyMaxX = rect.maxX - pointerDepth
        let radius = min(corner, rect.height / 2, bodyMaxX / 2)
        let clampedPointerY = min(
            max(pointerY, radius + pointerHalfHeight),
            rect.maxY - radius - pointerHalfHeight
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: bodyMaxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX, y: rect.minY + radius),
            control: CGPoint(x: bodyMaxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: bodyMaxX, y: clampedPointerY - pointerHalfHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: clampedPointerY))
        path.addLine(to: CGPoint(x: bodyMaxX, y: clampedPointerY + pointerHalfHeight))
        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX - radius, y: rect.maxY),
            control: CGPoint(x: bodyMaxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
