import AppKit
import QuietLockCore
import SwiftUI

struct ScreenSaverControls: View {
    @ObservedObject var model: ScreenSaverSettingsModel
    let isEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Bool { model.isCurrent && model.snapshot?.isEnabled == true }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "sparkles.tv" : "tv")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(isOn ? QuietLockStyle.accent : QuietLockStyle.secondaryText(colorScheme))
                .frame(width: 32, height: 32)
                .background((isOn ? QuietLockStyle.accent : Color.primary).opacity(isOn ? 0.09 : 0.05),
                            in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text("自动屏保")
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle("闲置时自动启动屏幕保护程序", isOn: Binding(
                get: { isOn },
                set: { enabled in Task { await model.setEnabled(enabled) } }
            ))
            .labelsHidden()
            .toggleStyle(AccentSwitchStyle())
            .disabled(!isEnabled || !model.canAdjust)
            .accessibilityValue(!model.isCurrent ? "状态未知" : model.snapshot?.isEnabled == true ? "已开启" : "已关闭")
            .help("关闭闲置自动屏保；重新开启时恢复原等待时间。")
            Button(action: openSettings) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
            .help("打开系统屏幕保护程序设置")
            .accessibilityLabel("打开系统屏幕保护程序设置")
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .animation(QuietLockStyle.animation(reduceMotion: reduceMotion), value: isOn)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.02), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5)
        }
    }

    private var detail: String {
        if model.isApplying { return "正在更新…" }
        if model.isRefreshing && !model.isCurrent { return "正在读取…" }
        if !model.isCurrent { return "读取失败，请重试" }
        if model.snapshot?.isManaged == true { return "由组织管理" }
        if model.snapshot?.isEnabled == false { return "已关闭 · 开启恢复原定时" }
        return model.snapshot?.detail ?? "状态未知"
    }

    private func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

/// An accent-filled switch: the small system switch rendered both states in near-identical grey here.
private struct AccentSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        // A plain button keeps the switch reachable by keyboard focus.
        Button { configuration.isOn.toggle() } label: { track(isOn: configuration.isOn) }
            .buttonStyle(.plain)
    }

    private func track(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(QuietLockStyle.spectrum)
                  : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12)))
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 0.5)
            }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}
