import Foundation

public struct CodexRateLimitSnapshot: Equatable, Sendable {
    public let primaryFraction: Double
    public let primaryResetsAt: Date?
    public let secondaryFraction: Double?
    public let secondaryResetsAt: Date?
    public let planType: String?
    public let observedAt: Date?

    public init(
        primaryFraction: Double,
        primaryResetsAt: Date?,
        secondaryFraction: Double?,
        secondaryResetsAt: Date?,
        planType: String?,
        observedAt: Date?
    ) {
        self.primaryFraction = primaryFraction
        self.primaryResetsAt = primaryResetsAt
        self.secondaryFraction = secondaryFraction
        self.secondaryResetsAt = secondaryResetsAt
        self.planType = planType
        self.observedAt = observedAt
    }
}

public struct ClaudeUsageSnapshot: Equatable, Sendable {
    public let sessionFraction: Double
    public let sessionResetsAt: Date?
    public let weeklyFraction: Double?
    public let weeklyResetsAt: Date?

    public init(
        sessionFraction: Double,
        sessionResetsAt: Date?,
        weeklyFraction: Double?,
        weeklyResetsAt: Date?
    ) {
        self.sessionFraction = sessionFraction
        self.sessionResetsAt = sessionResetsAt
        self.weeklyFraction = weeklyFraction
        self.weeklyResetsAt = weeklyResetsAt
    }
}

public struct CursorUsageSnapshot: Equatable, Sendable {
    public let totalFraction: Double
    public let cursorModelsFraction: Double?
    public let otherModelsFraction: Double?
    public let resetsAt: Date?
    public let membershipType: String?
    public let onDemandUsedUSD: Double?
    public let onDemandLimitUSD: Double?

    public init(
        totalFraction: Double,
        cursorModelsFraction: Double?,
        otherModelsFraction: Double?,
        resetsAt: Date?,
        membershipType: String?,
        onDemandUsedUSD: Double?,
        onDemandLimitUSD: Double?
    ) {
        self.totalFraction = totalFraction
        self.cursorModelsFraction = cursorModelsFraction
        self.otherModelsFraction = otherModelsFraction
        self.resetsAt = resetsAt
        self.membershipType = membershipType
        self.onDemandUsedUSD = onDemandUsedUSD
        self.onDemandLimitUSD = onDemandLimitUSD
    }
}

public struct CursorGrokBotUsageSnapshot: Equatable, Sendable {
    public let usedFraction: Double
    public let resetsAt: Date?

    public init(usedFraction: Double, resetsAt: Date?) {
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
    }
}

public enum UsageFormatting {
    public static func resetLabel(until date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }

        let minutes = max(1, Int(interval / 60))
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            let hours = (minutes % (24 * 60)) / 60
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
