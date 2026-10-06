import AppKit
import Foundation
import OpenComputerUseKit

/// Reuses the signed UI probe, without constructing DisplayGuardian, a shield,
/// an input tap, hardware monitor, or a watchdog. Never runs application tools.
@MainActor
func runUnshieldedUnlockDiagnostic() throws {
    let original = LockedUseSession.current()
    let lock = ScreenLock()
    guard original.state == .locked, lock.available else { throw GuardianError.message("Diagnostic requires the locked original session and a relock backend") }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let client = try LockedUseIPCClient(endpoint: .guardian, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
    defer { client.close() }
    let begin = try client.request(.init(operation: .beginUnshieldedDiagnostic, session: original))
    guard begin.result != .denied, begin.detail == "unshieldedDiagnostic",
          let lease = begin.leaseID, let deadline = begin.startupDeadline,
          deadline.isFinite, deadline > ProcessInfo.processInfo.systemUptime,
          deadline - ProcessInfo.processInfo.systemUptime <= 20 else { throw GuardianError.message("Root rejected unshielded diagnostic") }
    let cancellation = UnlockCancellation()
    defer { cancellation.cancel() }
    emit("unshieldedDiagnosticStarted", details: ["shieldProcesses": 0, "inputFilters": 0, "maximumSeconds": 20, "productionEvidenceEligible": false])
    var observedUnlock = false
    var consumedPermit = false
    var relockRequested = false
    func sameOriginal(_ current: LockedUseSession) -> Bool {
        current.userID == original.userID && current.auditSessionID == original.auditSessionID
    }
    defer {
        let current = LockedUseSession.current()
        if sameOriginal(current), current.state == .unlocked, !relockRequested { lock.request() }
    }
    _ = LockScreenInteractor.wake(session: original, cancellation: cancellation, ui: LockUIObservation(),
        clickTag: Int64.random(in: 1...Int64.max), validationConfirmation: true, unshieldedReturn: true)
    while ProcessInfo.processInfo.systemUptime < deadline {
        let current = LockedUseSession.current()
        guard sameOriginal(current) else { throw GuardianError.message("Diagnostic session changed") }
        let reply = try client.request(.init(operation: .status, leaseID: lease, session: current))
        guard reply.result != .denied else { throw GuardianError.message("Root diagnostic polling denied") }
        consumedPermit = consumedPermit || reply.result == .authorized
        if current.state == .unlocked {
            observedUnlock = true
            emit("unshieldedUnlockObserved", details: ["permitConsumed": consumedPermit, "guiActionsPerformed": false])
            break
        }
        if reply.phase == .awaitingManualUnlock { break }
        Thread.sleep(forTimeInterval: 0.2)
    }
    cancellation.cancel()
    guard sameOriginal(.current()) else { throw GuardianError.message("Diagnostic session changed before relock") }
    lock.request(); relockRequested = true
    let drainDeadline = ProcessInfo.processInfo.systemUptime + 5
    while LockedUseSession.current().state != .locked, ProcessInfo.processInfo.systemUptime < drainDeadline {
        Thread.sleep(forTimeInterval: 0.1)
    }
    let current = LockedUseSession.current()
    guard sameOriginal(current), current.state == .locked else { throw GuardianError.message("Diagnostic relock not observed") }
    let end = try client.request(.init(operation: .endUnshieldedDiagnostic, leaseID: lease, session: current))
    guard end.result != .denied, end.phase == .idle else { throw GuardianError.message("Diagnostic end not acknowledged") }
    emit("unshieldedDiagnosticEnded", details: ["unlockObserved": observedUnlock, "permitConsumed": consumedPermit,
        "relockObserved": true, "guiActionsPerformed": false, "productionEvidenceEligible": false])
}
