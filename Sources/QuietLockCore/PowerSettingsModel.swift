import Combine
import Foundation

public struct SettingsFeedback: Equatable, Sendable {
    public enum Kind: Sendable { case neutral, success, error }
    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

@MainActor
public final class PowerSettingsModel: ObservableObject {
    @Published public private(set) var snapshot: PowerSnapshot?
    @Published public private(set) var isSnapshotCurrent = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isApplying = false
    @Published public private(set) var isKeepingAwake = false
    @Published public private(set) var feedback: SettingsFeedback?

    private enum RetryAction: Equatable { case read, apply(LockPreset), protection }
    private let service: any PowerSettingsServing
    private let protection: any IdleSleepProtecting
    private var revision = 0
    private var retryAction: RetryAction?

    public init(service: any PowerSettingsServing = SystemPowerSettingsService(),
                protection: (any IdleSleepProtecting)? = nil) {
        self.service = service
        self.protection = protection ?? SystemIdleSleepProtection()
    }

    public var canAdjust: Bool { isSnapshotCurrent && !isApplying }
    public var canRetry: Bool { retryAction != nil && !isApplying && !isRefreshing }
    private var hasPendingWriteRetry: Bool {
        if case .apply = retryAction { return true }
        return false
    }

    public func refresh() async {
        await refresh(preservingFeedback: false)
    }

    public func refreshInBackground() async {
        guard !isRefreshing else { return }
        await refresh(preservingFeedback: true)
    }

    private func refresh(preservingFeedback: Bool) async {
        guard !isApplying else { return }
        revision += 1
        let requestRevision = revision
        isRefreshing = true
        do {
            let actual = try await service.read()
            guard revision == requestRevision else { return }
            let previous = snapshot
            snapshot = actual
            isSnapshotCurrent = true
            if previous != nil && previous != actual {
                if previous?.preset == .never {
                    feedback = SettingsFeedback(kind: .error, message: "系统熄屏时间已改变，“永不”已停止。可重试恢复。")
                    retryAction = .apply(.never)
                } else {
                    feedback = SettingsFeedback(kind: .neutral, message: "系统熄屏时间已改变，已同步实际设置。")
                    retryAction = nil
                }
            } else if retryAction == .read || (!preservingFeedback && !hasPendingWriteRetry) {
                // An unchanged value cannot resolve a pending write retry; opening the panel must not hide it.
                feedback = nil
                retryAction = nil
            }
            synchronizeProtection()
        } catch {
            guard revision == requestRevision else { return }
            isSnapshotCurrent = false
            feedback = SettingsFeedback(kind: .error, message: "无法读取当前设置，请重试。")
            retryAction = .read
        }
        isRefreshing = false
    }

    public func apply(_ preset: LockPreset) async {
        guard canAdjust else { return }
        guard snapshot?.uniformMinutes != preset.rawValue else {
            if preset == .never { synchronizeProtection() }
            return
        }
        revision += 1
        isRefreshing = false
        isApplying = true
        retryAction = nil
        feedback = SettingsFeedback(kind: .neutral, message: "请在系统弹窗中允许修改…")

        var writeError: Error?
        do { try await service.apply(preset) } catch { writeError = error }

        // Even a failed command could have changed one power profile. Always re-read reality.
        do {
            snapshot = try await service.read()
            isSnapshotCurrent = true
        } catch {
            isSnapshotCurrent = false
        }

        isApplying = false
        if !isSnapshotCurrent {
            feedback = SettingsFeedback(kind: .error, message: "暂时无法确认当前设置，请重新读取。")
            retryAction = .read
        } else if let error = writeError {
            if (error as? PowerSettingsError) == .authorizationCancelled {
                feedback = SettingsFeedback(kind: .neutral, message: "已取消授权，当前系统设置如下。")
                retryAction = nil
            } else if snapshot?.uniformMinutes == preset.rawValue {
                feedback = SettingsFeedback(kind: .neutral, message: "已同步，系统当前已是所选时间。")
                retryAction = nil
            } else {
                feedback = SettingsFeedback(kind: .error, message: "修改未完成，已显示实际设置。")
                retryAction = .apply(preset)
            }
        } else if snapshot?.uniformMinutes == preset.rawValue {
            feedback = SettingsFeedback(
                kind: .success,
                message: preset == .never ? "已设置为永不自动熄屏" : "已设置为闲置 \(preset.rawValue) 分钟后熄屏"
            )
        } else {
            feedback = SettingsFeedback(kind: .error, message: "系统未完整应用修改，请重试。")
            retryAction = .apply(preset)
        }
        if isSnapshotCurrent { synchronizeProtection() }
    }

    public func retry() async {
        guard canRetry, let action = retryAction else { return }
        switch action {
        case .read: await refresh()
        case .apply(let preset): await apply(preset)
        case .protection: await refresh()
        }
    }

    public func stopKeepingAwake() {
        protection.deactivate()
        isKeepingAwake = false
    }

    private func synchronizeProtection() {
        guard isSnapshotCurrent else { return }
        guard snapshot?.preset == .never else {
            stopKeepingAwake()
            return
        }
        do {
            try protection.activate()
            guard protection.isActive else { throw IdleSleepProtectionError.unavailable }
            isKeepingAwake = true
            if retryAction == .protection {
                feedback = SettingsFeedback(kind: .success, message: "保持唤醒已开启。")
                retryAction = nil
            }
        } catch {
            isKeepingAwake = false
            feedback = SettingsFeedback(kind: .error, message: "熄屏定时已关闭，但保持唤醒未开启，请重试。")
            retryAction = .protection
        }
    }
}
