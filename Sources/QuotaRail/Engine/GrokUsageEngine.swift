import Foundation
import QuotaRailCore

/// Reuses the login created by the official Grok Build CLI. The token is read
/// from ~/.grok/auth.json for each refresh and is sent only to Grok's own
/// billing surfaces; QuotaRail never stores or refreshes it.
enum GrokUsageEngine {
    struct Snapshot {
        let weeklyPercent: Double
        let weeklyResetsLabel: String?
    }

    struct Status {
        let note: String
        let actionTitle: String
        let actionURL: URL
    }

    enum Failure: Error {
        case credentialsUnavailable
        case credentialsExpired
        case requestFailed
        case invalidResponse

        var userMessage: String {
            switch self {
            case .credentialsUnavailable:
                return "未找到 Grok Build 登录状态。请先运行 grok login。"
            case .credentialsExpired:
                return "Grok 登录已过期。请运行 grok login 刷新。"
            case .requestFailed:
                return "Grok 用量接口暂时不可用。"
            case .invalidResponse:
                return "Grok 返回了无法识别的用量数据。"
            }
        }
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
    }

    private enum FetchFailure: Error {
        case authentication
        case request
    }

    static func computeSnapshot() -> Result<Snapshot, Failure> {
        guard let credentials = loadCredentials() else {
            return .failure(.credentialsUnavailable)
        }
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
            return .failure(.credentialsExpired)
        }

        let proxyCandidate: GrokUsageCandidate?
        switch fetchCredits(accessToken: credentials.accessToken) {
        case .success(let data):
            proxyCandidate = GrokUsagePayloadParser.parseCreditsJSON(data: data)
        case .failure(.authentication):
            return .failure(.credentialsExpired)
        case .failure(.request):
            proxyCandidate = nil
        }

        if let fraction = proxyCandidate?.usedFraction {
            return .success(snapshot(fraction: fraction, resetsAt: proxyCandidate?.resetsAt))
        }

        switch fetchWebBilling(accessToken: credentials.accessToken) {
        case .success(let data):
            guard let candidate = GrokUsagePayloadParser.parseGRPCWeb(data: data),
                  let fraction = candidate.usedFraction
            else { return .failure(.invalidResponse) }
            return .success(snapshot(
                fraction: fraction,
                resetsAt: proxyCandidate?.resetsAt ?? candidate.resetsAt
            ))
        case .failure(.authentication):
            return .failure(.credentialsExpired)
        case .failure(.request):
            return .failure(.requestFailed)
        }
    }

    static func status() -> Status {
        Status(
            note: "QuotaRail 会复用 Grok Build 的本机登录状态，不读取浏览器 Cookie。",
            actionTitle: "打开 Grok Usage",
            actionURL: URL(string: "https://grok.com/?_s=usage")!
        )
    }

    private static func snapshot(fraction: Double, resetsAt: Date?) -> Snapshot {
        Snapshot(
            weeklyPercent: min(1, max(0, fraction)),
            weeklyResetsLabel: UsageFormatting.resetLabel(until: resetsAt)
        )
    }

    private static func loadCredentials() -> Credentials? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let entries = root.compactMap { scope, value -> (String, [String: Any])? in
            guard let object = value as? [String: Any] else { return nil }
            return (scope, object)
        }
        let ordered = entries.sorted { lhs, rhs in
            let lhsPreferred = lhs.0.hasPrefix("https://auth.x.ai::")
            let rhsPreferred = rhs.0.hasPrefix("https://auth.x.ai::")
            return lhsPreferred && !rhsPreferred
        }

        for (_, object) in ordered {
            guard let token = object["key"] as? String, !token.isEmpty else { continue }
            return Credentials(
                accessToken: token,
                expiresAt: (object["expires_at"] as? String).flatMap(parseISO8601)
            )
        }
        return nil
    }

    private static func fetchCredits(accessToken: String) -> Result<Data, FetchFailure> {
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else {
            return .failure(.request)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaRail/0.9.1", forHTTPHeaderField: "User-Agent")
        return perform(request)
    }

    private static func fetchWebBilling(accessToken: String) -> Result<Data, FetchFailure> {
        guard let url = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig") else {
            return .failure(.request)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = Data([0, 0, 0, 0, 0])
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("https://grok.com", forHTTPHeaderField: "Origin")
        request.setValue("https://grok.com/?_s=usage", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.setValue("connect-es/2.1.1", forHTTPHeaderField: "x-user-agent")
        request.setValue("QuotaRail/0.9.1", forHTTPHeaderField: "User-Agent")
        return perform(request)
    }

    private static func perform(_ request: URLRequest) -> Result<Data, FetchFailure> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, FetchFailure> = .failure(.request)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 || http.statusCode == 403 {
                result = .failure(.authentication)
                return
            }
            guard http.statusCode == 200, let data else { return }
            result = .success(data)
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 12) == .timedOut {
            task.cancel()
            return .failure(.request)
        }
        return result
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
