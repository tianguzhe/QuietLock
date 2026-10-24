import XCTest
@testable import QuietLockCore

final class PowerSettingsParserTests: XCTestCase {
    func testDesktopProfile() throws {
        let settings = try PowerSettingsParser.parse("""
        AC Power:
         sleep 0
         displaysleep         10
         disksleep 10
        """)
        XCTAssertEqual(settings.uniformMinutes, 10)
        XCTAssertEqual(settings.preset, .tenMinutes)
        XCTAssertEqual(settings.profiles, [PowerProfile(source: .adapter, minutes: 10)])
    }

    func testAllPowerSourcesAndNever() throws {
        let settings = try PowerSettingsParser.parse("""
        Battery Power:
          displaysleep 0
        AC Power:
          displaysleep 0
        UPS Power:
          displaysleep 0
        """)
        XCTAssertEqual(settings.profiles.count, 3)
        XCTAssertEqual(settings.preset, .never)
    }

    func testCustomValueIsPreserved() throws {
        let settings = try PowerSettingsParser.parse("AC Power:\n displaysleep 7\n")
        XCTAssertEqual(settings.uniformMinutes, 7)
        XCTAssertNil(settings.preset)
    }

    func testDifferentPowerSourcesRemainMixed() throws {
        let settings = try PowerSettingsParser.parse("Battery Power:\n displaysleep 5\nAC Power:\n displaysleep 15\n")
        XCTAssertNil(settings.uniformMinutes)
        XCTAssertNil(settings.preset)
        XCTAssertEqual(settings.detail, localized("Battery 5 min · AC 15 min", "电池 5 分钟 · 接电 15 分钟"))
    }

    func testInvalidAndIncompleteOutputsAreRejected() {
        for output in [
            "", "permission denied", "AC Power:\n sleep 10",
            "AC Power:\n displaysleep -1", "AC Power:\n displaysleep never",
            "Battery Power:\n sleep 10\nAC Power:\n displaysleep 5",
            "AC Power:\n displaysleep 5\n displaysleep 10",
            "AC Power:\n displaysleep 5\nAC Power:\n displaysleep 5",
            "AC Power:\n displaysleep 5 unexpected"
        ] {
            XCTAssertThrowsError(try PowerSettingsParser.parse(output), output)
        }
    }

    func testUnrelatedOutputDoesNotBecomeAPowerProfile() throws {
        let settings = try PowerSettingsParser.parse("Warning: using current profiles\nAC Power:\n displaysleep 30\n")
        XCTAssertEqual(settings.preset, .thirtyMinutes)
    }
}

private actor StubExecutor: CommandExecuting {
    struct Invocation: Sendable {
        let executable: String
        let arguments: [String]
    }
    var results: [CommandResult]
    var invocations: [Invocation] = []

    init(_ results: [CommandResult]) { self.results = results }

    func run(executable: String, arguments: [String]) async throws -> CommandResult {
        invocations.append(Invocation(executable: executable, arguments: arguments))
        return results.removeFirst()
    }

    func recorded() -> [Invocation] { invocations }
}

