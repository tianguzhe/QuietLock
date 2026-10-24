import Foundation

public enum LockPreset: Int, CaseIterable, Identifiable, Sendable {
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case never = 0

    public var id: Int { rawValue }
    public var index: Int { Self.allCases.firstIndex(of: self)! }
    public var label: String { self == .never ? "永不" : "\(rawValue) 分钟" }
    public var tickLabel: String { self == .never ? "∞" : String(rawValue) }
}

public enum PowerSource: String, CaseIterable, Sendable {
    case battery = "Battery Power"
    case adapter = "AC Power"
    case ups = "UPS Power"

    public var label: String {
        switch self {
        case .battery: return "电池"
        case .adapter: return "接电"
        case .ups: return "UPS"
        }
    }
}

public struct PowerProfile: Equatable, Sendable {
    public let source: PowerSource
    public let minutes: Int

    public init(source: PowerSource, minutes: Int) {
        self.source = source
        self.minutes = minutes
    }
}

public struct PowerSnapshot: Equatable, Sendable {
    public let profiles: [PowerProfile]

    public init(profiles: [PowerProfile]) {
        self.profiles = profiles
    }

    public var uniformMinutes: Int? {
        guard let first = profiles.first, profiles.allSatisfy({ $0.minutes == first.minutes }) else {
            return nil
        }
        return first.minutes
    }

    public var preset: LockPreset? { uniformMinutes.flatMap(LockPreset.init(rawValue:)) }

    public var detail: String {
        profiles.map { profile in
            "\(profile.source.label) \(profile.minutes == 0 ? "永不" : "\(profile.minutes) 分钟")"
        }.joined(separator: " · ")
    }
}

public enum PowerSettingsError: Error, LocalizedError, Equatable, Sendable {
    case invalidOutput
    case readFailed
    case authorizationCancelled
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidOutput: return "暂时无法识别系统的电源设置。"
        case .readFailed: return "无法读取系统设置，请重试。"
        case .authorizationCancelled: return "已取消授权。"
        case .writeFailed: return "未能完成修改，请重试并允许系统授权。"
        }
    }
}

public enum PowerSettingsParser {
    public static func parse(_ output: String) throws -> PowerSnapshot {
        var currentSource: PowerSource?
        var seenSources = Set<PowerSource>()
        var values: [PowerSource: Int] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasSuffix(":") {
                currentSource = PowerSource(rawValue: String(line.dropLast()))
                if let source = currentSource {
                    guard seenSources.insert(source).inserted else {
                        throw PowerSettingsError.invalidOutput
                    }
                }
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "displaysleep", let source = currentSource else { continue }
            guard fields.count == 2, let minutes = Int(fields[1]), minutes >= 0,
                  values[source] == nil else {
                throw PowerSettingsError.invalidOutput
            }
            values[source] = minutes
        }

        guard !values.isEmpty, values.count == seenSources.count else {
            throw PowerSettingsError.invalidOutput
        }
        return PowerSnapshot(profiles: PowerSource.allCases.compactMap { source in
            values[source].map { PowerProfile(source: source, minutes: $0) }
        })
    }
}
