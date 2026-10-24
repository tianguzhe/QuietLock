import XCTest
@testable import QuietLockCore

private actor MemoryScreenSaverStore: ScreenSaverPreferenceStoring {
    var actual: ScreenSaverSnapshot
    var saved: Int?
    var failRead = false
    var failWrite = false
    var ignoreWrite = false
    var writes: [Int] = []
    let holdWrite: Bool
    private var writeGate: CheckedContinuation<Void, Never>?
    private var writeWaiter: CheckedContinuation<Void, Never>?

    init(seconds: Int, saved: Int? = nil, managed: Bool = false, holdWrite: Bool = false) {
        actual = ScreenSaverSnapshot(idleSeconds: seconds, isManaged: managed)
        self.saved = saved
        self.holdWrite = holdWrite
    }

    func read() throws -> ScreenSaverSnapshot {
        if failRead { throw ScreenSaverSettingsError.readFailed }
        return actual
    }

    func writeIdleSeconds(_ seconds: Int) async throws {
        writes.append(seconds)
        if holdWrite {
            await withCheckedContinuation { continuation in
                writeGate = continuation
                writeWaiter?.resume()
                writeWaiter = nil
            }
        }
        if failWrite { throw ScreenSaverSettingsError.writeFailed }
        if !ignoreWrite { actual = ScreenSaverSnapshot(idleSeconds: seconds) }
    }

    func savedIdleSeconds() -> Int? { saved }
    func saveIdleSeconds(_ seconds: Int) { saved = seconds }
    func recordedWrites() -> [Int] { writes }
    func setReadFailure(_ value: Bool) { failRead = value }
    func setWriteFailure() { failWrite = true }
    func setIgnoringWrite() { ignoreWrite = true }
    func setActual(_ seconds: Int) { actual = ScreenSaverSnapshot(idleSeconds: seconds) }
    func waitForWrite() async {
        if writeGate != nil { return }
        await withCheckedContinuation { writeWaiter = $0 }
    }
    func releaseWrite() { writeGate?.resume(); writeGate = nil }
}

final class ScreenSaverServiceTests: XCTestCase {
    func testDisableAndReenableRestoresExactCustomTimeout() async throws {
        let store = MemoryScreenSaverStore(seconds: 93)
        let service = SystemScreenSaverSettingsService(store: store)
        try await service.setEnabled(false)
        let disabled = try await service.read()
        XCTAssertFalse(disabled.isEnabled)
        try await service.setEnabled(true)
        let restored = try await service.read()
        XCTAssertEqual(restored.idleSeconds, 93)
        let writes = await store.recordedWrites()
        XCTAssertEqual(writes, [0, 93])
    }

    func testEnableWithoutBackupUsesTwentyMinutes() async throws {
        let store = MemoryScreenSaverStore(seconds: 0, saved: -1)
        let service = SystemScreenSaverSettingsService(store: store)
        try await service.setEnabled(true)
        let actual = try await service.read()
        XCTAssertEqual(actual.idleSeconds, 1200)
    }

    func testAlreadySelectedValueDoesNotWriteOrReplaceBackup() async throws {
        let store = MemoryScreenSaverStore(seconds: 0, saved: 600)
        try await SystemScreenSaverSettingsService(store: store).setEnabled(false)
        let writes = await store.recordedWrites()
        let saved = await store.savedIdleSeconds()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(saved, 600)
    }

    func testManagedSettingCannotBeWritten() async {
        let store = MemoryScreenSaverStore(seconds: 1200, managed: true)
        do {
            try await SystemScreenSaverSettingsService(store: store).setEnabled(false)
            XCTFail("Expected managed error")
        } catch { XCTAssertEqual(error as? ScreenSaverSettingsError, .managed) }
        let writes = await store.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    func testReadbackMismatchCannotReportSuccess() async {
        let store = MemoryScreenSaverStore(seconds: 1200)
        await store.setIgnoringWrite()
        do {
            try await SystemScreenSaverSettingsService(store: store).setEnabled(false)
            XCTFail("Expected verification failure")
        } catch { XCTAssertEqual(error as? ScreenSaverSettingsError, .verificationMismatch) }
    }

    func testIdleTimeAcceptsIntegersAndNumericStrings() {
        // `defaults -currentHost write com.apple.screensaver idleTime 0` (no -int) stores a string.
        XCTAssertEqual(ScreenSaverIdlePreference.seconds(from: NSNumber(value: 300)), 300)
        XCTAssertEqual(ScreenSaverIdlePreference.seconds(from: "0" as NSString), 0)
        XCTAssertEqual(ScreenSaverIdlePreference.seconds(from: "600" as NSString), 600)
        for invalid: CFPropertyList in ["-1" as NSString, "abc" as NSString, "" as NSString,
                                        NSNumber(value: 1.5), kCFBooleanTrue, [1] as NSArray] {
            XCTAssertNil(ScreenSaverIdlePreference.seconds(from: invalid), "\(invalid)")
        }
    }

    func testLivePreferencesAreReadOnly() async throws {
        let actual = try await SystemScreenSaverSettingsService().read()
        XCTAssertGreaterThanOrEqual(actual.idleSeconds, 0)
    }
}

@MainActor
final class ScreenSaverModelTests: XCTestCase {
    func testConfirmedToggleAndRefreshReflectExternalChanges() async throws {
        let store = MemoryScreenSaverStore(seconds: 1200)
        let model = ScreenSaverSettingsModel(service: SystemScreenSaverSettingsService(store: store))
        await model.refresh()
        await model.setEnabled(false)
        XCTAssertEqual(model.snapshot?.isEnabled, false)
        XCTAssertEqual(model.feedback?.kind, .success)
        await store.setActual(300)
        await model.refreshInBackground()
        XCTAssertEqual(model.snapshot?.idleSeconds, 300)
        XCTAssertNil(model.feedback)
    }

    func testFailedWriteDisplaysActualEnabledState() async {
        let store = MemoryScreenSaverStore(seconds: 1200)
        await store.setWriteFailure()
        let model = ScreenSaverSettingsModel(service: SystemScreenSaverSettingsService(store: store))
        await model.refresh()
        await model.setEnabled(false)
        XCTAssertEqual(model.snapshot?.isEnabled, true)
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertTrue(model.canAdjust)
    }

    func testReadFailureDisablesSwitchUntilRecovery() async {
        let store = MemoryScreenSaverStore(seconds: 1200)
        await store.setReadFailure(true)
        let model = ScreenSaverSettingsModel(service: SystemScreenSaverSettingsService(store: store))
        await model.refresh()
        XCTAssertFalse(model.canAdjust)
        await model.setEnabled(false)
        let writes = await store.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        await store.setReadFailure(false)
        await model.refresh()
        XCTAssertTrue(model.canAdjust)
        XCTAssertNil(model.feedback)
    }

    func testDuplicateToggleAndRefreshAreIgnoredWhileWriting() async {
        let store = MemoryScreenSaverStore(seconds: 1200, holdWrite: true)
        let model = ScreenSaverSettingsModel(service: SystemScreenSaverSettingsService(store: store))
        await model.refresh()
        let first = Task { await model.setEnabled(false) }
        await store.waitForWrite()
        XCTAssertTrue(model.isApplying)
        await model.setEnabled(true)
        await model.setEnabled(false)
        await model.refreshInBackground()
        await store.releaseWrite()
        await first.value
        let writes = await store.recordedWrites()
        XCTAssertEqual(writes, [0])
        XCTAssertEqual(model.snapshot?.isEnabled, false)
        XCTAssertEqual(model.feedback?.kind, .success)
    }
}
