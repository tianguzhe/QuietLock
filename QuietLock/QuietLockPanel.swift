import AppKit
import QuietLockCore
import SwiftUI

struct QuietLockPanel: View {
    static let size = NSSize(width: 344, height: 420)
    enum Page { case controls, help }

    @ObservedObject var model: PowerSettingsModel
    @ObservedObject var screenSaver: ScreenSaverSettingsModel
    @AppStorage("hasReadLockGuidance") private var hasReadLockGuidance = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var preview: LockPreset?
    @State private var submitted: LockPreset?
    @State private var page: Page

    init(model: PowerSettingsModel, screenSaver: ScreenSaverSettingsModel, initialPage: Page = .controls) {
        self.model = model
        self.screenSaver = screenSaver
        _page = State(initialValue: initialPage)
    }

    private var shownPreset: LockPreset? {
        preview ?? submitted ?? (model.isSnapshotCurrent ? model.snapshot?.preset : nil)
    }
    private var shownMinutes: Int? {
        shownPreset?.rawValue ?? (model.isSnapshotCurrent ? model.snapshot?.uniformMinutes : nil)
    }

    var body: some View {
        ZStack {
            if page == .controls { controls.transition(.opacity) }
            else { helpPage.transition(.opacity) }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(QuietLockStyle.primaryText(colorScheme))
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.15 : 0.9), .white.opacity(0.025)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
        .onDisappear { preview = nil }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 36)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            timeControl
                .padding(.horizontal, 16)

            ScreenSaverControls(model: screenSaver, isEnabled: !model.isApplying)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            statusLine
                .frame(height: 48)
                .padding(.horizontal, 16)

