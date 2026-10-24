import AppKit
import QuietLockCore
import SwiftUI

private struct PreviewService: PowerSettingsServing {
    let snapshot: PowerSnapshot
    func read() async throws -> PowerSnapshot { snapshot }
    func apply(_ preset: LockPreset) async throws { throw PowerSettingsError.writeFailed }
}

@MainActor
private final class PreviewSleepProtection: IdleSleepProtecting {
    private(set) var isActive = false
    func activate() throws { isActive = true }
    func deactivate() { isActive = false }
}

private struct PreviewScreenSaverService: ScreenSaverSettingsServing {
    let enabled: Bool
    func read() async throws -> ScreenSaverSnapshot { ScreenSaverSnapshot(idleSeconds: enabled ? 1200 : 0) }
    func setEnabled(_ enabled: Bool) async throws {}
}

private struct UnavailablePowerService: PowerSettingsServing {
    func read() async throws -> PowerSnapshot { throw PowerSettingsError.readFailed }
    func apply(_ preset: LockPreset) async throws { throw PowerSettingsError.writeFailed }
}

private struct UnavailableScreenSaverService: ScreenSaverSettingsServing {
    func read() async throws -> ScreenSaverSnapshot { throw ScreenSaverSettingsError.readFailed }
    func setEnabled(_ enabled: Bool) async throws { throw ScreenSaverSettingsError.writeFailed }
}

private actor AuthorizingPreviewService: PowerSettingsServing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func read() async throws -> PowerSnapshot {
        PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: 10)])
    }
    func apply(_ preset: LockPreset) async throws {
        await withCheckedContinuation {
            continuation = $0
            waiter?.resume()
            waiter = nil
        }
        throw PowerSettingsError.authorizationCancelled
    }
    func waitForAuthorization() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func cancel() { continuation?.resume(); continuation = nil }
}

