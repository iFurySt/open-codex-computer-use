import AppKit
import ApplicationServices
import OpenComputerUseKit

/// Independent windows and filtering input tap survive the main Guardian's
/// death. Keep them until the Broker's original-session drain/lock barrier.
@MainActor
final class WatchdogShield {
    private let surface = DisplayShieldSurface()
    private var displayPower: DisplayPowerAssertion?
    private var monitor: PhysicalInputMonitor?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clickAllowance: LockedUseClickAllowance?
    private var returnAllowance: LockedUseReturnAllowance?
    private(set) var localRecoveryRequested = false
    private var localRecoveryEnabled = false
    private let startupDeadline: TimeInterval?
    private var shieldStatus = LockedUseShieldStatus()
    private let stop: @MainActor (String) -> Void

    init(clickTag: Int64? = nil, returnTag: Int64? = nil, startupDeadline: TimeInterval? = nil, stop: @escaping @MainActor (String) -> Void) throws {
        self.stop = stop
        self.startupDeadline = startupDeadline
        if let returnTag { returnAllowance = .init(tag: returnTag, sender: getppid(), session: LockedUseSession.current(), now: ProcessInfo.processInfo.systemUptime) }
        if let clickTag { clickAllowance = .init(tag: clickTag, sender: getppid(), now: ProcessInfo.processInfo.systemUptime) }
        NSApplication.shared.setActivationPolicy(.accessory)
        let message = shieldStatus.update(now: ProcessInfo.processInfo.systemUptime,
            startupDeadline: startupDeadline, unlocked: false, stopping: false)!
        try surface.coverDisplays(message: message, levelOffset: -1)
        do {
            displayPower = try DisplayPowerAssertion()
            let context = Unmanaged.passUnretained(self).toOpaque()
            let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyDown, .keyUp, .flagsChanged,
                .scrollWheel, .tabletPointer, .tabletProximity, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
            let mask = types.reduce(CGEventMask(1) << 14) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
                    if let pointer {
                        let admitted = MainActor.assumeIsolated { () -> Bool in
                            let shield = Unmanaged<WatchdogShield>.fromOpaque(pointer).takeUnretainedValue()
                            if shield.localRecoveryEnabled { return true }
                            if shield.returnAllowance?.accepts(event, type: type, filter: "watchdog") == true { return true }
                            if shield.clickAllowance?.accepts(event, type: type, filter: "watchdog") == true {
                                recordLockUIClickAdmission(filter: "watchdog", type: type)
                                return true
                            }
                            shield.cancelNativeClick()
                            shield.stop("filterEvent")
                            return false
                        }
                        if admitted { return Unmanaged.passUnretained(event) }
                    }
                    return nil
                }, userInfo: context)
            guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                throw GuardianError.message("Independent watchdog input filter unavailable")
            }
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let monitor = PhysicalInputMonitor(activity: { [weak self] in
                self?.localRecoveryRequested = true
                self?.cancelNativeClick(); stop("hardwareActivity")
            },
                failure: { [weak self] in self?.cancelNativeClick(); stop("hardwareMonitorFailure") })
            self.monitor = monitor
            try monitor.start()
        } catch { close(); throw error }
    }

    var healthFailure: String? {
        if let failure = surface.coverageFailure() { return failure }
        if monitor?.healthy != true { return "hardwareMonitorUnhealthy" }
        if tap.map({ CGEvent.tapIsEnabled(tap: $0) }) != true { return "filterDisabled" }
        return nil
    }
    var healthy: Bool {
        healthFailure == nil
    }
    func close() {
        cancelNativeClick()
        monitor?.stop(); monitor = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil; tap = nil; surface.close()
        displayPower?.close(); displayPower = nil
    }
    func allowLocalLoginInput() {
        localRecoveryEnabled = true
        surface.allowLocalLoginInput()
    }
    func cancelNativeClick() { clickAllowance?.revoke(); returnAllowance?.revoke() }
    func updateStatus(now: TimeInterval, session: LockedUseSession, stopping: Bool) {
        if let message = shieldStatus.update(now: now, startupDeadline: startupDeadline,
            unlocked: session.state == .unlocked, stopping: stopping) {
            surface.updateMessage(message)
        }
    }
}
