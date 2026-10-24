import AppKit
import SwiftUI

/// A clock folded into a Q. One vector master is used at menu-bar and app-icon sizes.
enum QuietLockBrand {
    static func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let center = point(0.48, 0.47)
        path.addArc(center: center, radius: rect.width * 0.355,
                    startAngle: .pi / 3, endAngle: 2 * .pi + .pi / 9, clockwise: false)
        path.move(to: point(0.48, 0.28))
        path.addLine(to: point(0.48, 0.47))
        path.addLine(to: point(0.61, 0.47))
        path.move(to: point(0.64, 0.64))
        path.addLine(to: point(0.84, 0.84))
        return path
    }

    static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(in: rect.insetBy(dx: 0.5, dy: 0.5)))
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.55)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "静锁：调整自动锁屏时间"
        return image
    }
}

struct QuietLockMark: Shape {
    func path(in rect: CGRect) -> Path { Path(QuietLockBrand.path(in: rect)) }
}

struct BrandBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        QuietLockMark()
            .stroke(QuietLockStyle.spectrum, style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round))
            .padding(6)
            .frame(width: 35, height: 35)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(QuietLockStyle.accent.opacity(colorScheme == .dark ? 0.10 : 0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(QuietLockStyle.accent.opacity(0.17), lineWidth: 0.6)
            }
            .accessibilityHidden(true)
    }
}
