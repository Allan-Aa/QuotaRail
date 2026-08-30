import Foundation
import QuotaRailCore

/// Reads real usage straight from Anthropic's own account API — the same
/// endpoint Claude Code's `/usage` and `/status` use internally — instead of
/// estimating from local logs. Credentials are the ones Claude Code already
/// wrote to disk when you ran `claude login`; nothing is sent anywhere except
/// straight to api.anthropic.com with your own token.
enum ClaudeOAuthEngine {
    struct Snapshot {
        let sessionPercent: Double
        let sessionResetsLabel: String
        let weeklyPercent: Double?
        let weeklyResetsLabel: String?
        let planLabel: String?
    }

    enum Failure: Error {
        case credentialsUnavailable
        case requestFailed
        case invalidResponse

        var userMessage: String {
            switch self {
            case .credentialsUnavailable:
                return "未找到 Claude Code 登录凭据。请先运行 claude login。"
            case .requestFailed:
                return "Claude 用量接口暂时不可用。"
            case .invalidResponse:
                return "Claude 返回了无法识别的用量数据。"
            }
        }
    }

    private struct Credentials {
        let accessToken: String
        let rateLimitTier: String?
        let subscriptionType: String?
    }

    private static func loadCredentials() -> Credentials? {
        if let fromFile = loadCredentialsFromFile() { return fromFile }
        return loadCredentialsFromKeychain()
    }

    private static func loadCredentialsFromFile() -> Credentials? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let path = home + "/.claude/.credentials.json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return parseCredentials(data)
    }

    // Newer Claude Code versions store the OAuth payload in the macOS Keychain.
    // Reading through macOS's signed security tool avoids an ad-hoc app signature
    // becoming stuck behind an invisible Keychain authorization prompt.
    private static func loadCredentialsFromKeychain() -> Credentials? {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-w",
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        guard finished.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return parseCredentials(data)
    }

    private static func parseCredentials(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        return Credentials(
            accessToken: token,
            rateLimitTier: oauth["rateLimitTier"] as? String,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    static func computeSnapshot() -> Result<Snapshot, Failure> {
        guard let credentials = loadCredentials() else { return .failure(.credentialsUnavailable) }

        switch fetchUsageData(accessToken: credentials.accessToken) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let data):
            guard let usage = ClaudeUsagePayloadParser.parse(data: data) else {
                return .failure(.invalidResponse)
            }
            return .success(Snapshot(
                sessionPercent: usage.sessionFraction,
                sessionResetsLabel: UsageFormatting.resetLabel(until: usage.sessionResetsAt) ?? "unknown",
                weeklyPercent: usage.weeklyFraction,
                weeklyResetsLabel: UsageFormatting.resetLabel(until: usage.weeklyResetsAt),
                planLabel: planLabel(
                    rateLimitTier: credentials.rateLimitTier,
                    subscriptionType: credentials.subscriptionType
                )
            ))
        }
    }

    // Mirrors the plan-label logic used by community usage trackers: prefer
    // subscriptionType, fall back to rate_limit_tier, and surface the Max
    // usage multiplier (e.g. "default_claude_max_20x" -> "Max 20x") when present.
    private static func planLabel(rateLimitTier: String?, subscriptionType: String?) -> String? {
        let words: (String?) -> [String] = { text in
            (text ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }

        func basePlan(_ text: String?) -> String? {
            let w = words(text)
            if w.contains("max") { return "Max" }
            if w.contains("pro") { return "Pro" }
            if w.contains("team") { return "Team" }
            if w.contains("enterprise") { return "Enterprise" }
            if w.contains("ultra") { return "Ultra" }
            return nil
        }

        guard let plan = basePlan(subscriptionType) ?? basePlan(rateLimitTier) else { return nil }

        if plan == "Max" {
            let tierWords = words(rateLimitTier)
            if let maxIndex = tierWords.firstIndex(of: "max"), tierWords.indices.contains(maxIndex + 1) {
                let multiplier = tierWords[maxIndex + 1]
                if multiplier.hasSuffix("x"), Int(multiplier.dropLast()) != nil {
                    return "Max \(multiplier)"
                }
            }
        }
        return plan
    }

    private static func fetchUsageData(accessToken: String) -> Result<Data, Failure> {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return .failure(.requestFailed)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaRail/0.9.1", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Failure> = .failure(.requestFailed)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else { return }
            result = .success(data)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result
    }
}
