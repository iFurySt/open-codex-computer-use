import AppKit
import ApplicationServices
import Foundation
import OpenComputerUseKit

/// Isolated visual diagnostic. Never creates a permit, performs an AX action,
/// captures an application, or requests lock/unlock. Input cannot shorten the
/// countdown except Escape. This is not a production guardian policy.
@MainActor
final class ShieldPreview {
    private let shields = DisplayShieldSurface()
    private var timer: Timer?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var started: TimeInterval = 0
    private var lastSecond = -1
    private var inputCounts: [String: Int] = [:]
    private var firstInput: [String: Any] = [:]
    private var stopped = false
    private var ready = false
    private(set) var passed = false

    func start() throws {
        guard LockedUseSession.current().state == .unlocked,
              CGPreflightListenEventAccess() else {
            throw GuardianError.message("Shield preview requires an unlocked session and Input Monitoring")
        }
        try installTap()
        do {
            try shields.coverDisplays(message: message(seconds: 15))
            started = ProcessInfo.processInfo.systemUptime
            emit("previewStarted", details: ["displayCount": shields.count, "seconds": 15,
                "lockRequested": false, "unlockRequested": false, "actionsEnabled": false])
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            cleanup()
            throw error
        }
    }

    private func message(seconds: Int) -> String {
        "Open Computer Use · 遮罩预览\n剩余 \(seconds) 秒\n请观察每块物理屏幕 · Esc 提前退出\n本次不会锁屏或操作应用"
    }

    private func installTap() throws {
        let context = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(UInt32.max),
            callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let preview = Unmanaged<ShieldPreview>.fromOpaque(pointer).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        preview.finish(reason: "inputTapDisabled")
                        return
                    }
                    let key = String(type.rawValue)
                    preview.inputCounts[key, default: 0] += 1
                    if preview.firstInput.isEmpty {
                        preview.firstInput = ["type": type.rawValue,
                            "sourcePID": event.getIntegerValueField(.eventSourceUnixProcessID),
                            "sourceState": event.getIntegerValueField(.eventSourceStateID),
                            "elapsed": ProcessInfo.processInfo.systemUptime - preview.started]
                    }
                    // Read only the Escape exit key; no text/key data is logged.
                    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                        preview.finish(reason: "escape")
                    }
                }
                return nil
            }, userInfo: context)
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw GuardianError.message("Cannot create shield preview input tap")
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func poll() {
        guard !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let coverage = shields.coverageHealthy()
        let tapHealthy = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        guard tapHealthy, LockedUseSession.current().state == .unlocked else {
            finish(reason: "sessionOrInputTapChanged")
            return
        }
        if !ready {
            if coverage {
                ready = true
                // Begin the visible countdown only after WindowServer coverage.
                started = now
                emit("previewReady", details: ["displayCount": shields.count, "coverageHealthy": true])
            } else if now - started >= 1.5 {
                finish(reason: "coverageNotReady")
            }
            return
        }
        guard coverage else { finish(reason: "coverageChanged"); return }
        let elapsed = now - started
        let remaining = max(0, Int(ceil(15 - elapsed)))
        if remaining != lastSecond {
            lastSecond = remaining
            shields.updateMessage(message(seconds: remaining))
            emit("previewTick", details: ["remainingSeconds": remaining, "elapsed": elapsed,
                "coverageHealthy": coverage, "displayCount": shields.count,
                "inputCounts": inputCounts, "firstInput": firstInput])
            inputCounts.removeAll()
        }
        if elapsed >= 15 { passed = true; finish(reason: "completed") }
    }

    private func finish(reason: String) {
        guard !stopped else { return }
        stopped = true
        emit("previewFinished", details: ["reason": reason, "passed": passed,
            "elapsed": ProcessInfo.processInfo.systemUptime - started,
            "lockRequested": false, "unlockRequested": false])
        cleanup()
        let app = NSApplication.shared
        app.stop(nil)
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0) { app.postEvent(event, atStart: true) }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        shields.close()
    }
}
