import Foundation

public enum CodexRateLimitReader {
    private struct FileSnapshot {
        let snapshot: CodexRateLimitSnapshot
        let modifiedAt: Date
    }

    public static func latestSnapshot(
        in sessionsDirectory: URL,
        maxFiles: Int = 32,
        tailByteLimit: Int = 1_048_576,
        now: Date = Date(),
        maximumAge: TimeInterval = 15 * 60
    ) -> CodexRateLimitSnapshot? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            candidates.append((url, values.contentModificationDate ?? .distantPast))
        }

        candidates.sort { $0.modifiedAt > $1.modifiedAt }
        let snapshots: [FileSnapshot] = candidates.prefix(max(1, maxFiles)).compactMap { candidate in
            guard let data = try? tailData(from: candidate.url, maxBytes: tailByteLimit),
                  let snapshot = latestSnapshot(inJSONLData: data) else { return nil }
            return FileSnapshot(snapshot: snapshot, modifiedAt: candidate.modifiedAt)
        }

        let latest = snapshots.max { lhs, rhs in
            (lhs.snapshot.observedAt ?? lhs.modifiedAt) < (rhs.snapshot.observedAt ?? rhs.modifiedAt)
        }
        guard let latest else { return nil }
        let observedAt = latest.snapshot.observedAt ?? latest.modifiedAt
        guard now.timeIntervalSince(observedAt) >= 0,
              now.timeIntervalSince(observedAt) <= maximumAge
        else { return nil }
        return latest.snapshot
    }

    public static func latestSnapshot(inJSONLData data: Data) -> CodexRateLimitSnapshot? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var latest: CodexRateLimitSnapshot?
        text.enumerateLines { line, _ in
            if let snapshot = snapshot(fromJSONLine: line) {
                latest = snapshot
            }
        }
        return latest
    }

    public static func snapshot(fromJSONLine line: String) -> CodexRateLimitSnapshot? {
        guard line.contains("\"rate_limits\""),
              let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let rateLimits = payload["rate_limits"] as? [String: Any],
              let primary = rateLimits["primary"] as? [String: Any],
              let primaryUsed = number(primary["used_percent"])
        else { return nil }

        let secondary = rateLimits["secondary"] as? [String: Any]
        let observedAt = (root["timestamp"] as? String).flatMap(parseISO8601)

        return CodexRateLimitSnapshot(
            primaryFraction: primaryUsed / 100,
            primaryResetsAt: unixDate(primary["resets_at"]),
            secondaryFraction: number(secondary?["used_percent"]).map { $0 / 100 },
            secondaryResetsAt: unixDate(secondary?["resets_at"]),
            planType: rateLimits["plan_type"] as? String,
            observedAt: observedAt
        )
    }

    private static func tailData(from url: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let end = try handle.seekToEnd()
        let byteLimit = UInt64(max(1, maxBytes))
        let offset = end > byteLimit ? end - byteLimit : 0
        try handle.seek(toOffset: offset)
        var data = try handle.readToEnd() ?? Data()

        if offset > 0, let newline = data.firstIndex(of: 0x0A) {
            data.removeSubrange(data.startIndex...newline)
        }
        return data
    }

    private static func unixDate(_ value: Any?) -> Date? {
        number(value).map { Date(timeIntervalSince1970: $0) }
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
