import Darwin
import Foundation
import QuotaRailCore

struct CheckRunner {
    private(set) var passed = 0
    private(set) var failed = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
    }
}

func codexLine(primary: Double, secondary: Double? = nil, timestamp: String) -> String {
    let secondaryJSON = secondary.map {
        #","secondary":{"used_percent":\#($0),"resets_at":1788602400}"#
    } ?? ""
    return #"{"timestamp":"\#(timestamp)","payload":{"rate_limits":{"primary":{"used_percent":\#(primary),"resets_at":1787997600}\#(secondaryJSON),"plan_type":"pro"}}}"#
}

func cursorJWT(subject: String, expiration: TimeInterval) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["sub": subject, "exp": expiration])
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
}

func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuotaRailChecks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func setModifiedAt(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

if CommandLine.arguments.contains("--live-codex") {
    let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    if let snapshot = CodexRateLimitReader.latestSnapshot(in: sessionsDirectory) {
        let primary = Int((snapshot.primaryFraction * 100).rounded())
        let secondary = snapshot.secondaryFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "unavailable"
        print("LIVE_CODEX primary=\(primary)% secondary=\(secondary) plan=\(snapshot.planType ?? "unknown")")
        exit(0)
    }
    print("LIVE_CODEX unavailable")
    exit(2)
}

var runner = CheckRunner()

if let snapshot = CodexRateLimitReader.snapshot(fromJSONLine: codexLine(
    primary: 25,
    secondary: 52.5,
    timestamp: "2026-08-29T10:00:00.000Z"
)) {
    runner.expect(abs(snapshot.primaryFraction - 0.25) < 0.0001, "Codex primary percentage")
    runner.expect(abs((snapshot.secondaryFraction ?? -1) - 0.525) < 0.0001, "Codex secondary percentage")
    runner.expect(snapshot.planType == "pro", "Codex plan type")
    runner.expect(snapshot.observedAt != nil, "Codex event timestamp")
} else {
    runner.expect(false, "Codex valid line parses")
}

do {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let valid = directory.appendingPathComponent("rollout-valid.jsonl")
    let noise = directory.appendingPathComponent("other-newer.jsonl")
    try codexLine(primary: 41, timestamp: "2026-08-29T10:00:00Z")
        .write(to: valid, atomically: true, encoding: .utf8)
    try "{\"payload\":{}}".write(to: noise, atomically: true, encoding: .utf8)
    try setModifiedAt(Date(timeIntervalSince1970: 100), for: valid)
    try setModifiedAt(Date(timeIntervalSince1970: 200), for: noise)

    let snapshot = CodexRateLimitReader.latestSnapshot(
        in: directory,
        now: Date(timeIntervalSince1970: 1_787_997_900)
    )
    runner.expect(abs((snapshot?.primaryFraction ?? -1) - 0.41) < 0.0001, "Codex ignores non-rollout JSONL")
} catch {
    runner.expect(false, "Codex non-rollout fixture: \(error)")
}

do {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let valid = directory.appendingPathComponent("rollout-valid.jsonl")
    let invalid = directory.appendingPathComponent("rollout-newest.jsonl")
    try codexLine(primary: 63, timestamp: "2026-08-29T09:00:00Z")
        .write(to: valid, atomically: true, encoding: .utf8)
    try "{\"timestamp\":\"2026-08-29T11:00:00Z\",\"payload\":{}}"
        .write(to: invalid, atomically: true, encoding: .utf8)
    try setModifiedAt(Date(timeIntervalSince1970: 100), for: valid)
    try setModifiedAt(Date(timeIntervalSince1970: 200), for: invalid)

    let snapshot = CodexRateLimitReader.latestSnapshot(
        in: directory,
        now: Date(timeIntervalSince1970: 1_787_994_300)
    )
    runner.expect(abs((snapshot?.primaryFraction ?? -1) - 0.63) < 0.0001, "Codex falls back from invalid newest rollout")
} catch {
    runner.expect(false, "Codex fallback fixture: \(error)")
}

do {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let olderEvent = directory.appendingPathComponent("rollout-newer-mtime.jsonl")
    let newerEvent = directory.appendingPathComponent("rollout-older-mtime.jsonl")
    try codexLine(primary: 18, timestamp: "2026-08-29T08:00:00Z")
        .write(to: olderEvent, atomically: true, encoding: .utf8)
    try codexLine(primary: 77, timestamp: "2026-08-29T12:00:00Z")
        .write(to: newerEvent, atomically: true, encoding: .utf8)
    try setModifiedAt(Date(timeIntervalSince1970: 300), for: olderEvent)
    try setModifiedAt(Date(timeIntervalSince1970: 200), for: newerEvent)

    let snapshot = CodexRateLimitReader.latestSnapshot(
        in: directory,
        now: Date(timeIntervalSince1970: 1_788_005_100)
    )
    runner.expect(abs((snapshot?.primaryFraction ?? -1) - 0.77) < 0.0001, "Codex chooses latest observed event")
} catch {
    runner.expect(false, "Codex event ordering fixture: \(error)")
}

do {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let stale = directory.appendingPathComponent("rollout-stale.jsonl")
    try codexLine(primary: 64, timestamp: "2000-01-01T00:00:00Z")
        .write(to: stale, atomically: true, encoding: .utf8)

    runner.expect(
        CodexRateLimitReader.latestSnapshot(in: directory) == nil,
        "Codex stale rate-limit event is unavailable"
    )
} catch {
    runner.expect(false, "Codex stale fixture: \(error)")
}

let claudeData = #"{"five_hour":{"utilization":42,"resets_at":"2026-08-29T13:00:00Z"},"seven_day":{"utilization":57.5,"resets_at":"2026-09-02T10:00:00.000Z"}}"#.data(using: .utf8)!
if let snapshot = ClaudeUsagePayloadParser.parse(data: claudeData) {
    runner.expect(abs(snapshot.sessionFraction - 0.42) < 0.0001, "Claude session percentage")
    runner.expect(abs((snapshot.weeklyFraction ?? -1) - 0.575) < 0.0001, "Claude weekly percentage")
    runner.expect(snapshot.sessionResetsAt != nil, "Claude reset timestamp")
} else {
    runner.expect(false, "Claude valid payload parses")
}

let claudeSessionOnly = #"{"five_hour":{"utilization":12,"resets_at":"2026-08-29T13:00:00Z"}}"#.data(using: .utf8)!
let sessionOnlySnapshot = ClaudeUsagePayloadParser.parse(data: claudeSessionOnly)
runner.expect(sessionOnlySnapshot?.weeklyFraction == nil, "Claude missing weekly remains unavailable")

let invalidClaude = #"{"seven_day":{"utilization":22}}"#.data(using: .utf8)!
runner.expect(ClaudeUsagePayloadParser.parse(data: invalidClaude) == nil, "Claude missing session is rejected")

let dockCenter = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: 55)
runner.expect(abs(dockCenter.scale - 1.5) < 0.0001, "Dock hovered item reaches selected B scale")
runner.expect(abs(dockCenter.horizontalOffset + 26) < 0.0001, "Dock hovered item lifts away from screen edge")
runner.expect(abs(dockCenter.verticalOffset) < 0.0001, "Dock hovered item stays centered vertically")

