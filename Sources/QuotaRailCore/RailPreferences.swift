import Combine
import Foundation

public final class RailPreferences: ObservableObject {
    public static let providerIDs: Set<String> = ["Codex", "Claude", "Grok", "Cursor"]

    private enum Key {
        static let trackScale = "QuotaRail.trackScale"
        static let iconScale = "QuotaRail.iconScale"
        static let idleIconScale = "QuotaRail.idleIconScale"
        static let hoverMaxScale = "QuotaRail.hoverMaxScale"
        static let alwaysVisible = "QuotaRail.alwaysVisible"
        static let visibleProviderIDs = "QuotaRail.visibleProviderIDs"
    }

    private let defaults: UserDefaults
    private let persistChanges: Bool

    @Published public var trackScale: Double {
        didSet {
            let value = Self.clamp(trackScale, 0.75, 1.35)
            if trackScale != value {
                trackScale = value
                return
            }
            persist(trackScale, forKey: Key.trackScale)
        }
    }

    @Published public var iconScale: Double {
        didSet {
            let value = Self.clamp(iconScale, 0.70, 1.35)
            if iconScale != value {
                iconScale = value
                return
            }
            persist(iconScale, forKey: Key.iconScale)
        }
    }

    @Published public var idleIconScale: Double {
        didSet {
            let value = Self.clamp(idleIconScale, 0.60, 1.00)
            if idleIconScale != value {
                idleIconScale = value
                return
            }
            if hoverMaxScale < idleIconScale + 0.05 {
                hoverMaxScale = min(1.80, idleIconScale + 0.05)
            }
            persist(idleIconScale, forKey: Key.idleIconScale)
        }
    }

    @Published public var hoverMaxScale: Double {
        didSet {
            let minimum = max(1.05, idleIconScale + 0.05)
            let value = Self.clamp(hoverMaxScale, minimum, 1.80)
            if hoverMaxScale != value {
                hoverMaxScale = value
                return
            }
            persist(hoverMaxScale, forKey: Key.hoverMaxScale)
        }
    }

    @Published public var alwaysVisible: Bool {
        didSet { persist(alwaysVisible, forKey: Key.alwaysVisible) }
    }

    @Published public private(set) var visibleProviderIDs: Set<String>

    public init(defaults: UserDefaults = .standard, persistChanges: Bool = true) {
        self.defaults = defaults
        self.persistChanges = persistChanges

        let storedTrack = defaults.object(forKey: Key.trackScale) as? NSNumber
        let storedIcon = defaults.object(forKey: Key.iconScale) as? NSNumber
        let storedIdle = defaults.object(forKey: Key.idleIconScale) as? NSNumber
        let storedHover = defaults.object(forKey: Key.hoverMaxScale) as? NSNumber
        self.trackScale = Self.clamp(storedTrack?.doubleValue ?? 1, 0.75, 1.35)
        self.iconScale = Self.clamp(storedIcon?.doubleValue ?? 1, 0.70, 1.35)
        let resolvedIdle = Self.clamp(storedIdle?.doubleValue ?? 1, 0.60, 1.00)
        self.idleIconScale = resolvedIdle
        self.hoverMaxScale = Self.clamp(
            storedHover?.doubleValue ?? 1.5,
            max(1.05, resolvedIdle + 0.05),
            1.80
        )
        self.alwaysVisible = defaults.object(forKey: Key.alwaysVisible) as? Bool ?? false

        let storedProviders = Set(defaults.stringArray(forKey: Key.visibleProviderIDs) ?? [])
            .intersection(Self.providerIDs)
        self.visibleProviderIDs = storedProviders.isEmpty ? Self.providerIDs : storedProviders
    }

    public func isProviderVisible(_ id: String) -> Bool {
        visibleProviderIDs.contains(id)
    }

    public func setProviderVisible(_ id: String, _ visible: Bool) {
        guard Self.providerIDs.contains(id) else { return }
        var next = visibleProviderIDs
        if visible {
            next.insert(id)
        } else {
            guard next.count > 1 else { return }
            next.remove(id)
        }
        guard next != visibleProviderIDs else { return }
        visibleProviderIDs = next
        if persistChanges {
            defaults.set(Array(next).sorted(), forKey: Key.visibleProviderIDs)
        }
    }

    public func reset() {
        trackScale = 1
        iconScale = 1
        idleIconScale = 1
        hoverMaxScale = 1.5
        alwaysVisible = false
        visibleProviderIDs = Self.providerIDs
        if persistChanges {
            defaults.set(Array(Self.providerIDs).sorted(), forKey: Key.visibleProviderIDs)
        }
    }

    private func persist(_ value: Any, forKey key: String) {
        guard persistChanges else { return }
        defaults.set(value, forKey: key)
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

public struct RailLayout: Equatable, Sendable {
    public let trackScale: Double
    public let providerCount: Int

    public init(trackScale: Double, providerCount: Int) {
        self.trackScale = min(1.35, max(0.75, trackScale))
        self.providerCount = max(1, providerCount)
    }

    public var railWidth: Double { 58 * trackScale }
    public var interactiveWidth: Double { railWidth }
    public var sensorWidth: Double { glassBackgroundWidth }
    public var topInset: Double { 16 * trackScale }
    public var cellHeight: Double { 78 * trackScale }
    public var railHeight: Double { topInset * 2 + cellHeight * Double(providerCount) }
    public var hoverLabelWidth: Double { 104 }
    public var hoverLabelHeight: Double { 28 }
    public var hoverLabelGap: Double { 50 * trackScale }
    public var cardWidth: Double { 196 }
    public var cardGap: Double { 52 * trackScale }
    public var glassBackgroundWidth: Double { 96 * trackScale }
    public var liquidBulgeDepth: Double { 38 * trackScale }
    public var hoverWidth: Double { railWidth + hoverLabelGap + hoverLabelWidth }
    public var pinnedWidth: Double { railWidth + cardGap + cardWidth }
}
