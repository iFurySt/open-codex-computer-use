import ApplicationServices
import Foundation
import IOKit.hid

/// Supplement the filtering CG tap with hardware activity detection. No HID
/// values, key usages, text, device names or serial numbers are read or logged.
/// Secure Event Input delivery must be validated on the target OS before the
/// Broker's production validation stamp may be written.
@MainActor
final class PhysicalInputMonitor {
    private var manager: IOHIDManager?
    private let activity: @MainActor () -> Void
    private let failure: @MainActor () -> Void
    private(set) var healthy = false

    init(activity: @escaping @MainActor () -> Void, failure: @escaping @MainActor () -> Void) {
        self.activity = activity; self.failure = failure
    }

    func start() throws {
        guard CGPreflightListenEventAccess() else { throw GuardianError.message("Input Monitoring missing") }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { pointer, result, _, _ in
            guard let pointer else { return }
            MainActor.assumeIsolated {
                let observer = Unmanaged<PhysicalInputMonitor>.fromOpaque(pointer).takeUnretainedValue()
                if result == kIOReturnSuccess { observer.activity() }
                else { observer.healthy = false; observer.failure() }
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { pointer, _, _, _ in
            guard let pointer else { return }
            MainActor.assumeIsolated {
                let observer = Unmanaged<PhysicalInputMonitor>.fromOpaque(pointer).takeUnretainedValue()
                observer.healthy = false; observer.failure()
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = manager
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager), CFSetGetCount(devices) > 0 else {
            stop(); throw GuardianError.message("Hardware input activity monitor unavailable")
        }
        healthy = true
    }

    func stop() {
        healthy = false
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            _ = IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }
}
