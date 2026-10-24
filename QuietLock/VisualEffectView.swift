import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum QuietLockStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.42, green: 0.95, blue: 0.80, alpha: 1)
            : NSColor(red: 0.02, green: 0.48, blue: 0.42, alpha: 1)
    })
    static let deepAccent = accent
    static let mint = Color(red: 0.42, green: 0.95, blue: 0.80)
    static let cyan = Color(red: 0.30, green: 0.76, blue: 0.97)
    static var spectrum: LinearGradient {
        LinearGradient(colors: [accent, cyan], startPoint: .leading, endPoint: .trailing)
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.96, blue: 1) : Color(red: 0.08, green: 0.15, blue: 0.22)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        primaryText(scheme).opacity(scheme == .dark ? 0.58 : 0.56)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.045, green: 0.075, blue: 0.12) : Color(red: 0.96, green: 0.98, blue: 1)
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)
    }
}