let dockNeighbor = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: 133)
runner.expect(dockNeighbor.scale > 1.22 && dockNeighbor.scale < 1.25, "Dock adjacent item joins magnification wave")
runner.expect(dockNeighbor.verticalOffset > 4 && dockNeighbor.verticalOffset < 4.6, "Dock adjacent item moves away from pointer")

let dockFar = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: 211)
runner.expect(dockFar.scale < 1.03, "Dock distant item remains nearly stable")
let dockCursorFar = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: 289)
runner.expect(dockCursorFar.scale < 1.001, "Dock fourth item remains stable at opposite edge")

let dockUpperNeighbor = DockMagnificationCurve.transform(pointerY: 133, itemCenterY: 55)
runner.expect(abs(dockUpperNeighbor.scale - dockNeighbor.scale) < 0.0001, "Dock curve is symmetric")
runner.expect(abs(dockUpperNeighbor.verticalOffset + dockNeighbor.verticalOffset) < 0.0001, "Dock wave pushes neighbors apart")

let dockReducedMotion = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: 55, reduceMotion: true)
runner.expect(dockReducedMotion.scale > 1 && dockReducedMotion.scale <= 1.08, "Dock honors Reduce Motion")

let customDockConfiguration = DockMagnificationConfiguration(
    idleScale: 0.60,
    hoverMaxScale: 1.80,
    trackScale: 1.20
)
let customDockCenter = DockMagnificationCurve.transform(
    pointerY: 55,
    itemCenterY: 55,
    configuration: customDockConfiguration
)
runner.expect(abs(customDockCenter.scale - 1.80) < 0.0001, "Dock custom hover scale reaches slider maximum")
let customDockFar = DockMagnificationCurve.transform(
    pointerY: 55,
    itemCenterY: 400,
    configuration: customDockConfiguration
)
runner.expect(abs(customDockFar.scale - 0.60) < 0.001, "Dock custom idle scale controls distant item")

