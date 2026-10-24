import AppKit
import QuietLockCore
import SwiftUI

struct PresetSlider: View {
    let selection: LockPreset?
    let isEnabled: Bool
    let onPreview: (LockPreset?) -> Void
    let onCommit: (LockPreset) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var dragPosition: CGFloat?
    @State private var keyboardSelection: LockPreset?
    @State private var lastHapticPreset: LockPreset?
    @State private var hoveredPreset: LockPreset?
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let inset = thumbSize / 2
            let trackWidth = max(1, geometry.size.width - thumbSize)
            let selectedIndex = selection.map { CGFloat($0.index) }
            let position = dragPosition ?? selectedIndex.map { $0 / 5 * trackWidth }

            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
                        .frame(height: 6)
                        .padding(.horizontal, inset)

                    if let position {
                        Capsule()
                            .fill(QuietLockStyle.spectrum)
                            .frame(width: max(5, position), height: 6)
                            .offset(x: inset)
                            .shadow(color: QuietLockStyle.accent.opacity(colorScheme == .dark ? 0.45 : 0.1), radius: 5)
                    }

                    ForEach(LockPreset.allCases) { preset in
                        Circle()
                            .fill(tickColor(preset, position: position, width: trackWidth))
                            .frame(width: 4, height: 4)
                            .offset(x: inset - 2 + CGFloat(preset.index) / 5 * trackWidth)
                    }

                    if let position {
                        Circle()
                            .fill(LinearGradient(
                                colors: colorScheme == .dark ? [Color(red: 0.19, green: 0.29, blue: 0.35), Color(red: 0.08, green: 0.15, blue: 0.21)] : [.white, Color(red: 0.91, green: 0.96, blue: 0.98)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .overlay {
                                Circle().strokeBorder(colorScheme == .dark ? QuietLockStyle.mint.opacity(0.65) : .white, lineWidth: 1)
                            }
                            .overlay {
                                Circle().fill(QuietLockStyle.accent)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: QuietLockStyle.accent.opacity(0.7), radius: 4)
                            }
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 4, y: 2)
                            .shadow(color: QuietLockStyle.accent.opacity(colorScheme == .dark ? 0.18 : 0), radius: 9)
                            .frame(width: thumbSize, height: thumbSize)
                            .scaleEffect(dragPosition == nil ? 1 : 1.08)
                            .offset(x: position)
                    }
                }
                .frame(height: 34)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isFocused = true
                        let x = min(max(value.location.x - inset, 0), trackWidth)
                        dragPosition = x
                        let next = preset(at: x, width: trackWidth)
                        if let lastHapticPreset, lastHapticPreset != next {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        lastHapticPreset = next
                        onPreview(next)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        let x = min(max(value.location.x - inset, 0), trackWidth)
                        let target = preset(at: x, width: trackWidth)
                        withAnimation(QuietLockStyle.animation(reduceMotion: reduceMotion)) {
                            dragPosition = nil
                            lastHapticPreset = nil
                            onPreview(nil)
                            onCommit(target)
                        }
                    })

                HStack(spacing: 0) {
                    ForEach(LockPreset.allCases) { preset in
                        Button {
                            guard isEnabled else { return }
                            onCommit(preset)
                        } label: {
                            Text(preset.tickLabel)
                                .font(.system(size: preset == .never ? 16 : 11, weight: selection == preset ? .semibold : .medium, design: .rounded))
                                .foregroundStyle(selection == preset ? QuietLockStyle.accent : QuietLockStyle.secondaryText(colorScheme))
                                .frame(width: thumbSize, height: 25)
                                .background(QuietLockStyle.accent.opacity(selection == preset ? 0.12 : hoveredPreset == preset ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .accessibilityHidden(true)
                        .focusable(false)
                        .onHover { hoveredPreset = $0 ? preset : nil }
                        if preset != .never { Spacer(minLength: 0) }
                    }
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(QuietLockStyle.accent.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
                    .padding(-5)
            }
            .focusable(isEnabled)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { keyboardAdjust(-1) }
            .onKeyPress(.rightArrow) { keyboardAdjust(1) }
            .onKeyPress(.return) { commitKeyboardSelection() }
            .onKeyPress(.space) { commitKeyboardSelection() }
            .onKeyPress(.escape) {
                guard keyboardSelection != nil || dragPosition != nil else { return .ignored }
                keyboardSelection = nil
                dragPosition = nil
                onPreview(nil)
                return .handled
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { keyboardSelection = nil; onPreview(nil) }
            }
            .accessibilityRepresentation {
                Slider(value: Binding(
                    get: { Double(selection?.index ?? 0) },
                    set: { value in
                        guard isEnabled else { return }
                        onCommit(LockPreset.allCases[min(5, max(0, Int(value.rounded())))])
                    }
                ), in: 0...5, step: 1)
                .disabled(!isEnabled)
                .accessibilityLabel(localized("Display sleep timer", "闲置熄屏时间"))
                .accessibilityValue(selection?.label ?? localized("Custom or mixed setting", "当前为自定义或未统一设置"))
                .accessibilityHint(localized("Arrow keys preview, Return applies. Adjusting asks for authorization.",
                                              "方向键预览，回车应用。VoiceOver 调整后请求系统授权。"))
            }
            .animation(dragPosition == nil ? QuietLockStyle.animation(reduceMotion: reduceMotion) : nil, value: selection)
        }
        .frame(height: 59)
        .onDisappear { dragPosition = nil; keyboardSelection = nil; onPreview(nil) }
    }

    private func preset(at x: CGFloat, width: CGFloat) -> LockPreset {
        LockPreset.allCases[min(5, max(0, Int((x / width * 5).rounded())))]
    }

    private func tickColor(_ preset: LockPreset, position: CGFloat?, width: CGFloat) -> Color {
        if let position, CGFloat(preset.index) / 5 * width <= position + 1 {
            return .white.opacity(0.65)
        }
        return Color.primary.opacity(0.22)
    }

    private func keyboardAdjust(_ direction: Int) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        let index = keyboardSelection?.index ?? selection?.index ?? (direction > 0 ? -1 : 6)
        let next = LockPreset.allCases[min(5, max(0, index + direction))]
        keyboardSelection = next
        withAnimation(QuietLockStyle.animation(reduceMotion: reduceMotion)) { onPreview(next) }
        return .handled
    }

    private func commitKeyboardSelection() -> KeyPress.Result {
        guard isEnabled, let preset = keyboardSelection else { return .ignored }
        keyboardSelection = nil
        onPreview(nil)
        onCommit(preset)
        return .handled
    }
}