            Rectangle().fill(Color.primary.opacity(0.065)).frame(height: 0.5)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            BrandBadge().scaleEffect(0.9).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("QuietLock", "静锁")).font(.system(size: 13, weight: .semibold))
                Text(localized("DISPLAY SLEEP", "QUIETLOCK")).font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 4, height: 4)
                Text(model.isApplying ? localized("Authorizing", "待授权")
                     : !model.isSnapshotCurrent ? localized("Not synced", "未同步")
                     : model.isKeepingAwake ? localized("Awake", "保持唤醒") : localized("Synced", "已同步"))
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.primary.opacity(0.035), in: Capsule())
            .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            .accessibilityElement(children: .combine)

            Button {
                preview = nil
                page = .help
            } label: {
                Image(systemName: "info.circle").font(.system(size: 13))
                    .frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(ChromeButtonStyle())
            .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            .help(localized("Guide", "使用说明"))
            .accessibilityLabel(localized("Guide", "使用说明"))
        }
    }

    private var timeControl: some View {
        VStack(spacing: 8) {
            TimeDial(minutes: shownMinutes, preset: shownPreset, isPreviewing: preview != nil)
            PresetSlider(selection: shownPreset,
                isEnabled: model.canAdjust && !screenSaver.isApplying,
                onPreview: { preview = $0 }, onCommit: apply)
            HStack(spacing: 5) {
                Image(systemName: preview == nil ? "bolt.horizontal" : "hand.draw")
                    .font(.system(size: 9))
                Text(cardCaption)
                    .font(.system(size: 10))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            .frame(height: 12)
        }
        .padding(.horizontal, 15)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.74))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.6)
        }
    }

    private var cardCaption: String {
        if preview != nil { return localized("Release or press Return to apply", "松开或按回车，应用新时间") }
        if model.isApplying { return localized("Waiting for authorization…", "正在等待系统授权…") }
        if !model.isSnapshotCurrent {
            return model.isRefreshing ? localized("Reading system settings…", "正在读取系统设置…") : localized("Current setting unknown", "当前设置未知")
        }
        if model.snapshot?.uniformMinutes == nil { return localized("Power sources differ · pick a step to match", "电源时间未统一 · 选择档位即可统一") }
        if model.snapshot?.preset == nil { return localized("Custom value · pick a step to change", "系统自定义时间 · 选择档位即可修改") }
        return localized("Battery and AC · applied together", "电池与接电 · 统一设置")
    }

    private var statusColor: Color {
        if !model.isSnapshotCurrent || model.feedback?.kind == .error { return .orange }
        return QuietLockStyle.accent
    }

    private var screenSaverHasError: Bool { screenSaver.feedback?.kind == .error }
    private var showsGuidance: Bool {
        !hasReadLockGuidance && model.feedback == nil && !screenSaverHasError && shownMinutes != 0 &&
            model.isSnapshotCurrent && model.snapshot?.uniformMinutes != nil
    }

    private var statusLine: some View {
        HStack(alignment: .center, spacing: 8) {
            if model.isApplying || screenSaver.isApplying || (model.isRefreshing && !model.isSnapshotCurrent) {
                ProgressView().controlSize(.mini).frame(width: 14)
            } else {
                Image(systemName: statusSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusTint)
                    .frame(width: 14)
            }
            Text(statusText)
                .font(.system(size: 11))
                .lineSpacing(1)
                .lineLimit(2)
                .foregroundStyle(statusIsWarning ? QuietLockStyle.primaryText(colorScheme) : QuietLockStyle.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(statusText)
            if model.canRetry {
                Button(localized("Retry", "重试")) { Task { await model.retry() } }
                    .buttonStyle(CalloutActionStyle(tint: statusTint))
            } else if screenSaverHasError {
                Button(localized("Reload", "重读")) { Task { await screenSaver.refresh() } }
                    .buttonStyle(CalloutActionStyle(tint: statusTint))
                    .disabled(screenSaver.isApplying || model.isApplying)
            } else if screenSaverDefeatsNever && screenSaver.canAdjust && !model.isApplying {
                Button(localized("Turn Off", "关闭屏保")) { Task { await screenSaver.setEnabled(false) } }
                    .buttonStyle(CalloutActionStyle(tint: statusTint))
            } else if showsGuidance {
                Button { hasReadLockGuidance = true } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 20, height: 22)
                }
                .buttonStyle(ChromeButtonStyle())
                .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
                .accessibilityLabel(localized("Dismiss setup tip", "知道了，关闭首次提示"))
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .background(statusTint.opacity(statusIsWarning ? 0.13 : model.feedback?.kind == .success ? 0.09 : 0.05),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(statusTint.opacity(statusIsWarning ? 0.32 : 0.12), lineWidth: 0.6)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: statusIsWarning)
        .accessibilityElement(children: .contain)
    }

    private var screenSaverDefeatsNever: Bool {
        shownMinutes == 0 && screenSaver.isCurrent && screenSaver.snapshot?.isEnabled == true
    }

    private var statusIsWarning: Bool {
        model.feedback?.kind == .error || screenSaverHasError || screenSaverDefeatsNever
    }

    private var statusTint: Color { statusIsWarning ? .orange : QuietLockStyle.accent }

    private var statusSymbol: String {
        if statusIsWarning { return "exclamationmark.circle" }
        if model.feedback?.kind == .success { return "checkmark.circle.fill" }
        if shownMinutes == 0 { return "sun.max" }
        return "lock.shield"
    }

    private var statusText: String {
        if model.isApplying || model.feedback?.kind == .error, let feedback = model.feedback { return feedback.message }
        if screenSaverHasError, let feedback = screenSaver.feedback { return feedback.message }
        if screenSaver.isApplying { return localized("Updating the screen saver…", "正在更新自动屏保设置…") }
        if preview != nil { return localized("Previewing. Release or press Return to apply.", "拖动实时预览，松开或按回车后提交。") }
        if screenSaverDefeatsNever {
            return localized("The screen saver is on and can still lock your Mac.", "自动屏保仍开启，闲置后仍可能锁屏。")
        }
        if let feedback = model.feedback { return feedback.message }
        if shownMinutes == 0 {
            return model.isKeepingAwake
                ? localized("Keeping your Mac awake while QuietLock runs. You can still lock it manually.", "静锁运行时保持唤醒；仍可手动锁屏与合盖。")
                : localized("Idle display sleep is off. Password rules follow macOS.", "已关闭闲置熄屏定时，密码要求跟随系统。")
        }
        if let snapshot = model.snapshot, model.isSnapshotCurrent, snapshot.uniformMinutes == nil { return snapshot.detail }
        if showsGuidance {
            return localized("First run: in Lock Screen settings, set Require password to Immediately.", "首次使用：在锁屏设置中，将「需要密码」设为「立即」。")
        }
        return localized("Sets idle display sleep. Password rules follow macOS.", "调整的是闲置熄屏时间，密码要求跟随系统。")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button(action: openLockSettings) {
                Label(localized("Lock Screen", "锁屏设置"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).frame(height: 28)
            }
            .buttonStyle(ChromeButtonStyle())
            Spacer()
            Button {
                Task {
                    await model.refresh()
                    await screenSaver.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11)).frame(width: 28, height: 28)
            }
            .buttonStyle(ChromeButtonStyle())
            .help(localized("Reload system settings", "重新读取系统设置"))
            .accessibilityLabel(localized("Reload system settings", "重新读取系统设置"))
            .disabled(model.isApplying || screenSaver.isApplying)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11)).frame(width: 28, height: 28)
            }
            .buttonStyle(ChromeButtonStyle())
            .disabled(model.isApplying || screenSaver.isApplying)
            .help(localized("Quit QuietLock (settings stay, keep-awake ends)", "退出静锁（保留设置，结束保持唤醒）"))
            .accessibilityLabel(localized("Quit QuietLock", "退出静锁"))
        }
        .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    hasReadLockGuidance = true
                    page = .controls
                } label: {
                    Label(localized("Back", "返回"), systemImage: "chevron.left").font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).frame(height: 28)
                }
                .buttonStyle(ChromeButtonStyle()).foregroundStyle(QuietLockStyle.accent)
                Spacer()
                Text(localized("Guide", "使用说明")).font(.system(size: 13, weight: .semibold))
            }
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                helpSection(localized("Display sleep and locking", "熄屏与锁屏"), symbol: "lock.shield",
                    text: localized("QuietLock sets idle display sleep. To lock when the display sleeps, set Require password to Immediately in System Settings.",
                                    "静锁设置闲置熄屏时间。要熄屏后立即锁定，请在系统设置中将「需要密码」设为「立即」。"))
                helpSection(localized("Never and keep-awake", "永不与保持唤醒"), symbol: "sun.max",
                    text: localized("∞ keeps your Mac awake while QuietLock runs. Turn off the screen saver too so it can't lock. macOS still handles manual lock, the lid and low battery.",
                                    "选择 ∞ 后，静锁运行期间保持唤醒。要避免屏保触发锁屏，请同时关闭自动屏保。手动锁屏、合盖、低电量仍由系统处理。"))
                helpSection(localized("Screen saver and settings", "屏保与设置保留"), symbol: "sparkles.tv",
                    text: localized("Turning the screen saver on restores its delay, or 20 minutes. Quitting only ends keep-awake; settings stay.",
                                    "开启屏保恢复原等待时间，无记录时为 20 分钟。退出静锁只结束保持唤醒，已写入的设置仍保留。"))
            }

            Spacer(minLength: 10)

            HStack(spacing: 5) {
                keycap("←")
                keycap("→")
                Text(localized("Preview", "预览")).padding(.trailing, 6)
                keycap("↩")
                Text(localized("Apply", "应用")).padding(.trailing, 6)
                keycap("esc")
                Text(localized("Cancel", "取消"))
            }
            .font(.system(size: 10))
            .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localized("Arrow keys preview, Return applies, Esc cancels", "方向键预览，回车应用，Esc 取消"))
            .padding(.bottom, 10)

            Button(action: openLockSettings) {
                HStack {
                    Text(localized("Open Lock Screen Settings", "打开系统锁屏设置"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).frame(height: 36)
                .background(QuietLockStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(QuietLockStyle.accent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private func helpSection(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(QuietLockStyle.accent)
                .frame(width: 28, height: 28)
                .background(QuietLockStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(text).font(.system(size: 10.5)).lineSpacing(2)
                    .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.025),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .frame(minWidth: 18).padding(.horizontal, 3).frame(height: 17)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private var panelBackground: some View {
        ZStack {
            if !reduceTransparency { VisualEffectView() }
            QuietLockStyle.surface(colorScheme).opacity(reduceTransparency ? 1 : 0.96)
            if !reduceTransparency {
                RadialGradient(colors: [QuietLockStyle.mint.opacity(colorScheme == .dark ? 0.09 : 0.06), .clear],
                    center: .topLeading, startRadius: 0, endRadius: 290)
            }
        }
        .allowsHitTesting(false)
    }

    private func apply(_ preset: LockPreset) {
        guard model.canAdjust && !screenSaver.isApplying else { return }
        submitted = preset
        preview = nil
        Task {
            await model.apply(preset)
            withAnimation(QuietLockStyle.animation(reduceMotion: reduceMotion)) { submitted = nil }
        }
    }

    private func openLockSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : isHovered ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
    }
}

private struct CalloutActionStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .opacity(isEnabled ? 1 : 0.45)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.14), in: Capsule())
            .contentShape(Capsule())
    }
}