var dockSweepFinite = true
var dockSweepMaximumScaleDelta = 0.0
var dockSweepMaximumVerticalDelta = 0.0
for center in [55.0, 133.0, 211.0, 289.0] {
    var previous = DockMagnificationCurve.transform(pointerY: 55, itemCenterY: center)
    for pointerY in stride(from: 59.0, through: 289.0, by: 4.0) {
        let current = DockMagnificationCurve.transform(pointerY: pointerY, itemCenterY: center)
        dockSweepFinite = dockSweepFinite
            && current.scale.isFinite
            && current.horizontalOffset.isFinite
            && current.verticalOffset.isFinite
        dockSweepMaximumScaleDelta = max(
            dockSweepMaximumScaleDelta,
            abs(current.scale - previous.scale)
        )
        dockSweepMaximumVerticalDelta = max(
            dockSweepMaximumVerticalDelta,
            abs(current.verticalOffset - previous.verticalOffset)
        )
        previous = current
    }
}
runner.expect(dockSweepFinite, "Dock continuous sweep remains finite")
runner.expect(dockSweepMaximumScaleDelta < 0.04, "Dock scale changes continuously while sliding")
runner.expect(dockSweepMaximumVerticalDelta < 1.2, "Dock vertical wave has no center-point jump")

let cursorUsageData = #"{"billingCycleStart":"2026-08-15T00:00:00Z","billingCycleEnd":"2026-09-15T00:00:00Z","membershipType":"pro","individualUsage":{"plan":{"used":725,"limit":2000,"totalPercentUsed":36.25,"autoPercentUsed":20.5,"apiPercentUsed":52},"onDemand":{"enabled":true,"used":250,"limit":1000}}}"#.data(using: .utf8)!
if let snapshot = CursorUsagePayloadParser.parse(data: cursorUsageData) {
    runner.expect(abs(snapshot.totalFraction - 0.3625) < 0.0001, "Cursor total monthly percentage")
    runner.expect(abs((snapshot.cursorModelsFraction ?? -1) - 0.205) < 0.0001, "Cursor models pool percentage")
    runner.expect(abs((snapshot.otherModelsFraction ?? -1) - 0.52) < 0.0001, "Cursor other models pool percentage")
    runner.expect(snapshot.resetsAt != nil, "Cursor billing reset timestamp")
    runner.expect(snapshot.membershipType == "pro", "Cursor membership type")
    runner.expect(abs((snapshot.onDemandUsedUSD ?? -1) - 2.5) < 0.0001, "Cursor on-demand dollars")
} else {
    runner.expect(false, "Cursor usage summary parses")
}

let cursorRatioData = #"{"billingCycleEnd":"2026-09-15T00:00:00Z","individualUsage":{"plan":{"used":500,"limit":2000}}}"#.data(using: .utf8)!
runner.expect(
    abs((CursorUsagePayloadParser.parse(data: cursorRatioData)?.totalFraction ?? -1) - 0.25) < 0.0001,
    "Cursor falls back to used/limit ratio"
)

let cursorOverallData = #"{"billingCycleEnd":"2026-09-15T00:00:00Z","individualUsage":{"overall":{"used":3000,"limit":10000}}}"#.data(using: .utf8)!
runner.expect(
    abs((CursorUsagePayloadParser.parse(data: cursorOverallData)?.totalFraction ?? -1) - 0.30) < 0.0001,
    "Cursor team member personal cap fallback"
)

