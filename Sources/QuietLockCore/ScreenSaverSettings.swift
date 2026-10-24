import Combine
import Foundation

public struct ScreenSaverSnapshot: Equatable, Sendable {
    public let idleSeconds: Int
    public let isManaged: Bool
    public var isEnabled: Bool { idleSeconds > 0 }

    public init(idleSeconds: Int, isManaged: Bool = false) {
        self.idleSeconds = idleSeconds
        self.isManaged = isManaged
    }

    public var detail: String {
        guard isEnabled else { return localized("Idle screen saver is off", "已关闭闲置自动屏保") }
        if idleSeconds % 60 == 0 {
            return localized("Starts after \(idleSeconds / 60) min idle", "闲置 \(idleSeconds / 60) 分钟后开始")
        }
        return localized("Starts after \(idleSeconds) s idle", "闲置 \(idleSeconds) 秒后开始")
    }
}

public enum ScreenSaverSettingsError: Error, Equatable {
    case readFailed, writeFailed, managed, verificationMismatch
}

public protocol ScreenSaverSettingsServing: Sendable {
    func read() async throws -> ScreenSaverSnapshot
    func setEnabled(_ enabled: Bool) async throws
}

protocol ScreenSaverPreferenceStoring: Sendable {
    func read() async throws -> ScreenSaverSnapshot
    func writeIdleSeconds(_ seconds: Int) async throws
    func savedIdleSeconds() async -> Int?
    func saveIdleSeconds(_ seconds: Int) async
}

enum ScreenSaverIdlePreference {
    /// Accepts integer numbers and numeric strings: the common
    /// `defaults -currentHost write com.apple.screensaver idleTime 0` (no `-int`) stores a string.
    /// Booleans, fractions, negatives and other types are rejected.
    static func seconds(from value: CFPropertyList) -> Int? {
        let text: String
        if CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber {
            text = number.stringValue
        } else if CFGetTypeID(value) == CFStringGetTypeID(), let string = value as? String {
            text = string.trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        guard let seconds = Int(text), seconds >= 0 else { return nil }
        return seconds
    }
}

/// idleTime is a per-user, per-host setting. A missing value uses macOS's
/// 20-minute default; writing zero disables only the automatic screen saver.
private actor SystemScreenSaverPreferenceStore: ScreenSaverPreferenceStoring {
    private let domain = "com.apple.screensaver" as CFString
    private let idleKey = "idleTime" as CFString
    private let restoreKey = "screenSaverPreviousIdleSeconds"

    func read() throws -> ScreenSaverSnapshot {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw ScreenSaverSettingsError.readFailed
        }
        let value = CFPreferencesCopyValue(idleKey, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            ?? CFPreferencesCopyAppValue(idleKey, domain)
        var seconds = 20 * 60
        if let value {
            guard let parsed = ScreenSaverIdlePreference.seconds(from: value) else {
                throw ScreenSaverSettingsError.readFailed
            }
            seconds = parsed
        }
        return ScreenSaverSnapshot(idleSeconds: seconds,
            isManaged: CFPreferencesAppValueIsForced(idleKey, domain))
    }

    func writeIdleSeconds(_ seconds: Int) throws {
        guard seconds >= 0 else { throw ScreenSaverSettingsError.writeFailed }
        guard !CFPreferencesAppValueIsForced(idleKey, domain) else { throw ScreenSaverSettingsError.managed }
        CFPreferencesSetValue(idleKey, NSNumber(value: seconds), domain,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw ScreenSaverSettingsError.writeFailed
        }
    }

    func savedIdleSeconds() -> Int? {
        let value = UserDefaults.standard.integer(forKey: restoreKey)
        return value > 0 ? value : nil
    }

    func saveIdleSeconds(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: restoreKey)
    }
}

public actor SystemScreenSaverSettingsService: ScreenSaverSettingsServing {
    private let store: any ScreenSaverPreferenceStoring

    public init() { store = SystemScreenSaverPreferenceStore() }
    init(store: any ScreenSaverPreferenceStoring) { self.store = store }

    public func read() async throws -> ScreenSaverSnapshot { try await store.read() }

    public func setEnabled(_ enabled: Bool) async throws {
        let current = try await store.read()
        guard !current.isManaged else { throw ScreenSaverSettingsError.managed }
        guard enabled != current.isEnabled else { return }
        let target: Int
        if enabled {
            let saved = await store.savedIdleSeconds()
            target = saved.flatMap { $0 > 0 ? $0 : nil } ?? 20 * 60
        } else {
            // Save before disabling so a later app launch can restore the exact delay.
            await store.saveIdleSeconds(current.idleSeconds)
            target = 0
        }
        try await store.writeIdleSeconds(target)
        guard try await store.read().idleSeconds == target else {
            throw ScreenSaverSettingsError.verificationMismatch
        }
    }
}

@MainActor
public final class ScreenSaverSettingsModel: ObservableObject {
    @Published public private(set) var snapshot: ScreenSaverSnapshot?
    @Published public private(set) var isCurrent = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isApplying = false
    @Published public private(set) var feedback: SettingsFeedback?
    private let service: any ScreenSaverSettingsServing
    private var revision = 0

    public init(service: any ScreenSaverSettingsServing = SystemScreenSaverSettingsService()) {
        self.service = service
    }

    public var canAdjust: Bool { isCurrent && !isApplying && snapshot?.isManaged == false }

    public func refresh() async {
        guard !isApplying else { return }
        revision += 1
        let request = revision
        isRefreshing = true
        do {
            let actual = try await service.read()
            guard revision == request else { return }
            let changed = snapshot != nil && snapshot != actual
            let wasCurrent = isCurrent
            snapshot = actual
            isCurrent = true
            if changed || !wasCurrent { feedback = nil }
        } catch {
            guard revision == request else { return }
            isCurrent = false
            feedback = SettingsFeedback(kind: .error, message: localized("Couldn't read screen saver settings. Try again.", "无法读取屏保设置，请重试。"))
        }
        isRefreshing = false
    }

    public func refreshInBackground() async {
        guard !isRefreshing else { return }
        await refresh()
    }

    public func setEnabled(_ enabled: Bool) async {
        guard canAdjust, snapshot?.isEnabled != enabled else { return }
        revision += 1
        isRefreshing = false
        isApplying = true
        feedback = nil
        var writeError: Error?
        do { try await service.setEnabled(enabled) } catch { writeError = error }
        do {
            snapshot = try await service.read()
            isCurrent = true
        } catch { isCurrent = false }
        isApplying = false
        if !isCurrent {
            feedback = SettingsFeedback(kind: .error, message: localized("Couldn't confirm screen saver settings. Reload to check.", "无法确认屏保设置，请重新读取。"))
        } else if writeError != nil || snapshot?.isEnabled != enabled {
            feedback = SettingsFeedback(kind: .error, message: localized("The screen saver change didn't finish. Showing the actual state.", "屏保修改未完成，已显示实际状态。"))
        } else {
            feedback = SettingsFeedback(kind: .success,
                message: enabled ? localized("Screen saver turned back on.", "已恢复自动屏保。")
                    : localized("Screen saver turned off.", "已关闭自动屏保。"))
        }
    }
}
