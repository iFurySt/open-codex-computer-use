import CoreGraphics
import Foundation
import OpenComputerUseKit
import os

func recordLockUIClickAdmission(filter: String, type: CGEventType) {
    let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "LockUIClickFilter")
    let button = type == .leftMouseDown ? "down" : "up"
    logger.notice("clickAdmitted filter=\(filter, privacy: .public) type=\(button, privacy: .public)")
}

extension LockedUseClickAllowance {
    mutating func accepts(_ event: CGEvent, type: CGEventType, filter: String) -> Bool {
        let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "LockUIClickFilter")
        func reject(_ reason: String) -> Bool {
            logger.notice("clickRejected filter=\(filter, privacy: .public) reason=\(reason, privacy: .public)")
            return false
        }
        guard type == .leftMouseDown || type == .leftMouseUp else { return reject("type") }
        // Quartz adds non-keyboard flags during delivery. Only modifiers that
        // change a left click's semantics are prohibited; metadata flags and
        // Caps Lock cannot turn this capability into a keyboard event.
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        logger.notice("clickFlags raw=\(event.flags.rawValue, privacy: .public) modifiers=\(event.flags.intersection(modifiers).rawValue, privacy: .public)")
        guard event.flags.intersection(modifiers).isEmpty else { return reject("flags") }
        guard event.getIntegerValueField(.mouseEventWindowUnderMousePointer) ==
                event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) else { return reject("window") }
        let accepted = accept(button: type == .leftMouseDown ? .down : .up,
            tag: event.getIntegerValueField(.eventSourceUserData),
            sender: Int32(clamping: event.getIntegerValueField(.eventSourceUnixProcessID)),
            target: Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID)),
            window: event.getIntegerValueField(.mouseEventWindowUnderMousePointer),
            x: event.location.x, y: event.location.y,
            now: ProcessInfo.processInfo.systemUptime, locked: LockedUseSession.current().state == .locked)
        return accepted ? true : reject(rejection?.rawValue ?? "inactive")
    }
}
