import Foundation
import QuotaRailCore

/// Reads only service-provided rate-limit events from recent Codex rollout
/// tails. Prompt and response text are never surfaced or persisted by QuotaRail.
enum CodexUsageEngine {
    struct Snapshot {
        let primaryPercent: Double
        let primaryResetsLabel: String
        let secondaryPercent: Double?
        let secondaryResetsLabel: String?
        let planType: String?
    }

    static func computeSnapshot() -> Snapshot? {
        let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let snapshot = CodexRateLimitReader.latestSnapshot(in: sessionsDirectory) else { return nil }

        return Snapshot(
            primaryPercent: snapshot.primaryFraction,
            primaryResetsLabel: UsageFormatting.resetLabel(until: snapshot.primaryResetsAt) ?? "unknown",
            secondaryPercent: snapshot.secondaryFraction,
            secondaryResetsLabel: UsageFormatting.resetLabel(until: snapshot.secondaryResetsAt),
            planType: snapshot.planType
        )
    }
}
