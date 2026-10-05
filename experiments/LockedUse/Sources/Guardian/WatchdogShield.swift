import AppKit
import ApplicationServices
import OpenComputerUseKit

/// Independent windows and filtering input tap survive the main Guardian's
/// death. Keep them until the Broker's original-session drain/lock barrier.
@MainActor
final class WatchdogShield {
    private let surface = DisplayShieldSurface()
    private var monitor: PhysicalInputMonitor?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let stop: @MainActor () -> Void

    init(stop: @escaping @MainActor () -> Void) throws {
        self.stop = stop
        NSApplication.shared.setActivationPolicy(.accessory)
        try surface.coverDisplays(message: "Open Computer Use 正在使用电脑\n移动鼠标或按键可返回锁屏", levelOffset: -1)
        do {
            let context = Unmanaged.passUnretained(self).toOpaque()
            let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyDown, .keyUp, .flagsChanged,
                .scrollWheel, .tabletPointer, .tabletProximity, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
            let mask = types.reduce(CGEventMask(1) << 14) { $0 | (CGEventMask(1) << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, _, _, pointer in
                    if let pointer {
                        MainActor.assumeIsolated {
                            Unmanaged<WatchdogShield>.fromOpaque(pointer).takeUnretainedValue().stop()
                        }
                    }
                    return nil
                }, userInfo: context)
            guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                throw GuardianError.message("Independent watchdog input filter unavailable")
            }
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            let monitor = PhysicalInputMonitor(activity: stop, failure: stop)
            self.monitor = monitor
            try monitor.start()
        } catch { close(); throw error }
    }

    var healthy: Bool {
        surface.coverageHealthy() && monitor?.healthy == true && tap.map { CGEvent.tapIsEnabled(tap: $0) } == true
    }
    func close() {
        monitor?.stop(); monitor = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil; tap = nil; surface.close()
    }
}