let cursorExplicitZero = #"{"billingCycleEnd":"2026-09-15T00:00:00Z","individualUsage":{"plan":{"totalPercentUsed":0}}}"#.data(using: .utf8)!
runner.expect(CursorUsagePayloadParser.parse(data: cursorExplicitZero)?.totalFraction == 0, "Cursor explicit zero remains zero")

let cursorSplitPoolsWithoutTotal = #"{"individualUsage":{"plan":{"autoPercentUsed":20,"apiPercentUsed":80}}}"#.data(using: .utf8)!
runner.expect(
    CursorUsagePayloadParser.parse(data: cursorSplitPoolsWithoutTotal) == nil,
    "Cursor split pools without an official total remain unavailable"
)

let cursorSinglePoolWithoutTotal = #"{"individualUsage":{"plan":{"autoPercentUsed":20}}}"#.data(using: .utf8)!
runner.expect(
    CursorUsagePayloadParser.parse(data: cursorSinglePoolWithoutTotal) == nil,
    "Cursor single pool without an official total remains unavailable"
)

let cursorMissingUsage = #"{"billingCycleEnd":"2026-09-15T00:00:00Z"}"#.data(using: .utf8)!
runner.expect(CursorUsagePayloadParser.parse(data: cursorMissingUsage) == nil, "Cursor missing usage is not fabricated")

let cursorGrokBotData = #"{"currentPeriodStart":"2026-08-27T00:00:00Z","nextResetTimestampUtc":"2026-09-03T00:00:00Z","usagePercent":42.5,"hasAvailableUsage":true,"hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
let cursorMonthlyOnly = CursorUsagePayloadParser.parse(data: cursorUsageData)
let cursorGrokOnly = CursorGrokBotPayloadParser.parse(data: cursorGrokBotData)
runner.expect(
    CursorUsageAvailability.hasDisplayableUsage(monthly: cursorMonthlyOnly, grokBot: nil),
    "Cursor monthly usage can stand alone"
)
runner.expect(
    CursorUsageAvailability.hasDisplayableUsage(monthly: nil, grokBot: cursorGrokOnly),
    "Cursor Grok Bot usage can stand alone"
)
runner.expect(
    !CursorUsageAvailability.hasDisplayableUsage(monthly: nil, grokBot: nil),
    "Cursor requires at least one trustworthy usage source"
)
if let snapshot = CursorGrokBotPayloadParser.parse(data: cursorGrokBotData) {
    runner.expect(abs(snapshot.usedFraction - 0.425) < 0.0001, "Cursor Grok Bot weekly percentage")
    runner.expect(snapshot.resetsAt != nil, "Cursor Grok Bot reset timestamp")
} else {
    runner.expect(false, "Cursor Grok Bot payload parses")
}

let cursorGrokBotExhausted = #"{"nextResetTimestampUtc":"2026-09-03T00:00:00Z","usagePercent":100,"hasAvailableUsage":false,"hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
runner.expect(
    CursorGrokBotPayloadParser.parse(data: cursorGrokBotExhausted)?.usedFraction == 1,
    "Cursor Grok Bot exhausted allowance remains visible"
)

let cursorGrokBotNoAllowance = #"{"usagePercent":0,"hasAvailableUsage":false,"hasNonZeroIncludedLimit":false}"#.data(using: .utf8)!
runner.expect(CursorGrokBotPayloadParser.parse(data: cursorGrokBotNoAllowance) == nil, "Cursor account without Grok Bot allowance stays unavailable")

let cursorGrokBotMissingPercent = #"{"hasNonZeroIncludedLimit":true}"#.data(using: .utf8)!
runner.expect(CursorGrokBotPayloadParser.parse(data: cursorGrokBotMissingPercent) == nil, "Cursor Grok Bot missing percentage is rejected")

