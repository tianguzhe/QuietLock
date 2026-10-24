import QuietLockCore
import SwiftUI

/// A horizontal time readout with a small orbit, sized for a menu-bar panel.
struct TimeDial: View {
    let minutes: Int?
    let preset: LockPreset?
    let isPreviewing: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { preset.map { Double($0.index + 1) / 6 } ?? 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isPreviewing ? localized("Preview", "预览时长") : localized("Display sleeps after", "闲置后熄屏"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(minutes.map { $0 == 0 ? "∞" : String($0) } ?? "—")
                        .font(.system(size: 52, weight: .light, design: .rounded))
                        .tracking(minutes == 0 ? 0 : -2)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text(minutes == 0 ? localized("never", "永不") : minutes == nil ? localized("pick a step", "选择档位") : localized("min", "分钟"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(QuietLockStyle.secondaryText(colorScheme))
                }
                .frame(height: 55, alignment: .leading)
            }
            Spacer(minLength: 0)
            orbit
        }
        .frame(height: 82)
        .animation(QuietLockStyle.animation(reduceMotion: reduceMotion), value: fraction)
        .animation(QuietLockStyle.animation(reduceMotion: reduceMotion), value: minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Display sleep timer", "闲置熄屏时间"))
        .accessibilityValue(minutes.map { $0 == 0 ? localized("Never sleeps", "永不自动熄屏") : localized("\($0) minutes", "\($0) 分钟") }
            ?? localized("Mixed or unavailable", "当前时间未统一或不可用"))
    }

    private var orbit: some View {
        ZStack {
            Circle().fill(QuietLockStyle.accent.opacity(colorScheme == .dark ? 0.065 : 0.035))
            Circle()
                .trim(from: 0.10, to: 0.90)
                .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(5)
            Circle()
                .trim(from: 0.10, to: 0.10 + 0.80 * fraction)
                .stroke(QuietLockStyle.spectrum, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(90))
                .padding(5)
                .shadow(color: QuietLockStyle.accent.opacity(0.3), radius: 4)
            Image(systemName: minutes == 0 ? "sun.max" : "display")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(QuietLockStyle.accent)
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }
}
