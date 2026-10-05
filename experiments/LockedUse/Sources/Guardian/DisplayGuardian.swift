import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation
import OpenComputerUseKit
@preconcurrency import ScreenCaptureKit

private final class FixtureActionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    func close() { lock.lock(); closed = true; lock.unlock() }
    func allowsAction() -> Bool { lock.lock(); defer { lock.unlock() }; return !closed }
}

/// Live rehearsal adapter. This does not grant production permits or unlock.
/// The root Broker must eventually own action cancellation/quiescence. Here
/// only the controlled fixture performs actions; no unlock requests exist.
@MainActor
final class DisplayGuardian: NSObject {
    private var policy: LockedUseGuardianPolicy
    private let lock = ScreenLock()
    private let shields = DisplayShieldSurface()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var timer: Timer?
    private var watchdog: Process?
    private var watchdogInput: FileHandle?
    private var watchdogOutput: FileHandle?
    private var watchdogReader: HeartbeatPipe?
    private var watchdogReady = false
    private var lastWatchdogHeartbeat: TimeInterval
    private var started: TimeInterval
    private var lastReport: TimeInterval = 0
    private var topology = ""
    private var stopping = false
    private var fixtureWindow: NSWindow?
    private var fixtureCounter = 0
    private var fixtureLabel: NSTextField?
    private var fixtureVerificationStarted = false
    private let injectWatchdogStall: Bool
    private var watchdogRelockSeen = false
    private var stallResumedLocked = false
    private(set) var watchdogTestPassed = false
    private(set) var fixtureAXSelfTestPassed = false
    private let fixtureGate = FixtureActionGate()

    init(session: LockedUseSession, injectWatchdogStall: Bool = false) throws {
        guard session.state == .unlocked else { throw GuardianError.message("Rehearsal starts in a manually unlocked user session") }
        started = ProcessInfo.processInfo.systemUptime
        lastWatchdogHeartbeat = started
        policy = try .init(session: session, now: started, lifetime: 15)
        self.injectWatchdogStall = injectWatchdogStall
        policy.confirmQuiescence()
        super.init()
    }

    func start() throws {
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else {
            throw GuardianError.message("Grant Accessibility and Input Monitoring to the Guardian app before rehearsal")
        }
        guard lock.available, !IsSecureEventInputEnabled() else {
            throw GuardianError.message("Relock unavailable or Secure Event Input active")
        }
        try installTap()
        do {
            createCaptureFixture()
            try coverDisplays()
            try startWatchdog()
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            emit("preparing", details: ["displayCount": shields.count, "seconds": 15,
                "unlockRequested": false, "productionReady": false])
        } catch {
            // Preparation can fail before a live test is armed. No unlocking is
            // possible here; dispose only resources that actually exist.
            cleanup()
            throw error
        }
    }

    private func createCaptureFixture() {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 420, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Locked Use Capture Fixture"
        window.backgroundColor = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1)
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Counter: 0")
        label.frame = NSRect(x: 40, y: 120, width: 300, height: 40)
        label.textColor = .white
        let button = NSButton(title: "Increment", target: self, action: #selector(incrementFixture))
        button.setAccessibilityIdentifier("ocu.locked-use.rehearsal.increment")
        button.frame = NSRect(x: 40, y: 50, width: 160, height: 40)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(button)
        fixtureLabel = label
        fixtureWindow = window
        window.orderFrontRegardless()
    }

    @objc private func incrementFixture() {
        fixtureCounter += 1
        fixtureLabel?.stringValue = "Counter: \(fixtureCounter)"
    }

    func runFixtureAXSelfTest() throws {
        createCaptureFixture()
        defer { fixtureWindow?.close(); fixtureWindow = nil }
        guard performFixtureAXPress(), fixtureCounter == 1 else {
            throw GuardianError.message("MainActor same-process AX fixture did not change")
        }
        fixtureAXSelfTestPassed = true
        emit("fixtureAXSelfTest", details: ["passed": true, "counter": fixtureCounter, "lockRequested": false])
    }