let cursorTokenNow = Date(timeIntervalSince1970: 1_000)
let validCursorToken = cursorJWT(subject: "auth0|user-123", expiration: 2_000)
runner.expect(
    CursorAppSessionToken.cookieHeader(accessToken: validCursorToken, now: cursorTokenNow)
        == "WorkosCursorSessionToken=user-123%3A%3A\(validCursorToken)",
    "Cursor local token derives scoped session cookie"
)
runner.expect(
    CursorAppSessionToken.cookieHeader(
        accessToken: cursorJWT(subject: "auth0|user-123", expiration: 1_050),
        now: cursorTokenNow
    ) == nil,
    "Cursor nearly expired token is rejected"
)
runner.expect(
    CursorAppSessionToken.cookieHeader(
        accessToken: cursorJWT(subject: "auth0|bad/user", expiration: 2_000),
        now: cursorTokenNow
    ) == nil,
    "Cursor invalid user ID is rejected"
)

let preferencesSuite = "QuotaRailChecks.\(UUID().uuidString)"
let preferencesDefaults = UserDefaults(suiteName: preferencesSuite)!
preferencesDefaults.removePersistentDomain(forName: preferencesSuite)
do {
    let preferences = RailPreferences(defaults: preferencesDefaults)
    runner.expect(preferences.trackScale == 1, "Preferences default background scale")
    runner.expect(preferences.iconScale == 1, "Preferences default icon scale")
    runner.expect(preferences.idleIconScale == 1, "Preferences default idle scale")
    runner.expect(preferences.hoverMaxScale == 1.5, "Preferences default hover scale")
    runner.expect(preferences.visibleProviderIDs.count == 4, "Preferences show all providers by default")

    preferences.trackScale = 2
    preferences.iconScale = 0.2
    preferences.idleIconScale = 0.95
    preferences.hoverMaxScale = 0.8
    preferences.alwaysVisible = true
    runner.expect(preferences.trackScale == 1.35, "Preferences clamp background scale")
    runner.expect(preferences.iconScale == 0.70, "Preferences clamp icon scale")
    runner.expect(preferences.hoverMaxScale >= preferences.idleIconScale + 0.05, "Preferences keep hover larger than idle")

    preferences.setProviderVisible("Claude", false)
    preferences.setProviderVisible("Grok", false)
    preferences.setProviderVisible("Cursor", false)
    preferences.setProviderVisible("Codex", false)
    runner.expect(preferences.visibleProviderIDs == ["Codex"], "Preferences refuse an empty provider set")

    let layout = RailLayout(trackScale: preferences.trackScale, providerCount: 1)
    runner.expect(layout.railWidth > 58, "Rail layout background slider changes width")
    runner.expect(layout.railHeight > 110, "Rail layout includes visible provider count")

    let compactLayout = RailLayout(trackScale: 0.75, providerCount: 3)
    runner.expect(
        compactLayout.interactiveWidth == compactLayout.railWidth,
        "Rail hover hit width matches the resting panel"
    )
    runner.expect(
        compactLayout.glassBackgroundWidth > compactLayout.interactiveWidth,
        "Rail glass may render beyond the fixed hover hit strip"
    )
    runner.expect(
        compactLayout.sensorWidth == compactLayout.glassBackgroundWidth,
        "Rail sensor window reserves the full liquid glass width"
    )

    let reloaded = RailPreferences(defaults: preferencesDefaults)
    runner.expect(reloaded.trackScale == preferences.trackScale, "Preferences persist background scale")
    runner.expect(reloaded.iconScale == preferences.iconScale, "Preferences persist icon scale")
    runner.expect(reloaded.alwaysVisible, "Preferences persist always-visible mode")
    runner.expect(reloaded.visibleProviderIDs == ["Codex"], "Preferences persist provider selection")
}
preferencesDefaults.removePersistentDomain(forName: preferencesSuite)

let grokCredits = #"{"config":{"creditUsagePercent":37.5,"currentPeriod":{"end":"2026-09-03T16:46:19Z"}}}"#.data(using: .utf8)!
if let snapshot = GrokUsagePayloadParser.parseCreditsJSON(data: grokCredits) {
    runner.expect(abs((snapshot.usedFraction ?? -1) - 0.375) < 0.0001, "Grok credits percentage")
    runner.expect(snapshot.resetsAt != nil, "Grok credits reset timestamp")
} else {
    runner.expect(false, "Grok credits payload parses")
}

let grokPeriodOnly = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-03T16:46:19Z"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0}}}"#.data(using: .utf8)!
let grokPeriodCandidate = GrokUsagePayloadParser.parseCreditsJSON(data: grokPeriodOnly)
runner.expect(grokPeriodCandidate?.usedFraction == nil, "Grok missing percentage remains unknown before fallback")
runner.expect(grokPeriodCandidate?.resetsAt != nil, "Grok period-only payload retains reset")

