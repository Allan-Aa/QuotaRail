import Foundation

public enum ClaudeUsagePayloadParser {
    public static func parse(data: Data) -> ClaudeUsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = window(root["five_hour"]) else { return nil }

        let weekly = window(root["seven_day"])
        return ClaudeUsageSnapshot(
            sessionFraction: session.fraction,
            sessionResetsAt: session.resetsAt,
            weeklyFraction: weekly?.fraction,
            weeklyResetsAt: weekly?.resetsAt
        )
    }

    private static func window(_ value: Any?) -> (fraction: Double, resetsAt: Date?)? {
        guard let object = value as? [String: Any],
              let utilization = number(object["utilization"]) else { return nil }
        return (
            utilization / 100,
            (object["resets_at"] as? String).flatMap(parseISO8601)
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
