import Foundation
import QuotaRailCore
import SQLite3

/// Reads Cursor.app's own local login database in read-only mode, then sends
/// the derived session cookie only to cursor.com. QuotaRail never imports
/// browser cookies, refreshes the token, or persists it anywhere else.
enum CursorUsageEngine {
    struct Snapshot {
        let grokBotWeeklyPercent: Double?
        let grokBotWeeklyResetsLabel: String?
        let monthlyPercent: Double?
        let monthlyResetsLabel: String?
        let cursorModelsPercent: Double?
        let otherModelsPercent: Double?
        let planLabel: String?
    }

    struct Status {
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
                return "未找到 Cursor 登录状态。请先安装并登录 Cursor。"
            case .credentialsExpired:
                return "Cursor 登录已过期。请打开 Cursor 重新登录。"
            case .requestFailed:
                return "Cursor 用量接口暂时不可用。"
            case .invalidResponse:
                return "Cursor 返回了无法识别的用量数据。"
            }
        }
    }

    private enum FetchFailure: Error {
        case authentication
        case request
    }

    private struct SQLiteFailure: Error {
        let code: Int32
    }

    static func computeSnapshot() -> Result<Snapshot, Failure> {
        let token: String
        do {
            guard let loaded = try loadAccessToken() else {
                return .failure(.credentialsUnavailable)
            }
            token = loaded
        } catch {
            return .failure(.credentialsUnavailable)
        }

        let cookieHeader: String
        switch makeCookieHeader(accessToken: token) {
        case .success(let header):
            cookieHeader = header
        case .failure(let failure):
            return .failure(failure)
        }

        let monthlyResult = fetchUsage(cookieHeader: cookieHeader)
        let grokBotResult = fetchGrokBotUsage(cookieHeader: cookieHeader)
        let monthlyUsage: CursorUsageSnapshot?
        if case .success(let data) = monthlyResult {
            monthlyUsage = CursorUsagePayloadParser.parse(data: data)
        } else {
            monthlyUsage = nil
        }
        let grokBotUsage: CursorGrokBotUsageSnapshot?
        if case .success(let data) = grokBotResult {
            grokBotUsage = CursorGrokBotPayloadParser.parse(data: data)
        } else {
            grokBotUsage = nil
        }

        if CursorUsageAvailability.hasDisplayableUsage(monthly: monthlyUsage, grokBot: grokBotUsage) {
            return .success(Snapshot(
                grokBotWeeklyPercent: grokBotUsage?.usedFraction,
                grokBotWeeklyResetsLabel: grokBotUsage.flatMap { UsageFormatting.resetLabel(until: $0.resetsAt) },
                monthlyPercent: monthlyUsage?.totalFraction,
                monthlyResetsLabel: monthlyUsage.flatMap { UsageFormatting.resetLabel(until: $0.resetsAt) },
                cursorModelsPercent: monthlyUsage?.cursorModelsFraction,
                otherModelsPercent: monthlyUsage?.otherModelsFraction,
                planLabel: monthlyUsage.flatMap { planLabel($0.membershipType) }
            ))
        }

        let monthlyAuthenticatedFailure: Bool
        if case .failure(.authentication) = monthlyResult {
            monthlyAuthenticatedFailure = true
        } else {
            monthlyAuthenticatedFailure = false
        }
        let grokBotAuthenticatedFailure: Bool
        if case .failure(.authentication) = grokBotResult {
            grokBotAuthenticatedFailure = true
        } else {
            grokBotAuthenticatedFailure = false
        }
        let monthlyReturnedResponse: Bool
        if case .success = monthlyResult {
            monthlyReturnedResponse = true
        } else {
            monthlyReturnedResponse = false
        }
        let grokBotReturnedResponse: Bool
        if case .success = grokBotResult {
            grokBotReturnedResponse = true
        } else {
            grokBotReturnedResponse = false
        }

        if monthlyAuthenticatedFailure && grokBotAuthenticatedFailure {
            return .failure(.credentialsExpired)
        }
        if monthlyReturnedResponse || grokBotReturnedResponse {
            return .failure(.invalidResponse)
        }
        if monthlyAuthenticatedFailure || grokBotAuthenticatedFailure {
            return .failure(.credentialsExpired)
        }
        return .failure(.requestFailed)
    }

    static func status() -> Status {
        Status(
            actionTitle: "打开 Cursor Usage",
            actionURL: URL(string: "https://cursor.com/dashboard/spending")!
        )
    }

    private static func loadAccessToken() throws -> String? {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        do {
            return try readDatabaseValue(path: dbPath, immutable: false)
        } catch let failure as SQLiteFailure {
            let sidecarsMissing = !FileManager.default.fileExists(atPath: dbPath + "-wal")
                && !FileManager.default.fileExists(atPath: dbPath + "-shm")
            guard failure.code == SQLITE_CANTOPEN, sidecarsMissing else { throw failure }
            return try readDatabaseValue(path: dbPath, immutable: true)
        }
    }

    private static func readDatabaseValue(path: String, immutable: Bool) throws -> String? {
        var db: OpaquePointer?
        let databaseURL = URL(fileURLWithPath: path, isDirectory: false).absoluteURL
        let filename = immutable ? "\(databaseURL.absoluteString)?immutable=1" : path
        let flags = immutable ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI : SQLITE_OPEN_READONLY
        let openResult = sqlite3_open_v2(filename, &db, flags, nil)
        guard openResult == SQLITE_OK else {
            let code = db.map(sqlite3_errcode) ?? openResult
            sqlite3_close(db)
            throw SQLiteFailure(code: code)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw SQLiteFailure(code: sqlite3_errcode(db))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, "cursorAuth/accessToken", -1, sqliteTransient)

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_DONE { return nil }
        guard stepResult == SQLITE_ROW else {
            throw SQLiteFailure(code: sqlite3_errcode(db))
        }

        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            guard let value = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: value)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16LittleEndian)
        default:
            return nil
        }
    }

    private static func makeCookieHeader(accessToken: String) -> Result<String, Failure> {
        guard let header = CursorAppSessionToken.cookieHeader(accessToken: accessToken) else {
            return .failure(.credentialsExpired)
        }
        return .success(header)
    }

    private static func fetchUsage(cookieHeader: String) -> Result<Data, FetchFailure> {
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
            return .failure(.request)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("QuotaRail/0.9.1", forHTTPHeaderField: "User-Agent")

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

    private static func fetchGrokBotUsage(cookieHeader: String) -> Result<Data, FetchFailure> {
        guard let url = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status") else {
            return .failure(.request)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("QuotaRail/0.9.1", forHTTPHeaderField: "User-Agent")

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
        if semaphore.wait(timeout: .now() + 7) == .timedOut {
            task.cancel()
            return .failure(.request)
        }
        return result
    }

    private static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