let grokPercentPayload = Data([0x0a, 0x05, 0x0d, 0x00, 0x00, 0x28, 0x42])
var grokPercentFrame = Data([0x00, 0x00, 0x00, 0x00, UInt8(grokPercentPayload.count)])
grokPercentFrame.append(grokPercentPayload)
let okTrailer = Data("grpc-status:0\r\n".utf8)
grokPercentFrame.append(contentsOf: [0x80, 0x00, 0x00, 0x00, UInt8(okTrailer.count)])
grokPercentFrame.append(okTrailer)
let grokGRPCPercent = GrokUsagePayloadParser.parseGRPCWeb(data: grokPercentFrame)
runner.expect(abs((grokGRPCPercent?.usedFraction ?? -1) - 0.42) < 0.0001, "Grok gRPC percentage")

let grokFrameWithoutTrailer = Data(grokPercentFrame.prefix(grokPercentPayload.count + 5))
runner.expect(
    GrokUsagePayloadParser.parseGRPCWeb(data: grokFrameWithoutTrailer) == nil,
    "Grok gRPC response without a status trailer is rejected"
)

let grokNoUsageBytes: [UInt8] = [
    0x00, 0x00, 0x00, 0x00, 0x48, 0x0a, 0x46, 0x12, 0x00, 0x1a, 0x00, 0x22,
    0x0c, 0x08, 0xdb, 0xd3, 0xc1, 0xd4, 0x06, 0x10, 0xb8, 0xe3, 0xe3, 0x93,
    0x03, 0x2a, 0x0c, 0x08, 0xdb, 0xc8, 0xe6, 0xd4, 0x06, 0x10, 0xb8, 0xe3,
    0xe3, 0x93, 0x03, 0x42, 0x1e, 0x08, 0x02, 0x12, 0x0c, 0x08, 0xdb, 0xd3,
    0xc1, 0xd4, 0x06, 0x10, 0xb8, 0xe3, 0xe3, 0x93, 0x03, 0x1a, 0x0c, 0x08,
    0xdb, 0xc8, 0xe6, 0xd4, 0x06, 0x10, 0xb8, 0xe3, 0xe3, 0x93, 0x03, 0x58,
    0x01, 0x62, 0x00, 0x68, 0x01, 0x80, 0x00, 0x00, 0x00, 0x0f, 0x67, 0x72,
    0x70, 0x63, 0x2d, 0x73, 0x74, 0x61, 0x74, 0x75, 0x73, 0x3a, 0x30, 0x0d,
    0x0a,
]
let grokNoUsage = GrokUsagePayloadParser.parseGRPCWeb(
    data: Data(grokNoUsageBytes),
    now: Date(timeIntervalSince1970: 1_700_000_000)
)
runner.expect(grokNoUsage?.usedFraction == 0, "Grok omitted proto percentage means no usage yet")
runner.expect(grokNoUsage?.resetsAt != nil, "Grok gRPC reset timestamp")

var rejectedFrame = grokPercentFrame.prefix(grokPercentFrame.count - okTrailer.count - 5)
let rejectedTrailer = Data("grpc-status:16\r\n".utf8)
rejectedFrame.append(contentsOf: [0x80, 0x00, 0x00, 0x00, UInt8(rejectedTrailer.count)])
rejectedFrame.append(rejectedTrailer)
runner.expect(
    GrokUsagePayloadParser.parseGRPCWeb(data: Data(rejectedFrame)) == nil,
    "Grok gRPC authentication failure is rejected"
)

let now = Date(timeIntervalSince1970: 1_000)
runner.expect(
    UsageFormatting.resetLabel(until: now.addingTimeInterval(3_900), now: now) == "1h 5m",
    "Reset label hours and minutes"
)
runner.expect(
    UsageFormatting.resetLabel(until: now.addingTimeInterval(90_000), now: now) == "1d 1h",
    "Reset label days and hours"
)

print("RESULT \(runner.passed) passed, \(runner.failed) failed")
if runner.failed > 0 { exit(1) }
