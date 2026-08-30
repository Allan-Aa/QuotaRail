import Foundation

public struct GrokUsageCandidate: Equatable, Sendable {
    public let usedFraction: Double?
    public let resetsAt: Date?

    public init(usedFraction: Double?, resetsAt: Date?) {
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
    }
}

public enum GrokUsagePayloadParser {
    public static func parseCreditsJSON(data: Data) -> GrokUsageCandidate? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = root["config"] as? [String: Any]
        else { return nil }

        let resetsAt = ((config["currentPeriod"] as? [String: Any])?["end"] as? String)
            .flatMap(parseISO8601)
            ?? (config["billingPeriodEnd"] as? String).flatMap(parseISO8601)

        if let percent = number(config["creditUsagePercent"]), percent.isFinite {
            return GrokUsageCandidate(
                usedFraction: min(100, max(0, percent)) / 100,
                resetsAt: resetsAt
            )
        }

        if let capObject = config["onDemandCap"] as? [String: Any],
           let usedObject = config["onDemandUsed"] as? [String: Any],
           let cap = number(capObject["val"]), cap > 0,
           let used = number(usedObject["val"])
        {
            return GrokUsageCandidate(
                usedFraction: min(1, max(0, used / cap)),
                resetsAt: resetsAt
            )
        }

        guard resetsAt != nil else { return nil }
        return GrokUsageCandidate(usedFraction: nil, resetsAt: resetsAt)
    }

    public static func parseGRPCWeb(data: Data, now: Date = Date()) -> GrokUsageCandidate? {
        guard let frames = grpcWebFrames(data), !frames.payloads.isEmpty, frames.status == 0 else {
            return nil
        }

        var scan = ProtobufScan()
        for payload in frames.payloads {
            scan.merge(scanProtobuf(payload, path: [], depth: 0, order: 0).scan)
        }

        let percent = scan.fixed32Fields
            .filter { field in
                field.path.last == 1
                    && field.value.isFinite
                    && field.value >= 0
                    && field.value <= 100
            }
            .min { lhs, rhs in
                lhs.path.count == rhs.path.count
                    ? lhs.order < rhs.order
                    : lhs.path.count < rhs.path.count
            }
            .map { Double($0.value) / 100 }

        let resetFields = scan.varintFields.compactMap { field -> (path: [UInt64], date: Date)? in
            guard field.value >= 1_700_000_000, field.value <= 2_100_000_000 else { return nil }
            return (field.path, Date(timeIntervalSince1970: TimeInterval(field.value)))
        }
        let futureResets = resetFields.filter { $0.date > now }
        let resetsAt = futureResets
            .filter { $0.path == [1, 5, 1] }
            .map(\.date)
            .min()
            ?? futureResets.map(\.date).min()

        let hasUsagePeriod = scan.varintFields.contains { field in
            field.path.starts(with: [1, 6])
                || (field.path == [1, 8, 1] && (field.value == 1 || field.value == 2))
        }
        let noUsageYet = percent == nil
            && scan.fixed32Fields.isEmpty
            && resetsAt != nil
            && hasUsagePeriod

        guard let usedFraction = percent ?? (noUsageYet ? 0 : nil) else { return nil }
        return GrokUsageCandidate(usedFraction: usedFraction, resetsAt: resetsAt)
    }

    private static func grpcWebFrames(_ data: Data) -> (payloads: [Data], status: Int)? {
        let bytes = [UInt8](data)
        var payloads: [Data] = []
        var status: Int?
        var index = 0

        while index < bytes.count {
            guard index + 5 <= bytes.count else { return nil }
            let flags = bytes[index]
            let length = (Int(bytes[index + 1]) << 24)
                | (Int(bytes[index + 2]) << 16)
                | (Int(bytes[index + 3]) << 8)
                | Int(bytes[index + 4])
            let start = index + 5
            let end = start + length
            guard end <= bytes.count else { return nil }

            let body = Data(bytes[start..<end])
            if flags & 0x80 == 0 {
                payloads.append(body)
            } else if let text = String(data: body, encoding: .utf8) {
                for line in text.components(separatedBy: .newlines) {
                    let pieces = line.split(separator: ":", maxSplits: 1)
                    if pieces.count == 2,
                       pieces[0].trimmingCharacters(in: .whitespacesAndNewlines) == "grpc-status",
                       let parsed = Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    {
                        status = parsed
                    }
                }
            }
            index = end
        }

        guard let status else { return nil }
        return (payloads, status)
    }

    private struct ProtobufScan {
        struct Fixed32Field {
            let path: [UInt64]
            let value: Float
            let order: Int
        }

        struct VarintField {
            let path: [UInt64]
            let value: UInt64
        }

        var fixed32Fields: [Fixed32Field] = []
        var varintFields: [VarintField] = []

        mutating func merge(_ other: ProtobufScan) {
            fixed32Fields.append(contentsOf: other.fixed32Fields)
            varintFields.append(contentsOf: other.varintFields)
        }
    }

    private static func scanProtobuf(
        _ data: Data,
        path: [UInt64],
        depth: Int,
        order: Int
    ) -> (scan: ProtobufScan, order: Int) {
        let bytes = [UInt8](data)
        var scan = ProtobufScan()
        var index = 0
        var nextOrder = order

        while index < bytes.count {
            let fieldStart = index
            guard let key = readVarint(bytes, index: &index), key != 0 else {
                index = fieldStart + 1
                continue
            }
            let fieldPath = path + [key >> 3]

            switch key & 0x07 {
            case 0:
                if let value = readVarint(bytes, index: &index) {
                    scan.varintFields.append(.init(path: fieldPath, value: value))
                } else {
                    index = fieldStart + 1
                }
            case 1:
                guard index + 8 <= bytes.count else { return (scan, nextOrder) }
                index += 8
            case 2:
                guard let length = readVarint(bytes, index: &index),
                      length <= UInt64(bytes.count - index)
                else {
                    index = fieldStart + 1
                    continue
                }
                let end = index + Int(length)
                if depth < 4 {
                    let nested = scanProtobuf(
                        Data(bytes[index..<end]),
                        path: fieldPath,
                        depth: depth + 1,
                        order: nextOrder
                    )
                    scan.merge(nested.scan)
                    nextOrder = nested.order
                }
                index = end
            case 5:
                guard index + 4 <= bytes.count else { return (scan, nextOrder) }
                let bits = UInt32(bytes[index])
                    | (UInt32(bytes[index + 1]) << 8)
                    | (UInt32(bytes[index + 2]) << 16)
                    | (UInt32(bytes[index + 3]) << 24)
                scan.fixed32Fields.append(.init(
                    path: fieldPath,
                    value: Float(bitPattern: bits),
                    order: nextOrder
                ))
                nextOrder += 1
                index += 4
            default:
                index = fieldStart + 1
            }
        }

        return (scan, nextOrder)
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
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
