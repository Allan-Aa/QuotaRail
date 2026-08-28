import Foundation

/// Reads Claude Code's local session transcripts (~/.claude/projects/**/*.jsonl)
/// and estimates rolling-window usage. Anthropic does not expose an official
/// "percent used" API locally, so this approximates dollar cost from token
/// counts (using real per-model pricing ratios) and compares that against a
/// user-calibratable budget (Settings). Cost, not raw token count, is what
/// actually maps to rate-limit consumption — a raw token sum is dominated by
/// near-free cache reads and wildly overstates usage for cache-heavy workflows.
enum ClaudeUsageEngine {
    struct Snapshot {
        let sessionCost: Double
        let sessionPercent: Double
        let sessionResetsLabel: String
        let weeklyCost: Double
        let weeklyPercent: Double
        let weeklyResetsLabel: String
    }

    private struct Pricing {
        let input: Double
        let output: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
        let cacheRead: Double
    }

    // $ per token, derived from Anthropic's published $/million-token rates.
    private static let opus = Pricing(input: 15/1e6, output: 75/1e6, cacheWrite5m: 18.75/1e6, cacheWrite1h: 30/1e6, cacheRead: 1.5/1e6)
    private static let sonnet = Pricing(input: 3/1e6, output: 15/1e6, cacheWrite5m: 3.75/1e6, cacheWrite1h: 6/1e6, cacheRead: 0.3/1e6)
    private static let haiku = Pricing(input: 0.8/1e6, output: 4/1e6, cacheWrite5m: 1/1e6, cacheWrite1h: 1.6/1e6, cacheRead: 0.08/1e6)

    private static func pricing(for model: String?) -> Pricing {
        guard let model = model?.lowercased() else { return sonnet }
        if model.contains("opus") { return opus }
        if model.contains("haiku") { return haiku }
        return sonnet // sonnet, fable, and any unrecognized model default to sonnet-tier pricing
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func computeSnapshot(sessionBudget: Double, weeklyBudget: Double) -> Snapshot? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let projectsDir = home + "/.claude/projects"
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectsDir) else { return nil }

        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        var sessionCost = 0.0
        var weeklyCost = 0.0
        var earliestInWeek: Date? = nil
        var earliestInSession: Date? = nil

        for case let path as String in enumerator {
            guard path.hasSuffix(".jsonl") else { continue }
            let fullPath = projectsDir + "/" + path
            // Skip files not touched in the last week for speed.
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let modified = attrs[.modificationDate] as? Date,
               modified < weekAgo {
                continue
            }
            guard let data = fm.contents(atPath: fullPath),
                  let text = String(data: data, encoding: .utf8) else { continue }

            text.enumerateLines { line, _ in
                guard line.contains("\"usage\""), line.contains("\"timestamp\"") else { return }
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let tsString = obj["timestamp"] as? String,
                      let ts = isoFormatter.date(from: tsString),
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any]
                else { return }

                guard ts >= weekAgo else { return }

                let input = (usage["input_tokens"] as? Double) ?? 0
                let output = (usage["output_tokens"] as? Double) ?? 0
                let cacheRead = (usage["cache_read_input_tokens"] as? Double) ?? 0
                let cacheCreation = usage["cache_creation"] as? [String: Any]
                let cacheWrite5m = (cacheCreation?["ephemeral_5m_input_tokens"] as? Double) ?? 0
                let cacheWrite1h = (cacheCreation?["ephemeral_1h_input_tokens"] as? Double) ?? 0
                // Fall back to the flat field if the breakdown isn't present, treating it as 5m writes.
                let cacheCreateFlat = (cacheWrite5m == 0 && cacheWrite1h == 0)
                    ? ((usage["cache_creation_input_tokens"] as? Double) ?? 0)
                    : 0

                let price = pricing(for: message["model"] as? String)
                let cost = input * price.input
                    + output * price.output
                    + cacheWrite5m * price.cacheWrite5m
                    + cacheWrite1h * price.cacheWrite1h
                    + cacheCreateFlat * price.cacheWrite5m
                    + cacheRead * price.cacheRead

                weeklyCost += cost
                if earliestInWeek == nil || ts < earliestInWeek! { earliestInWeek = ts }
                if ts >= fiveHoursAgo {
                    sessionCost += cost
                    if earliestInSession == nil || ts < earliestInSession! { earliestInSession = ts }
                }
            }
        }

        let sessionReset = (earliestInSession ?? now).addingTimeInterval(5 * 3600)
        let weeklyReset = (earliestInWeek ?? now).addingTimeInterval(7 * 24 * 3600)

        return Snapshot(
            sessionCost: sessionCost,
            sessionPercent: sessionCost / sessionBudget,
            sessionResetsLabel: relativeLabel(until: sessionReset, now: now),
            weeklyCost: weeklyCost,
            weeklyPercent: weeklyCost / weeklyBudget,
            weeklyResetsLabel: relativeLabel(until: weeklyReset, now: now)
        )
    }

    private static func relativeLabel(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 24 {
            let days = hours / 24
            return "in \(days)d"
        } else if hours >= 1 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes) min"
        }
    }
}
