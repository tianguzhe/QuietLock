import Foundation
import IOKit.pwr_mgt

@MainActor
public protocol IdleSleepProtecting: AnyObject {
    var isActive: Bool { get }
    func activate() throws
    func deactivate()
}

/// This assertion prevents idle display sleep and, as documented by IOKit,
/// idle system sleep. It neither synthesizes input nor bypasses explicit locks.
@MainActor
public final class SystemIdleSleepProtection: IdleSleepProtecting {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isActive: Bool { assertionID != nil }

    public func activate() throws {
        guard assertionID == nil else { return }
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "QuietLock · 永不闲置熄屏" as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { throw IdleSleepProtectionError.unavailable }
        assertionID = identifier
    }

    public func deactivate() {
        guard let identifier = assertionID else { return }
        IOPMAssertionRelease(identifier)
        assertionID = nil
    }

    deinit {
        if let assertionID { IOPMAssertionRelease(assertionID) }
    }
}

public enum IdleSleepProtectionError: Error {
    case unavailable
}