@main
struct RenderPreviews {
    @MainActor
    static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "com.quietlock.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let standard = PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: 10)])
        let mixed = PowerSnapshot(profiles: [PowerProfile(source: .battery, minutes: 5), PowerProfile(source: .adapter, minutes: 15)])
        let variants: [(String, PowerSnapshot, Bool, Bool)] = [
            ("quietlock-light", standard, false, false),
            ("quietlock-dark", standard, true, false),
            ("quietlock-compact", standard, false, true),
            ("quietlock-dark-compact", standard, true, true),
            ("quietlock-mixed", mixed, true, true),
            ("quietlock-custom", PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: 7)]), false, true),
            ("quietlock-never", PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: 0)]), true, true),
            ("quietlock-never-guidance", PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: 0)]), true, false),
            ("quietlock-help", standard, true, true),
            ("quietlock-unavailable", standard, false, true),
            ("quietlock-saver-error", standard, true, true),
            ("quietlock-authorizing", standard, true, true)
        ]

        var sizes: [String: NSSize] = [:]
        for (name, snapshot, isDark, compact) in variants {
            defaults.set(compact, forKey: "hasReadLockGuidance")
            let authorizing = AuthorizingPreviewService()
            let service: any PowerSettingsServing
            if name == "quietlock-unavailable" { service = UnavailablePowerService() }
            else if name == "quietlock-authorizing" { service = authorizing }
            else { service = PreviewService(snapshot: snapshot) }
            let model = PowerSettingsModel(service: service, protection: PreviewSleepProtection())
            await model.refresh()
            let saverService: any ScreenSaverSettingsServing = name == "quietlock-saver-error"
                ? UnavailableScreenSaverService() : PreviewScreenSaverService(enabled: name != "quietlock-never")
            let saver = ScreenSaverSettingsModel(service: saverService)
            await saver.refresh()
            var authorizationTask: Task<Void, Never>?
            if name == "quietlock-authorizing" {
                authorizationTask = Task { await model.apply(.fiveMinutes) }
                await authorizing.waitForAuthorization()
            }
            let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
            let content = QuietLockPanel(model: model, screenSaver: saver,
                                        initialPage: name == "quietlock-help" ? .help : .controls)
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, isDark ? .dark : .light)
            let view = NSHostingView(rootView: content)
            view.appearance = appearance
            let size = view.fittingSize
            guard size == QuietLockPanel.size else {
                throw NSError(domain: "QuietLockPreview", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected panel size: \(name) \(size)"])
            }
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()

            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "QuietLockPreview", code: 1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "QuietLockPreview", code: 2)
            }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
            sizes[name] = size
            print("\(name): \(Int(size.width)) × \(Int(size.height)) pt")
            window.contentView = nil
            if let authorizationTask {
                await authorizing.cancel()
                await authorizationTask.value
            }
        }
        try renderDesignSheet(directory: directory, sizes: sizes)
        try renderCompactSheet(directory: directory)
    }

    @MainActor
    private static func renderCompactSheet(directory: URL) throws {
        let image = NSImage(size: NSSize(width: 752, height: 500))
        image.lockFocus()
        NSColor(red: 0.055, green: 0.075, blue: 0.11, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 752, height: 500).fill()
        for (name, x, title) in [
            ("quietlock-dark-compact", CGFloat(24), localized("Dark · 344 × 420 pt", "深色 · 344 × 420pt")),
            ("quietlock-compact", CGFloat(384), localized("Light · 344 × 420 pt", "浅色 · 344 × 420pt"))
        ] {
            NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.65)
            ]).draw(at: NSPoint(x: x + 2, y: 470))
            NSImage(contentsOf: directory.appendingPathComponent("\(name).png"))!
                .draw(in: NSRect(x: x, y: 30, width: 344, height: 420))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("ui-preview.png"))
    }

    @MainActor
    private static func renderDesignSheet(directory: URL, sizes: [String: NSSize]) throws {
        let panelHeight = max(sizes["quietlock-dark-compact"]!.height, sizes["quietlock-compact"]!.height)
        let sheetSize = NSSize(width: 1104, height: panelHeight + 112)
        let image = NSImage(size: sheetSize)
        image.lockFocus()
        NSColor(red: 0.055, green: 0.075, blue: 0.11, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheetSize).fill()

        func label(_ text: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
                .draw(at: NSPoint(x: x, y: y))
        }
        let labelColor = NSColor(red: 0.58, green: 0.66, blue: 0.75, alpha: 1)
        label(localized("01 / Dark", "01 / 深色"), x: 32, y: sheetSize.height - 39, font: .systemFont(ofSize: 10, weight: .medium), color: labelColor)
        label(localized("02 / Light", "02 / 浅色"), x: 408, y: sheetSize.height - 39, font: .systemFont(ofSize: 10, weight: .medium), color: labelColor)
        label(localized("03 / Original icon", "03 / 原创图标"), x: 800, y: sheetSize.height - 39, font: .systemFont(ofSize: 10, weight: .medium), color: labelColor)
        for (name, x) in [("quietlock-dark-compact", CGFloat(32)), ("quietlock-compact", CGFloat(408))] {
            let panelImage = NSImage(contentsOf: directory.appendingPathComponent("\(name).png"))!
            let size = sizes[name]!
            panelImage.draw(in: NSRect(x: x, y: sheetSize.height - 60 - size.height, width: size.width, height: size.height))
        }
        let iconURL = URL(fileURLWithPath: ".build/AppIcon.iconset/icon_512x512@2x.png")
        if let icon = NSImage(contentsOf: iconURL) {
            icon.draw(in: NSRect(x: 794, y: sheetSize.height - 328, width: 278, height: 278))
        }
        label("Q × CLOCK", x: 885, y: sheetSize.height - 359,
              font: .monospacedSystemFont(ofSize: 10, weight: .medium), color: labelColor)
        label(localized("Menu bar · actual 18 pt", "状态栏 · 实际 18pt"), x: 810, y: sheetSize.height - 418,
              font: .systemFont(ofSize: 10), color: labelColor)

        for (isDark, x) in [(false, CGFloat(800)), (true, CGFloat(940))] {
            let bar = NSRect(x: x, y: sheetSize.height - 480, width: 124, height: 40)
            (isDark ? NSColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1) : NSColor(red: 0.9, green: 0.93, blue: 0.96, alpha: 1)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 11, yRadius: 11).fill()
            let color = isDark ? NSColor.white : NSColor.black
            let cg = NSGraphicsContext.current!.cgContext
            cg.saveGState()
            cg.translateBy(x: bar.minX + 18, y: bar.midY + 9)
            cg.scaleBy(x: 1, y: -1)
            cg.addPath(QuietLockBrand.path(in: CGRect(x: 0.5, y: 0.5, width: 17, height: 17)))
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(1.55)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
            cg.restoreGState()
            label(localized("QuietLock", "静锁"), x: bar.minX + 49, y: bar.midY - 7, font: .systemFont(ofSize: 11, weight: .medium), color: color)
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("design-preview.png"))
    }
}
