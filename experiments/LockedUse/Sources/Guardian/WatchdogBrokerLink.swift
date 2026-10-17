import Foundation
import Darwin
import OpenComputerUseKit
import os

/// Root RPC runs on a separate queue. A wedged or restarting Broker cannot
/// delay the watchdog's inherited-pipe heartbeat deadline or native relock.
final class WatchdogBrokerLink: @unchecked Sendable {
    private let logger = Logger(subsystem: "dev.opencomputeruse.locked-use", category: "WatchdogBroker")
    private var reportedFailure = false
    private let mutex = NSLock()
    private let bootstrap: LockedUseGuardianBootstrap
    private var client: LockedUseIPCClient?
    private var timer: DispatchSourceTimer?
    private var witnessedUnlock = false
    private var release = false
    private var registered = false
    private var protected = false
    private var stopping = false
    private let queue = DispatchQueue(label: "ocu.watchdog.broker")

    init(bootstrap: LockedUseGuardianBootstrap, protected: Bool) {
        self.bootstrap = bootstrap; self.protected = protected
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(300))
        timer.setEventHandler { [weak self] in self?.report() }
        self.timer = timer; timer.resume()
    }
    func observe(_ session: LockedUseSession, protected: Bool, stopping: Bool) {
        mutex.lock(); defer { mutex.unlock() }
        if session.state == .unlocked { witnessedUnlock = true }
        self.protected = protected; self.stopping = stopping
    }
    var ready: Bool { mutex.lock(); defer { mutex.unlock() }; return registered }
    var releaseRequested: Bool { mutex.lock(); defer { mutex.unlock() }; return release }

    private func report() {
        do {
            mutex.lock(); let observed = witnessedUnlock; let protected = protected; let stopping = stopping; mutex.unlock()
            if client == nil {
                let candidate = try LockedUseIPCClient(endpoint: .guardian, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
                let recovery = try candidate.request(.init(operation: .watchdogRecoveryHello, leaseID: bootstrap.leaseID,
                    session: .current(), hasObservedUnlock: observed))
                if recovery.result == .denied {
                    let hello = try candidate.request(.init(operation: .watchdogHello, leaseID: bootstrap.leaseID, token: bootstrap.token))
                    guard hello.result != .denied else { candidate.close(); throw GuardianError.message("Watchdog registration denied") }
                }
                client = candidate
                logger.notice("registered")
            }
            let reply = try client!.request(.init(operation: .watchdogReport, leaseID: bootstrap.leaseID,
                session: .current(), guards: .init(allDisplaysCovered: protected, inputTapHealthy: protected,
                    watchdogHealthy: protected, displayGeneration: 1), stopReason: stopping ? .guardLost : nil,
                hasObservedUnlock: observed))
            guard reply.result != .denied else { throw GuardianError.message("Watchdog report denied") }
            mutex.lock(); registered = protected && !stopping; mutex.unlock()
            if reply.effects.contains("releaseWatchdog") { mutex.lock(); release = true; mutex.unlock() }
        } catch {
            if !reportedFailure { logger.error("registrationOrReportFailed error=\(String(describing: error), privacy: .public)"); reportedFailure = true }
            client?.close(); client = nil
            mutex.lock(); registered = false; mutex.unlock()
        }
    }
    func finish() {
        timer?.cancel(); timer = nil
        queue.sync {
            client?.close(); client = nil
            mutex.lock(); let observed = witnessedUnlock; mutex.unlock()
            _ = GuardReleaseAcknowledgement.send(bootstrap: bootstrap, watchdog: true, observedUnlock: observed)
        }
    }
}

func readGuardianBootstrap() throws -> LockedUseGuardianBootstrap {
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    func exact(_ size: Int) throws -> Data {
        var result = Data()
        while result.count < size {
            try LockedUseIPCSocket.wait(descriptor: STDIN_FILENO, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: min(4096, size - result.count))
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            guard count > 0 else { throw GuardianError.message("Guardian bootstrap pipe ended") }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
    let length = try exact(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard length > 0, length <= LockedUseIPCFrame.maximumPayload else { throw GuardianError.message("Invalid Guardian bootstrap size") }
    let value = try JSONDecoder().decode(LockedUseGuardianBootstrap.self, from: exact(Int(length)))
    guard value.token.count == 32 else { throw GuardianError.message("Invalid Guardian bootstrap token") }
    return value
}