final class PowerSettingsServiceTests: XCTestCase {
    func testRealProcessRunnerCapturesUnicode() async throws {
        let result = try await ProcessCommandExecutor().run(executable: "/usr/bin/printf", arguments: ["%s", "静锁 ✓"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "静锁 ✓")
    }

    func testRealProcessRunnerPreservesFailureStatus() async throws {
        let result = try await ProcessCommandExecutor().run(executable: "/usr/bin/false", arguments: [])
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testProductionServiceReadsLiveSettingsWithoutAuthorization() async throws {
        let snapshot = try await SystemPowerSettingsService().read()
        XCTAssertFalse(snapshot.profiles.isEmpty)
        XCTAssertTrue(snapshot.profiles.allSatisfy { $0.minutes >= 0 })
    }

    func testReadUsesReadOnlyCommand() async throws {
        let executor = StubExecutor([CommandResult(exitCode: 0, output: "AC Power:\n displaysleep 10")])
        let snapshot = try await SystemPowerSettingsService(executor: executor).read()
        XCTAssertEqual(snapshot.preset, .tenMinutes)
        let calls = await executor.recorded()
        XCTAssertEqual(calls.first?.executable, "/usr/bin/pmset")
        XCTAssertEqual(calls.first?.arguments, ["-g", "custom"])
    }

    func testReadProcessFailure() async {
        let executor = StubExecutor([CommandResult(exitCode: 1, output: "failed")])
        do {
            _ = try await SystemPowerSettingsService(executor: executor).read()
            XCTFail("Expected a read error")
        } catch { XCTAssertEqual(error as? PowerSettingsError, .readFailed) }
    }

    private let sudoRefused = CommandResult(exitCode: 1, output: "sudo: a password is required\n")

    private let promptOK = CommandResult(exitCode: 0, output: "QUIETLOCK_OK\n")

    func testFirstChangeInEachLaunchPromptsEvenIfARuleIsLeftOver() async throws {
        // A leftover rule would let sudo succeed; a new launch must still ask once.
        let executor = StubExecutor([promptOK])
        try await SystemPowerSettingsService(executor: executor, userName: "mac").apply(.fiveMinutes)
        let calls = await executor.recorded()
        XCTAssertEqual(calls.map(\.executable), ["/usr/bin/osascript"])
    }

    func testLaterChangesInTheSameLaunchDoNotPrompt() async throws {
        let executor = StubExecutor([promptOK, CommandResult(exitCode: 0, output: "")])
        let service = SystemPowerSettingsService(executor: executor, userName: "mac")
        try await service.apply(.fiveMinutes)
        try await service.apply(.tenMinutes)
        let calls = await executor.recorded()
        XCTAssertEqual(calls.map(\.executable), ["/usr/bin/osascript", "/usr/bin/sudo"])
        XCTAssertEqual(calls.last?.arguments, ["-n", "/usr/bin/pmset", "-a", "displaysleep", "10"])
    }

    func testRemovedRulePromptsAgainInsteadOfFailing() async throws {
        let executor = StubExecutor([promptOK, sudoRefused, promptOK])
        let service = SystemPowerSettingsService(executor: executor, userName: "mac")
        try await service.apply(.fiveMinutes)
        try await service.apply(.tenMinutes)
        let calls = await executor.recorded()
        XCTAssertEqual(calls.map(\.executable), ["/usr/bin/osascript", "/usr/bin/sudo", "/usr/bin/osascript"])
    }

    func testCancelledPromptDoesNotGrantTheLaunch() async throws {
        let executor = StubExecutor([CommandResult(exitCode: 0, output: "QUIETLOCK_CANCELLED"), promptOK])
        let service = SystemPowerSettingsService(executor: executor, userName: "mac")
        do { try await service.apply(.fiveMinutes) } catch {}
        try await service.apply(.fiveMinutes)
        let calls = await executor.recorded()
        XCTAssertEqual(calls.map(\.executable), ["/usr/bin/osascript", "/usr/bin/osascript"])
    }

    func testEveryPresetPromptInstallsTheSessionRule() async throws {
        let executor = StubExecutor(LockPreset.allCases.map { _ in promptOK })
        for preset in LockPreset.allCases {
            try await SystemPowerSettingsService(executor: executor, userName: "mac").apply(preset)
        }
        let calls = await executor.recorded()
        XCTAssertEqual(calls.count, 6)
        for (call, preset) in zip(calls, LockPreset.allCases) {
            XCTAssertEqual(call.executable, "/usr/bin/osascript")
            XCTAssertEqual(call.arguments.count, 4)
            XCTAssertTrue(call.arguments[1].contains("with administrator privileges"))
            let command = call.arguments[3]
            XCTAssertTrue(command.hasPrefix("/usr/bin/pmset -a displaysleep \(preset.rawValue) || exit 1\n"))
            XCTAssertTrue(command.contains("/usr/sbin/visudo -cf"))
            XCTAssertTrue(command.contains("/usr/bin/install -m 0440 -o root -g wheel"))
            XCTAssertTrue(command.contains(PasswordlessAccess.rule(for: "mac")!))
        }
    }

    func testPasswordlessRuleAllowsOnlyPresetsAndItsOwnRemoval() {
        XCTAssertEqual(PasswordlessAccess.rule(for: "mac"),
            "mac ALL = (root) NOPASSWD: /usr/bin/pmset -a displaysleep 1, /usr/bin/pmset -a displaysleep 5, " +
            "/usr/bin/pmset -a displaysleep 10, /usr/bin/pmset -a displaysleep 15, " +
            "/usr/bin/pmset -a displaysleep 30, /usr/bin/pmset -a displaysleep 0, " +
            "/bin/rm -f /etc/sudoers.d/quietlock")
        for unsafe in ["", "a b", "a'b", "a,b", "%admin", "-x", "a\nb"] {
            XCTAssertNil(PasswordlessAccess.rule(for: unsafe), unsafe)
        }
    }

    func testUnsafeUserNameStillChangesSettingWithoutInstallingRule() async throws {
        let executor = StubExecutor([promptOK])
        try await SystemPowerSettingsService(executor: executor, userName: "a'b").apply(.tenMinutes)
        let command = await executor.recorded().last!.arguments[3]
        XCTAssertTrue(command.hasPrefix("/usr/bin/pmset -a displaysleep 10"))
        XCTAssertFalse(command.contains("sudoers"))
    }

    func testRevokingRemovesTheRuleWithoutPrompt() async throws {
        let executor = StubExecutor([CommandResult(exitCode: 0, output: ""), sudoRefused])
        let service = SystemPowerSettingsService(executor: executor, userName: "mac")
        try await service.revokeSessionAccess()
        let call = await executor.recorded().first!
        XCTAssertEqual(call.executable, "/usr/bin/sudo")
        XCTAssertEqual(call.arguments, ["-n", "/bin/rm", "-f", "/etc/sudoers.d/quietlock"])
        do {
            try await service.revokeSessionAccess()
            XCTFail("Expected a refused removal to be reported")
        } catch { XCTAssertEqual(error as? PowerSettingsError, .writeFailed) }
    }

    func testCancellationUsesLanguageIndependentMarker() async {
        let executor = StubExecutor([CommandResult(exitCode: 0, output: "QUIETLOCK_CANCELLED\n")])
        do {
            try await SystemPowerSettingsService(executor: executor, userName: "mac").apply(.fiveMinutes)
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? PowerSettingsError, .authorizationCancelled) }
    }

    func testNonzeroExitAndUnexpectedOutputCannotReportSuccess() async {
        for result in [CommandResult(exitCode: 1, output: "QUIETLOCK_OK"), CommandResult(exitCode: 0, output: "")] {
            do {
                try await SystemPowerSettingsService(executor: StubExecutor([result]), userName: "mac")
                    .apply(.fiveMinutes)
                XCTFail("Expected write failure")
            } catch { XCTAssertEqual(error as? PowerSettingsError, .writeFailed) }
        }
    }
}

private actor StubService: PowerSettingsServing {
    var reads: [Result<PowerSnapshot, PowerSettingsError>]
    let writeError: PowerSettingsError?
    let holdApply: Bool
    let holdReadAt: Int?
    var applied: [LockPreset] = []
    private var readCount = 0
    private var applyGate: CheckedContinuation<Void, Never>?
    private var applyWaiter: CheckedContinuation<Void, Never>?
    private var readGate: CheckedContinuation<Void, Never>?
    private var readWaiter: CheckedContinuation<Void, Never>?

    init(reads: [Result<PowerSnapshot, PowerSettingsError>], writeError: PowerSettingsError? = nil,
         holdApply: Bool = false, holdReadAt: Int? = nil) {
        self.reads = reads
        self.writeError = writeError
        self.holdApply = holdApply
        self.holdReadAt = holdReadAt
    }

    func read() async throws -> PowerSnapshot {
        readCount += 1
        let result = reads.removeFirst()
        if readCount == holdReadAt {
            await withCheckedContinuation { continuation in
                readGate = continuation
                readWaiter?.resume()
                readWaiter = nil
            }
        }
        return try result.get()
    }

    func apply(_ preset: LockPreset) async throws {
        applied.append(preset)
        if holdApply {
            await withCheckedContinuation { continuation in
                applyGate = continuation
                applyWaiter?.resume()
                applyWaiter = nil
            }
        }
        if let writeError { throw writeError }
    }

    func waitUntilApplyStarted() async {
        if applyGate != nil { return }
        await withCheckedContinuation { applyWaiter = $0 }
    }
    func releaseApply() { applyGate?.resume(); applyGate = nil }
    func waitUntilReadHeld() async {
        if readGate != nil { return }
        await withCheckedContinuation { readWaiter = $0 }
    }
    func releaseRead() { readGate?.resume(); readGate = nil }
    func writeCount() -> Int { applied.count }
}

@MainActor
private final class StubIdleSleepProtection: IdleSleepProtecting {
    var isActive = false
    var shouldFail = false
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func activate() throws {
        guard !isActive else { return }
        activationCount += 1
        if shouldFail { throw IdleSleepProtectionError.unavailable }
        isActive = true
    }

