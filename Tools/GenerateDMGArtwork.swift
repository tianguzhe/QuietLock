import AppKit

/// Finder renders the background at 640 × 440 points; include both display scales.
@main
struct GenerateDMGArtwork {
    private static let size = NSSize(width: 640, height: 440)

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "QuietLockDMG", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Usage: GenerateDMGArtwork <directory> <version>"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let representations = [1, 2].map { draw(scale: $0, version: CommandLine.arguments[2]) }
        let image = NSImage(size: size)
        representations.forEach { image.addRepresentation($0) }
        guard let tiff = image.tiffRepresentation,
              let png = representations[1].representation(using: .png, properties: [:]) else {
            throw NSError(domain: "QuietLockDMG", code: 2)
        }
        try tiff.write(to: directory.appendingPathComponent("background.tiff"))
        try png.write(to: directory.appendingPathComponent("background@2x.png"))
    }

    private static func draw(scale: Int, version: String) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        let drawingContext = NSGraphicsContext(bitmapImageRep: bitmap)!
        let cg = drawingContext.cgContext
        // The bitmap's logical size already gives its context the Retina scale.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        cg.setAllowsAntialiasing(true)

        let mint = color(0.20, 0.84, 0.69)
        let ink = color(0.08, 0.16, 0.20)
        let secondary = color(0.40, 0.49, 0.53)
        let bounds = NSRect(origin: .zero, size: size)
        gradient([color(0.94, 0.98, 0.97), color(0.97, 0.98, 0.99)],
                 from: CGPoint(x: 80, y: 150), to: CGPoint(x: 580, y: 440), in: bounds, context: cg)

        // A dark glass header continues the application's mint / cyan identity.
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: 0, width: 640, height: 136))
        gradient([color(0.045, 0.10, 0.14), color(0.065, 0.15, 0.18)],
                 from: CGPoint(x: 80, y: 130), to: CGPoint(x: 610, y: -100), in: bounds, context: cg)
        for (radius, alpha) in [(80.0, 0.09), (113.0, 0.07), (148.0, 0.05), (185.0, 0.035)] {
            cg.setStrokeColor(mint.withAlphaComponent(alpha).cgColor)
            cg.setLineWidth(0.75)
            cg.strokeEllipse(in: CGRect(x: 562 - radius, y: -64 - radius,
                                       width: radius * 2, height: radius * 2))
        }
        cg.restoreGState()

        let badge = NSBezierPath(roundedRect: NSRect(x: 40, y: 32, width: 46, height: 46), xRadius: 14, yRadius: 14)
        mint.withAlphaComponent(0.09).setFill()
        badge.fill()
        mint.withAlphaComponent(0.22).setStroke()
        badge.lineWidth = 0.7
        badge.stroke()
        cg.addPath(QuietLockBrand.path(in: CGRect(x: 48, y: 40, width: 30, height: 30)))
        cg.setStrokeColor(color(0.52, 0.97, 0.84).cgColor)
        cg.setLineWidth(2.3)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.strokePath()
        text("静锁 QuietLock", in: NSRect(x: 101, y: 36, width: 370, height: 35),
             font: .systemFont(ofSize: 26, weight: .semibold), color: .white)
        text("让每一次离开，都安心。", in: NSRect(x: 41, y: 96, width: 430, height: 22),
             font: .systemFont(ofSize: 12), color: color(0.66, 0.78, 0.80))

        let versionRect = NSRect(x: 527, y: 43, width: 73, height: 25)
        NSColor.white.withAlphaComponent(0.055).setFill()
        NSBezierPath(roundedRect: versionRect, xRadius: 12.5, yRadius: 12.5).fill()
        text("v\(version)", in: versionRect.offsetBy(dx: 0, dy: 5),
             font: .monospacedSystemFont(ofSize: 10, weight: .medium),
             color: color(0.63, 0.80, 0.78), alignment: .center)

        text("将 QuietLock 拖入右侧文件夹", in: NSRect(x: 40, y: 161, width: 560, height: 24),
             font: .systemFont(ofSize: 14, weight: .medium), color: ink, alignment: .center)

        // These halos align with the Finder icon centres in dmg-settings.py.
        for x in [170.0, 470.0] {
            let circle = NSRect(x: x - 67, y: 238 - 67, width: 134, height: 134)
            color(1, 1, 1).withAlphaComponent(0.65).setFill()
            NSBezierPath(ovalIn: circle).fill()
            color(0.17, 0.50, 0.47).withAlphaComponent(0.10).setStroke()
            let ring = NSBezierPath(ovalIn: circle)
            ring.lineWidth = 0.75
            ring.stroke()
        }

        cg.saveGState()
        cg.setStrokeColor(color(0.24, 0.56, 0.52).cgColor)
        cg.setLineWidth(2)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: 295, y: 238))
        cg.addLine(to: CGPoint(x: 345, y: 238))
        cg.move(to: CGPoint(x: 336, y: 229))
        cg.addLine(to: CGPoint(x: 345, y: 238))
        cg.addLine(to: CGPoint(x: 336, y: 247))
        cg.strokePath()
        cg.restoreGState()

        text("拖动安装", in: NSRect(x: 272, y: 260, width: 96, height: 20),
             font: .systemFont(ofSize: 10, weight: .medium), color: secondary, alignment: .center)

        cg.setStrokeColor(color(0.15, 0.35, 0.34).withAlphaComponent(0.12).cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: 40, y: 355))
        cg.addLine(to: CGPoint(x: 600, y: 355))
        cg.strokePath()
        text("安装后，打开应用，从屏幕顶部的 Q 图标开始。", in: NSRect(x: 40, y: 373, width: 560, height: 22),
             font: .systemFont(ofSize: 12), color: secondary, alignment: .center)
        text("macOS 14+   ·   Apple Silicon 与 Intel", in: NSRect(x: 40, y: 406, width: 560, height: 18),
             font: .systemFont(ofSize: 10), color: secondary.withAlphaComponent(0.8), alignment: .center)

        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor,
                             alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]).draw(in: rect)
    }

    private static func gradient(_ colors: [NSColor], from start: CGPoint, to end: CGPoint,
                                 in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
