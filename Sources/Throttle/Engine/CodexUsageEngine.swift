import Foundation

/// Codex CLI writes real rate-limit percentages (from OpenAI's API) into its
/// local session rollout files at ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl.
/// We just read the most recent one — no estimation needed.
enum CodexUsageEngine {
    struct Snapshot {
        let primaryPercent: Double
        let primaryResetsLabel: String
        let secondaryPercent: Double?
        let secondaryResetsLabel: String?
        let planType: String?
    }

    static func computeSnapshot() -> Snapshot? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let sessionsDir = home + "/.codex/sessions"
        let fm = FileManager.default

        guard let latestFile = mostRecentRollout(in: sessionsDir, fm: fm) else { return nil }
        guard let data = fm.contents(atPath: latestFile),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var lastRateLimits: [String: Any]? = nil
        text.enumerateLines { line, _ in
            guard line.contains("\"rate_limits\"") else { return }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any]
            else { return }
            lastRateLimits = rateLimits
        }

        guard let rl = lastRateLimits, let primary = rl["primary"] as? [String: Any],
              let usedPercent = primary["used_percent"] as? Double else { return nil }

        let now = Date()
        let primaryResetLabel = resetLabel(resetsAt: primary["resets_at"], now: now)

        var secondaryPercent: Double? = nil
        var secondaryResetLabel: String? = nil
        if let secondary = rl["secondary"] as? [String: Any],
           let sPercent = secondary["used_percent"] as? Double {
            secondaryPercent = sPercent
            secondaryResetLabel = resetLabel(resetsAt: secondary["resets_at"], now: now)
        }

        let planType = rl["plan_type"] as? String

        return Snapshot(
            primaryPercent: usedPercent / 100.0,
            primaryResetsLabel: primaryResetLabel,
            secondaryPercent: secondaryPercent.map { $0 / 100.0 },
            secondaryResetsLabel: secondaryResetLabel,
            planType: planType
        )
    }

    private static func resetLabel(resetsAt: Any?, now: Date) -> String {
        guard let seconds = resetsAt as? Double else { return "unknown" }
        let resetDate = Date(timeIntervalSince1970: seconds)
        let interval = resetDate.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let hours = Int(interval / 3600)
        if hours >= 24 {
            return "in \(hours / 24)d"
        } else if hours >= 1 {
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(Int(interval / 60)) min"
        }
    }

    private static func mostRecentRollout(in sessionsDir: String, fm: FileManager) -> String? {
        guard let enumerator = fm.enumerator(atPath: sessionsDir) else { return nil }
        var best: (path: String, date: Date)? = nil
        for case let path as String in enumerator {
            guard path.hasSuffix(".jsonl") else { continue }
            let fullPath = sessionsDir + "/" + path
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            if best == nil || modified > best!.date {
                best = (fullPath, modified)
            }
        }
        return best?.path
    }
}
