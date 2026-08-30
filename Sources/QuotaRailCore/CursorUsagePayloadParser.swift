import Foundation

public enum CursorUsagePayloadParser {
    public static func parse(data: Data) -> CursorUsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let individual = root["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let overall = individual?["overall"] as? [String: Any]
        let team = root["teamUsage"] as? [String: Any]
        let pooled = team?["pooled"] as? [String: Any]

        let cursorModelsFraction = percentFraction(plan?["autoPercentUsed"])
        let otherModelsFraction = percentFraction(plan?["apiPercentUsed"])

        let totalFraction = percentFraction(plan?["totalPercentUsed"])
            ?? ratio(in: plan)
            ?? ratio(in: overall)
            ?? ratio(in: pooled)

        guard let totalFraction else { return nil }

        let onDemand = individual?["onDemand"] as? [String: Any]
        let onDemandUsedUSD = number(onDemand?["used"]).map { $0 / 100 }
        let onDemandLimitUSD = number(onDemand?["limit"]).map { $0 / 100 }

        return CursorUsageSnapshot(
            totalFraction: totalFraction,
            cursorModelsFraction: cursorModelsFraction,
            otherModelsFraction: otherModelsFraction,
            resetsAt: (root["billingCycleEnd"] as? String).flatMap(parseISO8601),
            membershipType: root["membershipType"] as? String,
            onDemandUsedUSD: onDemandUsedUSD,
            onDemandLimitUSD: onDemandLimitUSD
        )
    }

    private static func percentFraction(_ value: Any?) -> Double? {
        guard let percent = number(value), percent.isFinite, percent >= 0 else { return nil }
        return percent / 100
    }

    private static func ratio(in object: [String: Any]?) -> Double? {
        guard let used = number(object?["used"]),
              let limit = number(object?["limit"]),
              used.isFinite,
              limit.isFinite,
              used >= 0,
              limit > 0
        else { return nil }
        return used / limit
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        default: return nil
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public enum CursorUsageAvailability {
    public static func hasDisplayableUsage(
        monthly: CursorUsageSnapshot?,
        grokBot: CursorGrokBotUsageSnapshot?
    ) -> Bool {
        monthly != nil || grokBot != nil
    }
}

public enum CursorAppSessionToken {
    public static func cookieHeader(accessToken: String, now: Date = Date()) -> String? {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              let userID = subject.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init),
              !userID.isEmpty,
              let expiration = (json["exp"] as? NSNumber)?.doubleValue,
              Date(timeIntervalSince1970: expiration).timeIntervalSince(now) > 60
        else {
            return nil
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard userID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
    }
}

public enum CursorGrokBotPayloadParser {
    public static func parse(data: Data) -> CursorGrokBotUsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["hasNonZeroIncludedLimit"] as? Bool == true,
              let usagePercent = number(root["usagePercent"]),
              usagePercent.isFinite,
              usagePercent >= 0
        else {
            return nil
        }

        return CursorGrokBotUsageSnapshot(
            usedFraction: min(100, usagePercent) / 100,
            resetsAt: (root["nextResetTimestampUtc"] as? String).flatMap(parseISO8601)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        default: return nil
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
