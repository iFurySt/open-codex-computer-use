import Foundation
import OpenComputerUseKit
import IOKit.pwr_mgt

/// Independently owned by both guards; powerd releases it on process death or
/// at the maximum lease duration. It does not authenticate or unlock a user.
final class DisplayPowerAssertion {
    private var identifier: IOPMAssertionID = 0

    init() throws {
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionNameKey: "Open Computer Use display protection",
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionTimeoutKey: LockedUseStateMachine.maximumLease,
            kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
        ]
        guard IOPMAssertionCreateWithProperties(properties as CFDictionary, &identifier) == kIOReturnSuccess else {
            throw GuardianError.message("Display sleep protection unavailable")
        }
    }

    func close() {
        if identifier != 0 { _ = IOPMAssertionRelease(identifier); identifier = 0 }
    }

    deinit { close() }
}