    func deactivate() {
        if isActive { deactivationCount += 1 }
        isActive = false
    }
}

@MainActor
final class PowerSettingsModelTests: XCTestCase {
    private func snapshot(_ minutes: Int) -> PowerSnapshot {
        PowerSnapshot(profiles: [PowerProfile(source: .adapter, minutes: minutes)])
    }

    func testConfirmedSuccess() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(5))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertEqual(model.snapshot?.preset, .fiveMinutes)
        XCTAssertEqual(model.feedback?.kind, .success)
        XCTAssertTrue(model.canAdjust)
        XCTAssertFalse(model.canRetry)
    }

    func testNoAuthorizationForAlreadySelectedValue() async {
        let service = StubService(reads: [.success(snapshot(10))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.tenMinutes)
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 0)
    }

    func testCancellationReReadsActualState() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(10))], writeError: .authorizationCancelled)
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertEqual(model.snapshot?.preset, .tenMinutes)
        XCTAssertEqual(model.feedback?.kind, .neutral)
        XCTAssertFalse(model.canRetry)
    }

    func testFailureDisplaysPartialChangesAndCanRetry() async {
        let mixed = PowerSnapshot(profiles: [PowerProfile(source: .battery, minutes: 5), PowerProfile(source: .adapter, minutes: 10)])
        let service = StubService(reads: [.success(snapshot(10)), .success(mixed)], writeError: .writeFailed)
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertEqual(model.snapshot, mixed)
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertTrue(model.canRetry)
    }

    func testReadbackMismatchIsAnError() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(15))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertEqual(model.snapshot?.preset, .fifteenMinutes)
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertTrue(model.canRetry)
    }

    func testWriteErrorWithDesiredActualValueDoesNotOfferANoopRetry() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(5))], writeError: .writeFailed)
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertEqual(model.snapshot?.preset, .fiveMinutes)
        XCTAssertEqual(model.feedback?.kind, .neutral)
        XCTAssertFalse(model.canRetry)
    }

    func testVerificationFailureRetriesReadWithoutAnotherAuthorization() async {
        let service = StubService(reads: [.success(snapshot(10)), .failure(.readFailed), .success(snapshot(5))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.apply(.fiveMinutes)
        XCTAssertFalse(model.isSnapshotCurrent)
        XCTAssertFalse(model.canAdjust)
        await model.retry()
        XCTAssertTrue(model.isSnapshotCurrent)
        XCTAssertEqual(model.snapshot?.preset, .fiveMinutes)
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 1)
    }

    func testInitialReadFailureCanRecover() async {
        let service = StubService(reads: [.failure(.readFailed), .success(snapshot(7))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        XCTAssertFalse(model.canAdjust)
        XCTAssertTrue(model.canRetry)
        await model.retry()
        XCTAssertTrue(model.canAdjust)
        XCTAssertEqual(model.snapshot?.uniformMinutes, 7)
        XCTAssertNil(model.snapshot?.preset)
    }

    func testDuplicateWritesAndRefreshAreIgnoredWhileAuthorizing() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(5))], holdApply: true)
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        let first = Task { await model.apply(.fiveMinutes) }
        await service.waitUntilApplyStarted()
        XCTAssertTrue(model.isApplying)
        XCTAssertFalse(model.canAdjust)
        await model.apply(.thirtyMinutes)
        await model.refresh()
        await service.releaseApply()
        await first.value
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(model.snapshot?.preset, .fiveMinutes)
    }

    func testLateRefreshCannotOverwriteConfirmedWrite() async {
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(30)), .success(snapshot(5))], holdReadAt: 2)
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        let staleRead = Task { await model.refresh() }
        await service.waitUntilReadHeld()
        await model.apply(.fiveMinutes)
        await service.releaseRead()
        await staleRead.value
        XCTAssertEqual(model.snapshot?.preset, .fiveMinutes)
        XCTAssertEqual(model.feedback?.kind, .success)
        XCTAssertFalse(model.isRefreshing)
    }

    func testNeverKeepsAwakeAndTimedPresetReleasesProtection() async {
        let protection = StubIdleSleepProtection()
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(0)), .success(snapshot(5))])
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        XCTAssertFalse(model.isKeepingAwake)
        await model.apply(.never)
        XCTAssertTrue(model.isKeepingAwake)
        XCTAssertEqual(protection.activationCount, 1)
        await model.apply(.fiveMinutes)
        XCTAssertFalse(protection.isActive)
        XCTAssertEqual(protection.deactivationCount, 1)
    }

    func testLaunchAdoptsNeverWithoutWritingAndShutdownReleases() async {
        let protection = StubIdleSleepProtection()
        let service = StubService(reads: [.success(snapshot(0)), .success(snapshot(0))])
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        await model.refreshInBackground()
        XCTAssertTrue(model.isKeepingAwake)
        XCTAssertEqual(protection.activationCount, 1)
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 0)
        model.stopKeepingAwake()
        XCTAssertFalse(protection.isActive)
        XCTAssertFalse(model.isKeepingAwake)
    }

    func testExternalChangeStopsProtectionAndShowsActualValueWithoutRewriting() async {
        let protection = StubIdleSleepProtection()
        let service = StubService(reads: [.success(snapshot(0)), .success(snapshot(10)), .success(snapshot(10))])
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        await model.refreshInBackground()
        XCTAssertFalse(model.isKeepingAwake)
        XCTAssertEqual(model.snapshot?.preset, .tenMinutes)
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertTrue(model.canRetry)
        await model.refreshInBackground()
        XCTAssertEqual(model.feedback?.kind, .error)
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 0)
    }

    func testOpeningPanelKeepsExternalChangeWarningDetectedInBackground() async {
        let service = StubService(reads: [.success(snapshot(0)), .success(snapshot(10)), .success(snapshot(10))])
        let model = PowerSettingsModel(service: service, protection: StubIdleSleepProtection())
        await model.refresh()
        await model.refreshInBackground()
        await model.refresh()
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertTrue(model.canRetry)
    }

    func testProtectionFailureCannotReportSuccessAndRetriesWithoutAuthorization() async {
        let protection = StubIdleSleepProtection()
        protection.shouldFail = true
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(0)), .success(snapshot(0))])
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        await model.apply(.never)
        XCTAssertEqual(model.feedback?.kind, .error)
        XCTAssertFalse(model.isKeepingAwake)
        XCTAssertTrue(model.canRetry)
        protection.shouldFail = false
        await model.retry()
        XCTAssertTrue(model.isKeepingAwake)
        XCTAssertFalse(model.canRetry)
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 1)
    }

    func testReadFailureKeepsExistingProtectionUntilConfirmedChange() async {
        let protection = StubIdleSleepProtection()
        let service = StubService(reads: [.success(snapshot(0)), .failure(.readFailed), .success(snapshot(10))])
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        await model.refreshInBackground()
        XCTAssertTrue(model.isKeepingAwake)
        XCTAssertFalse(model.isSnapshotCurrent)
        await model.refreshInBackground()
        XCTAssertFalse(model.isKeepingAwake)
        XCTAssertTrue(model.isSnapshotCurrent)
    }

    func testCancelledNeverSelectionDoesNotEnableProtection() async {
        let protection = StubIdleSleepProtection()
        let service = StubService(reads: [.success(snapshot(10)), .success(snapshot(10))], writeError: .authorizationCancelled)
        let model = PowerSettingsModel(service: service, protection: protection)
        await model.refresh()
        await model.apply(.never)
        XCTAssertFalse(model.isKeepingAwake)
        XCTAssertEqual(protection.activationCount, 0)
    }
}
