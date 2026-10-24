import AppKit

@main
struct GenerateIcon {
    static func main() throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try drawIcon(size: points * scale).representation(using: .png, properties: [:])!
                    .write(to: outputDirectory.appendingPathComponent(filename))
            }
        }
    }

    static func drawIcon(size: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setAllowsAntialiasing(true)

        let tile = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 192, yRadius: 192)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(red: 0.035, green: 0.07, blue: 0.12, alpha: 1).setFill()
        tile.fill()
        context.restoreGState()

        NSGradient(starting: NSColor(red: 0.075, green: 0.17, blue: 0.21, alpha: 1),
                   ending: NSColor(red: 0.025, green: 0.04, blue: 0.10, alpha: 1))!.draw(in: tile, angle: -65)

        context.saveGState()
        tile.addClip()
        let space = CGColorSpaceCreateDeviceRGB()
        let glow = CGGradient(colorsSpace: space, colors: [
            NSColor(red: 0.18, green: 0.9, blue: 0.72, alpha: 0.20).cgColor,
            NSColor(red: 0.08, green: 0.5, blue: 0.55, alpha: 0).cgColor
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: 810), startRadius: 0,
            endCenter: CGPoint(x: 390, y: 730), endRadius: 620, options: [.drawsAfterEndLocation])
        let blueGlow = CGGradient(colorsSpace: space, colors: [
            NSColor(red: 0.15, green: 0.5, blue: 1, alpha: 0.16).cgColor,
            NSColor(red: 0.05, green: 0.2, blue: 0.7, alpha: 0).cgColor
        ] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(blueGlow, startCenter: CGPoint(x: 820, y: 260), startRadius: 0,
            endCenter: CGPoint(x: 770, y: 320), endRadius: 540, options: [.drawsAfterEndLocation])
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.10).setStroke()
        tile.lineWidth = 2
        tile.stroke()

        // Fine orbit marks stay secondary to the bold Q silhouette.
        context.saveGState()
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        let center = CGPoint(x: 496, y: 488)
        for index in 0..<60 {
            let angle = CGFloat(index) / 60 * .pi * 2
            let major = index % 5 == 0
            let outer: CGFloat = 341
            let inner: CGFloat = major ? 326 : 335
            context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.setStrokeColor(NSColor.white.withAlphaComponent(major ? 0.20 : 0.07).cgColor)
            context.setLineWidth(major ? 2.5 : 1.5)
            context.setLineCap(.round)
            context.strokePath()
        }

        let glyph = QuietLockBrand.path(in: CGRect(x: 110, y: 110, width: 804, height: 804))
        context.setLineWidth(59)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 28, color: NSColor(red: 0.3, green: 1, blue: 0.82, alpha: 0.30).cgColor)
        context.addPath(glyph)
        context.setStrokeColor(NSColor(red: 0.34, green: 0.93, blue: 0.8, alpha: 0.55).cgColor)
        context.strokePath()
        context.restoreGState()

        context.addPath(glyph)
        context.replacePathWithStrokedPath()
        context.clip()
        let glyphGradient = CGGradient(colorsSpace: space, colors: [
            NSColor(red: 0.83, green: 1, blue: 0.94, alpha: 1).cgColor,
            NSColor(red: 0.37, green: 0.96, blue: 0.79, alpha: 1).cgColor,
            NSColor(red: 0.34, green: 0.74, blue: 1, alpha: 1).cgColor
        ] as CFArray, locations: [0, 0.46, 1])!
        context.drawLinearGradient(glyphGradient, start: CGPoint(x: 250, y: 230),
            end: CGPoint(x: 780, y: 830), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
