import AppKit
import QuietLockCore
import SwiftUI

@main
struct QuietLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = PowerSettingsModel()
    private let screenSaver = ScreenSaverSettingsModel()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = QuietLockBrand.statusImage()
            button.toolTip = "静锁 QuietLock · 自动锁屏时间"
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("静锁，自动锁屏时间")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let controller = NSHostingController(rootView: QuietLockPanel(model: model, screenSaver: screenSaver))
        controller.sizingOptions = [.preferredContentSize]
        controller.safeAreaRegions = []
        controller.preferredContentSize = QuietLockPanel.size
        controller.view.setFrameSize(QuietLockPanel.size)
        popover.contentViewController = controller
        popover.contentSize = QuietLockPanel.size
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.refreshInBackground() }
            })
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshInBackground() }
        }
        refreshTimer?.tolerance = 3
        Task {
            // A crash or force quit skips termination; clear its leftover rule before anything else.
            await revokePasswordlessAccess()
            await refreshInBackground()
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = QuietLockPanel.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task {
            await model.refresh()
            await screenSaver.refresh()
        }
    }

    private func refreshInBackground() async {
        await model.refreshInBackground()
        await screenSaver.refreshInBackground()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func popoverWillShow(_ notification: Notification) {
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard FileManager.default.fileExists(atPath: PasswordlessAccess.path) else { return .terminateNow }
        Task {
            await revokePasswordlessAccess()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func revokePasswordlessAccess() async {
        guard FileManager.default.fileExists(atPath: PasswordlessAccess.path) else { return }
        do {
            try await SystemPowerSettingsService().revokeSessionAccess()
        } catch {
            NSLog("QuietLock: could not remove %@: %@", PasswordlessAccess.path, String(describing: error))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        model.stopKeepingAwake()
    }
}