    private func performFixtureAXPress() -> Bool {
        let root = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(root, 0.2)
        var remaining = 100
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 12, remaining > 0 else { return nil }
            remaining -= 1
            var identifier: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
            if identifier as? String == "ocu.locked-use.rehearsal.increment" { return element }
            for attribute in [kAXWindowsAttribute, kAXChildrenAttribute] {
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &children) == .success {
                    for child in children as? [AXUIElement] ?? [] {
                        if let match = find(child, depth: depth + 1) { return match }
                    }
                }
            }
            return nil
        }
        return find(root, depth: 0).map {
            fixtureGate.allowsAction() && AXUIElementPerformAction($0, kAXPressAction as CFString) == .success
        } ?? false
    }

    private func verifyCaptureFixture() async {
        guard policy.phase == .shielding else { return }
        policy.requireQuiescence()
        defer { policy.confirmQuiescence() }
        guard CGPreflightScreenCaptureAccess(), let fixtureWindow else {
            emit("captureVerification", details: ["passed": false, "reason": "screenRecordingUnavailable"])
            return
        }
        do {
            emit("captureStage", details: ["stage": "shareableContent"])
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == CGWindowID(fixtureWindow.windowNumber) }),
                  window.owningApplication?.processID == getpid() else {
                throw GuardianError.message("Fixture SCWindow unavailable")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.width = 420
            configuration.height = 262
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            emit("captureStage", details: ["stage": "beforeImage"])
            let before = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let pixels = NSBitmapImageRep(cgImage: before)
            guard let sample = pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)?.usingColorSpace(.sRGB),
                  sample.blueComponent > 0.5, sample.blueComponent > sample.redComponent * 2 else {
                throw GuardianError.message("Covered fixture capture did not contain the expected blue background")
            }
            guard policy.phase == .shielding else { throw GuardianError.message("Rehearsal stopped before action") }
            emit("captureStage", details: ["stage": "axPress"])
            // Same-process AX invokes AppKit directly on the caller's thread.
            // This fixture therefore performs AXPress on MainActor. Dispatching
            // to a background queue violates its AppKit/Swift actor isolation.
            let pressed = performFixtureAXPress()
            guard policy.phase == .shielding, pressed, fixtureCounter == 1 else {
                throw GuardianError.message("AXPress did not change the controlled fixture counter")
            }
            fixtureWindow.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let after = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let changed = NSBitmapImageRep(cgImage: before).representation(using: .png, properties: [:])
                != NSBitmapImageRep(cgImage: after).representation(using: .png, properties: [:])
            emit("captureVerification", details: ["passed": changed, "axCounterChanged": true,
                "windowCaptureChanged": changed, "coveredFixtureVisible": true])
            if changed, injectWatchdogStall, policy.phase == .shielding {
                emit("faultInjected", details: ["kind": "guardianMainLoopStall", "seconds": 5,
                    "lockRequestedByGuardian": false])
                // Development-only fault injection: keep the existing windows
                // alive while stopping the UI loop and its outgoing heartbeat.
                stallMainLoopForWatchdogTest()
                let resumedSession = LockedUseSession.current()
                stallResumedLocked = resumedSession.state == .locked
                emit("faultResumed", details: ["session": resumedSession.state.rawValue])
            }
        } catch {
            emit("captureVerification", details: ["passed": false, "reason": String(describing: error)])
        }
    }

    private func installTap() throws {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyDown, .keyUp, .flagsChanged,
            .scrollWheel, .tabletPointer, .tabletProximity, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        // NX_SYSDEFINED (14) includes media/power keys; no keystrokes are logged.
        let mask = types.reduce(CGEventMask(1) << 14) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let guardian = Unmanaged<DisplayGuardian>.fromOpaque(pointer).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        emit("inputTapDisabled", details: ["kind": type == .tapDisabledByTimeout ? "timeout" : "userInput",
                            "phase": guardian.policy.phase.rawValue])
                        guardian.stop(.guardianFailure)
                        return
                    }
                    // No synthetic events are exempted on the global stream.
                    // Default OCU postToPid does not traverse this tap. Global
                    // input during Locked Use must remain disallowed.
                    if guardian.policy.phase != .relocking {
                        emit("inputTakeover", details: ["type": type.rawValue,
                            "sourcePID": event.getIntegerValueField(.eventSourceUnixProcessID),
                            "sourceState": event.getIntegerValueField(.eventSourceStateID),
                            "phase": guardian.policy.phase.rawValue])
                        guardian.stop(.localInput)
                    }
                }
                return nil
            }, userInfo: context)
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw GuardianError.message("Cannot create a filtering event tap")
        }
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // Intentionally synchronous: Task.sleep would keep servicing the run loop
    // and heartbeats, so it would not simulate a stuck Guardian.
    private func stallMainLoopForWatchdogTest() {
        Thread.sleep(forTimeInterval: 5)
    }

    private func displayTopology() -> String { shields.displayTopology() }
    private func coverDisplays() throws {
        try shields.coverDisplays(message: "Open Computer Use · 测试中\n移动鼠标或按键将重新锁屏")
        topology = displayTopology()
    }
    private func coverageHealthy() -> Bool { shields.coverageHealthy() }

    private func startWatchdog() throws {
        let process = Process()
        process.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--watchdog"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        watchdog = process
        watchdogInput = input.fileHandleForWriting
        watchdogOutput = output.fileHandleForReading
        watchdogReader = HeartbeatPipe(output.fileHandleForReading.fileDescriptor)
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        let bytes = watchdogReader?.drain(allowed: [72, 82, 83]) ?? []
        if bytes.contains(83) {
            watchdogRelockSeen = true
            emit("watchdogRelockReported", details: ["lockConfirmed": false])
        }
        if bytes.contains(82) { watchdogReady = true }
        if !bytes.isEmpty { lastWatchdogHeartbeat = now }
        let watchdogHealthy = watchdogReady && watchdog?.isRunning == true && watchdogReader?.failed == false && now - lastWatchdogHeartbeat < 1.5
        if let watchdogInput, !HeartbeatPipe.send(72, to: watchdogInput.fileDescriptor) { stop(.parentDisconnected) }
        do {
            if policy.phase == .preparing {
                // Initial AppKit drawing and child launch can take a few frames.
                if now - started >= 1.5 { stop(.guardianFailure) }
                else if watchdogHealthy, coverageHealthy(), let tap, CGEvent.tapIsEnabled(tap: tap) {
                    try policy.prepared(topology: topology, now: now)
                    emit("shieldReady", details: ["displayCount": shields.count, "guardianPID": getpid(),
                        "watchdogPID": watchdog?.processIdentifier ?? 0, "backendValidated": false])
                    if !fixtureVerificationStarted {
                        fixtureVerificationStarted = true
                        Task { await self.verifyCaptureFixture() }
                    }
                }
            }
            if watchdogHealthy { execute(try policy.heartbeat(now: now)) }
            let current = LockedUseSession.current()
            let tapHealthy = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
            // Secure input is expected at loginwindow after relock. Prior to
            // stopping it is a coverage gap and must stop the rehearsal.
            let coverageFailure = shields.coverageFailure()
            let coverage = coverageFailure == nil
            let secureInput = IsSecureEventInputEnabled()
            let healthy = watchdogHealthy && tapHealthy && coverage && !secureInput
            if !healthy, policy.phase == .shielding {
                emit("guardHealthFailure", details: ["watchdogHealthy": watchdogHealthy,
                    "watchdogRunning": watchdog?.isRunning == true,
                    "watchdogPipeFailed": watchdogReader?.failed ?? true,
                    "watchdogHeartbeatAge": now - lastWatchdogHeartbeat,
                    "inputTapEnabled": tapHealthy, "coverageHealthy": coverage,
                    "coverageFailure": coverageFailure ?? "",
                    "topologyUnchanged": displayTopology() == topology, "secureInput": secureInput])
            }
            if policy.phase != .preparing {
                execute(try policy.poll(session: current, topology: displayTopology(), guardsHealthy: healthy, now: now))
            }
            if now - lastReport >= 1 {
                lastReport = now
                if policy.phase == .shielding {
                    let remaining = max(0, Int(ceil(15 - (now - started))))
                    shields.updateMessage("Open Computer Use · 遮罩期间操作测试\n剩余 \(remaining) 秒\n结束后将锁屏 · 请保持鼠标键盘不动")
                }
                emit("guardianState", details: ["phase": policy.phase.rawValue, "session": current.state.rawValue,
                    "reason": policy.reason?.rawValue ?? "", "inputTapEnabled": tapHealthy,
                    "watchdogHealthy": watchdogHealthy, "elapsed": now - started])
            }
        } catch { stop(.guardianFailure) }
    }

    private func stop(_ reason: LockedUseGuardianPolicy.Reason) {
        fixtureGate.close()
        if !stopping { stopping = true; emit("stopping", details: ["reason": reason.rawValue]) }
        execute(policy.stop(reason, now: ProcessInfo.processInfo.systemUptime))
    }

    private func execute(_ effects: [LockedUseGuardianPolicy.Effect]) {
        for effect in effects {
            switch effect {
            case .requestRelock:
                fixtureGate.close()
                if !stopping {
                    stopping = true
                    emit("stopping", details: ["reason": policy.reason?.rawValue ?? "", "elapsed": ProcessInfo.processInfo.systemUptime - started])
                }
                lock.request()
            case .releaseShield:
                if injectWatchdogStall {
                    watchdogTestPassed = stallResumedLocked && watchdogRelockSeen
                    emit("watchdogTestResult", details: ["passed": watchdogTestPassed,
                        "lockedBeforeGuardianResumed": stallResumedLocked,
                        "independentRelockReported": watchdogRelockSeen])
                }
                if let watchdogInput { _ = HeartbeatPipe.send(76, to: watchdogInput.fileDescriptor) }
                emit("lockConfirmed", details: ["shieldReleased": true, "unlockRequested": false])
                cleanup()
                NSApplication.shared.stop(nil)
                // Wake an AppKit run loop which may currently have no events.
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                    NSApplication.shared.postEvent(event, atStart: true)
                }
            }
        }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tapSource = nil
        tap = nil
        shields.close()
        fixtureWindow?.close()
        fixtureWindow = nil
        watchdogInput?.closeFile()
        watchdogOutput?.closeFile()
    }
}
