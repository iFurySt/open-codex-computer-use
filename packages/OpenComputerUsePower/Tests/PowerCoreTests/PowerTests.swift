import XCTest
@testable import PowerCore

final class FakeBackend: PowerBackend {
    var confirmed = PowerNeeds()
    var failApply = false, failRefresh = false
    var changes: [PowerNeeds] = []
    func apply(_ needs: PowerNeeds) throws {
        if failApply { throw PowerFailure.backend("apply failure") }
        confirmed = needs; changes.append(needs)
    }
    func refresh() throws { if failRefresh { throw PowerFailure.backend("helper restarted") } }
}
final class FakeSwitch: SleepSwitch {
    var disabled = false, failSet = false, failRead = false
    var writes: [Bool] = []
    func read() throws -> Bool { if failRead { throw PowerFailure.backend("read failure") }; return disabled }
    func set(_ value: Bool) throws {
        if failSet { throw PowerFailure.backend("write failure") }
        disabled = value; writes.append(value)
    }
}
final class FakeJournal: RecoveryJournal {
    var value: Bool?, failClear = false, failSave = false
    func load() throws -> Bool? { value }
    func save(original: Bool) throws { if failSave { throw PowerFailure.backend("journal failure") }; value = original }
    func clear() throws { if failClear { throw PowerFailure.backend("clear failure") }; value = nil }
}
final class PowerTests: XCTestCase {
    func testManualHoldSurvivesDisconnectAndHasNoDeadline() throws {
        var now = 0.0; let backend = FakeBackend()
        let r = PowerHoldRegistry(backend: backend, clock: { now })
        let hold = try r.acquire(.init(), uid: 501, connectionID: "a")
        r.disconnected("a"); now = 1e12; r.tick()
        XCTAssertEqual(try r.status(uid: 501, id: hold.id).holds.first?.phase, "active")
        XCTAssertTrue(backend.confirmed.idle)
    }
    func testAggregateReleasePreservesOtherOwners() throws {
        let backend = FakeBackend()
        let registry = PowerHoldRegistry(backend: backend)
        let first = try registry.acquire(.init(), uid: 501, connectionID: "a")
        var options = HoldOptions(); options.preventIdleSleep = false; options.preventDisplaySleep = true
        let second = try registry.acquire(options, uid: 502, connectionID: "b")
        XCTAssertThrowsError(try registry.release(first.id, uid: 502))
        try registry.release(first.id, uid: 501)
        XCTAssertEqual(backend.confirmed, .init(display: true))
        XCTAssertEqual(try registry.status(uid: 501).holds.count, 1)
        try registry.release(second.id, uid: 502)
        XCTAssertEqual(backend.confirmed, .init())
        try registry.release(second.id, uid: 502) // idempotent
    }
    func testTimedAndConnectionLifecycle() throws {
        var now = 1.0; let backend = FakeBackend(); let r = PowerHoldRegistry(backend: backend, clock: { now })
        var timed = HoldOptions(); timed.lifetime = .timed; timed.seconds = 10
        let h = try r.acquire(timed, uid: 1, connectionID: "timer")
        var connected = HoldOptions(); connected.lifetime = .connection
        let c = try r.acquire(connected, uid: 1, connectionID: "client")
        r.disconnected("timer"); now = 10.9; r.tick()
        XCTAssertEqual(try r.status(uid: 1, id: h.id).holds[0].phase, "active")
        now = 11; r.tick(); XCTAssertEqual(try r.status(uid: 1, id: h.id).holds[0].reason, "timeout")
        XCTAssertTrue(backend.confirmed.idle)
        r.disconnected("client"); XCTAssertEqual(try r.status(uid: 1, id: c.id).holds[0].reason, "connection_closed")
        XCTAssertFalse(backend.confirmed.idle)
    }
    func testCutoffsAreOptInAndPerHold() throws {
        let r = PowerHoldRegistry(backend: FakeBackend())
        let permanent = try r.acquire(.init(), uid: 1, connectionID: "a")
        var guarded = HoldOptions(); guarded.batteryFloorPercent = 20; guarded.stopOnSeriousThermalState = true
        let battery = try r.acquire(guarded, uid: 1, connectionID: "a")
        r.tick(environment: .init(batteryPercent: 10, onBattery: false))
        XCTAssertEqual(try r.status(uid: 1, id: battery.id).holds[0].phase, "active")
        r.tick(environment: .init(batteryPercent: 20, onBattery: true))
        XCTAssertEqual(try r.status(uid: 1, id: battery.id).holds[0].reason, "battery_floor")
        let thermal = try r.acquire(guarded, uid: 1, connectionID: "a")
        r.tick(environment: .init(seriousThermalState: true))
        XCTAssertEqual(try r.status(uid: 1, id: thermal.id).holds[0].reason, "thermal_cutoff")
        XCTAssertEqual(try r.status(uid: 1, id: permanent.id).holds[0].phase, "active")
    }
    func testFailedAcquireDoesNotPublishHold() throws {
        let backend = FakeBackend(); backend.failApply = true
        let r = PowerHoldRegistry(backend: backend)
        XCTAssertThrowsError(try r.acquire(.init(), uid: 1, connectionID: "a"))
        XCTAssertTrue(try r.status(uid: 1).holds.isEmpty)
    }
    func testLostHelperLeaseFailsLidHoldsOnly() throws {
        let backend = FakeBackend()
        let registry = PowerHoldRegistry(backend: backend)
        let ordinary = try registry.acquire(.init(), uid: 1, connectionID: "a")
        var lid = HoldOptions(); lid.preventLidSleep = true
        let h = try registry.acquire(lid, uid: 1, connectionID: "b")
        backend.failRefresh = true; registry.tick()
        XCTAssertEqual(try registry.status(uid: 1, id: h.id).holds[0].phase, "failed")
        XCTAssertEqual(try registry.status(uid: 1, id: ordinary.id).holds[0].phase, "active")
        XCTAssertEqual(backend.confirmed, .init(idle: true))
    }
    func testFailedRestorationRemainsVisibleAndRetries() throws {
        let backend = FakeBackend()
        let r = PowerHoldRegistry(backend: backend)
        let h = try r.acquire(.init(), uid: 1, connectionID: "a")
        backend.failApply = true; XCTAssertThrowsError(try r.release(h.id, uid: 1))
        XCTAssertNotNil(try r.status(uid: 1).backendError)
        XCTAssertTrue(backend.confirmed.idle)
        backend.failApply = false; r.tick()
        XCTAssertFalse(backend.confirmed.idle); XCTAssertNil(try r.status(uid: 1).backendError)
    }
    func testOptionValidationAndWireDefaults() throws {
        let defaultOptions = try JSONDecoder().decode(HoldOptions.self, from: Data("{}".utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(HoldOptions.self, from: Data("{\"prevent_lid_slep\":true}".utf8)))
        XCTAssertTrue(defaultOptions.preventIdleSleep); XCTAssertEqual(defaultOptions.lifetime, .manual)
        var invalid = HoldOptions(); invalid.preventIdleSleep = false
        XCTAssertThrowsError(try invalid.validate())
        invalid.preventLidSleep = true; invalid.lifetime = .timed
        for value in [-1.0, 0, Double.infinity, Double.nan] { invalid.seconds = value; XCTAssertThrowsError(try invalid.validate()) }
        invalid.seconds = 1; invalid.batteryFloorPercent = 0; XCTAssertThrowsError(try invalid.validate())
        invalid.batteryFloorPercent = 20; XCTAssertNoThrow(try invalid.validate())
    }
    func testRestartDoesNotRecreateManualHolds() throws {
        let b = FakeBackend(); let first = PowerHoldRegistry(backend: b)
        _ = try first.acquire(.init(), uid: 1, connectionID: "a"); try first.shutdown()
        let second = PowerHoldRegistry(backend: b)
        XCTAssertTrue(try second.status(uid: 1).holds.isEmpty); XCTAssertFalse(b.confirmed.idle)
    }
}
final class LidLeaseTests: XCTestCase {
    func testAcquireRenewExpireAndRestore() throws {
        var now = 0.0; let power = FakeSwitch(), journal = FakeJournal()
        let r = LidLeaseController(power: power, journal: journal, clock: { now })
        try r.recoverOnStartup()
        let acquired = r.handle(.init("acquire"), uid: 1, connection: "a")
        let token = try XCTUnwrap(acquired.lease)
        XCTAssertEqual(journal.value, false); XCTAssertTrue(power.disabled)
        now = 29; XCTAssertNil(r.handle(.init("renew", lease: token), uid: 1, connection: "a").error)
        now = 58; r.tick(); XCTAssertTrue(power.disabled)
        now = 59; r.tick(); XCTAssertFalse(power.disabled); XCTAssertNil(journal.value)
        XCTAssertNotNil(r.handle(.init("renew", lease: token), uid: 1, connection: "a").error)
    }
    func testLeaseIdentityAndDisconnectAggregation() throws {
        let power = FakeSwitch(), journal = FakeJournal()
        let controller = LidLeaseController(power: power, journal: journal)
        let a = try XCTUnwrap(controller.handle(.init("acquire"), uid: 1, connection: "a").lease)
        let b = try XCTUnwrap(controller.handle(.init("acquire"), uid: 2, connection: "b").lease)
        XCTAssertNotNil(controller.handle(.init("renew", lease: a), uid: 2, connection: "a").error)
        XCTAssertNotNil(controller.handle(.init("release", lease: a), uid: 1, connection: "b").error)
        _ = controller.handle(.init("disconnect"), uid: 1, connection: "a")
        XCTAssertTrue(power.disabled)
        XCTAssertNil(controller.handle(.init("release", lease: b), uid: 2, connection: "b").error)
        XCTAssertFalse(power.disabled)
    }
    func testExternalOwnerRefusedWithoutWrites() {
        let p = FakeSwitch(); p.disabled = true; let j = FakeJournal()
        let r = LidLeaseController(power: p, journal: j)
        XCTAssertNotNil(r.handle(.init("acquire"), uid: 1, connection: "a").error)
        XCTAssertTrue(p.writes.isEmpty); XCTAssertNil(j.value)
    }
    func testExternalChangeRevokesWithoutReassertion() throws {
        let p = FakeSwitch(), j = FakeJournal()
        let controller = LidLeaseController(power: p, journal: j)
        let token = try XCTUnwrap(controller.handle(.init("acquire"), uid: 1, connection: "a").lease)
        p.disabled = false
        XCTAssertNotNil(controller.handle(.init("renew", lease: token), uid: 1, connection: "a").error)
        XCTAssertEqual(p.writes, [true]); XCTAssertNil(j.value)
    }
    func testCrashJournalRecoveredAndOldTokenCannotRenew() throws {
        let p = FakeSwitch(), j = FakeJournal()
        let first = LidLeaseController(power: p, journal: j)
        let token = try XCTUnwrap(first.handle(.init("acquire"), uid: 1, connection: "a").lease)
        let second = LidLeaseController(power: p, journal: j)
        try second.recoverOnStartup()
        XCTAssertFalse(p.disabled); XCTAssertNil(j.value)
        XCTAssertNotNil(second.handle(.init("renew", lease: token), uid: 1, connection: "a").error)
    }
    func testJournalMustPersistBeforeMutation() {
        let p = FakeSwitch(), j = FakeJournal(); j.failSave = true
        let r = LidLeaseController(power: p, journal: j)
        XCTAssertNotNil(r.handle(.init("acquire"), uid: 1, connection: "a").error)
        XCTAssertTrue(p.writes.isEmpty)
    }
    func testRestoreFailureBlocksAcquireThenRetries() throws {
        let p = FakeSwitch(), j = FakeJournal()
        let r = LidLeaseController(power: p, journal: j)
        let token = try XCTUnwrap(r.handle(.init("acquire"), uid: 1, connection: "a").lease)
        p.failSet = true
        XCTAssertNotNil(r.handle(.init("release", lease: token), uid: 1, connection: "a").error)
        XCTAssertNotNil(r.handle(.init("acquire"), uid: 1, connection: "a").error)
        XCTAssertEqual(j.value, false)
        p.failSet = false; r.tick()
        XCTAssertFalse(p.disabled); XCTAssertNil(j.value)
        XCTAssertNotNil(r.handle(.init("acquire"), uid: 1, connection: "a").lease)
    }
    func testJournalClearFailureRetainsRecovery() throws {
        let p = FakeSwitch(), j = FakeJournal()
        let r = LidLeaseController(power: p, journal: j)
        let token = try XCTUnwrap(r.handle(.init("acquire"), uid: 1, connection: "a").lease)
        j.failClear = true; XCTAssertNotNil(r.handle(.init("release", lease: token), uid: 1, connection: "a").error)
        XCTAssertFalse(p.disabled); XCTAssertNotNil(j.value)
        j.failClear = false; r.tick(); XCTAssertNil(j.value)
    }
}

final class TransportTests: XCTestCase {
    func testPersistentSocketManualAndConnectionOwnership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("control.sock").path
        let backend = FakeBackend()
        let r = PowerHoldRegistry(backend: backend)
        let server = PowerSocketServer(registry: r, path: path)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var a: PowerClient? = try PowerClient(path: path)
        let manual = try XCTUnwrap(a?.acquire())
        var options = HoldOptions(); options.lifetime = .connection
        let connected = try XCTUnwrap(a?.acquire(options))
        let b = try PowerClient(path: path)
        XCTAssertEqual(try b.status().holds.count, 2)
        a = nil
        let until = ProcessInfo.processInfo.systemUptime + 2
        while try b.status(connected.id).holds[0].phase == "active", ProcessInfo.processInfo.systemUptime < until { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertEqual(try b.status(connected.id).holds[0].reason, "connection_closed")
        XCTAssertEqual(try b.status(manual.id).holds[0].phase, "active")
        try b.release(manual.id); XCTAssertFalse(try b.status().confirmed.idle)
        let duplicate = PowerSocketServer(registry: r, path: path)
        XCTAssertThrowsError(try duplicate.start())
        XCTAssertNoThrow(try b.status())
    }
    func testMalformedRequestDoesNotAcquirePower() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = PowerSocketServer(registry: PowerHoldRegistry(backend: FakeBackend()), path: dir.appendingPathComponent("s").path)
        try s.start(); defer { s.stop(); try? FileManager.default.removeItem(at: dir) }
        let c = try PowerClient(path: dir.appendingPathComponent("s").path)
        XCTAssertThrowsError(try c.request(.init("arbitrary-shell")))
        XCTAssertTrue(try c.status().holds.isEmpty)
    }
}
