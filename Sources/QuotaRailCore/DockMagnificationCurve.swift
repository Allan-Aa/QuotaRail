import Foundation

public struct DockMagnificationTransform: Equatable, Sendable {
    public let influence: Double
    public let scale: Double
    public let horizontalOffset: Double
    public let verticalOffset: Double

    public init(
        influence: Double,
        scale: Double,
        horizontalOffset: Double,
        verticalOffset: Double
    ) {
        self.influence = influence
        self.scale = scale
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }
}

public struct DockMagnificationConfiguration: Equatable, Sendable {
    public let idleScale: Double
    public let hoverMaxScale: Double
    public let trackScale: Double

    public init(idleScale: Double, hoverMaxScale: Double, trackScale: Double) {
        self.idleScale = min(1, max(0.60, idleScale))
        self.hoverMaxScale = min(1.80, max(self.idleScale + 0.05, hoverMaxScale))
        self.trackScale = min(1.35, max(0.75, trackScale))
    }

    public static let defaultValue = DockMagnificationConfiguration(
        idleScale: 1,
        hoverMaxScale: 1.5,
        trackScale: 1
    )
}

public enum DockMagnificationCurve {
    public static func transform(
        pointerY: Double,
        itemCenterY: Double,
        reduceMotion: Bool = false,
        configuration: DockMagnificationConfiguration = .defaultValue
    ) -> DockMagnificationTransform {
        let spread = 64 * configuration.trackScale
        let horizontalLift = 26 * configuration.trackScale
        let verticalPush = 10.5 * configuration.trackScale
        let delta = itemCenterY - pointerY
        let distance = abs(delta)
        let influence = exp(-(distance * distance) / (2 * spread * spread))
        let motionFactor = reduceMotion ? 0.15 : 1.0
        let verticalWave = tanh(delta / spread)

        return DockMagnificationTransform(
            influence: influence,
            scale: configuration.idleScale
                + (configuration.hoverMaxScale - configuration.idleScale) * influence * motionFactor,
            horizontalOffset: -horizontalLift * influence * motionFactor,
            verticalOffset: verticalWave * verticalPush * influence * motionFactor
        )
    }
}
