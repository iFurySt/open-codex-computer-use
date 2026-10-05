import XCTest
import PowerCore

final class MetricsTests: XCTestCase {
    final class Collector: MetricsCollector {
        var count = 0
        func collect() -> MetricsSample { count += 1; return .init(timestamp: 100, uptime: 1, readings: ["test": .init(3, unit: "W", source: "test")]) }
    }
    func testBatterySignAndInvalidValues() {
        XCTAssertEqual(NativeMetricsCollector.batteryWatts(voltageMV: 12000, currentMA: -2000), -24)
        XCTAssertEqual(NativeMetricsCollector.batteryWatts(voltageMV: 12000, currentMA: 2000), 24)
        XCTAssertEqual(NativeMetricsCollector.batteryWatts(voltageMV: 12000, currentMA: Int64(UInt32(bitPattern: -2000))), -24)
        XCTAssertNil(NativeMetricsCollector.batteryWatts(voltageMV: nil, currentMA: 0))
        XCTAssertNil(NativeMetricsCollector.batteryWatts(voltageMV: 12000, currentMA: Int64.min))
        XCTAssertNil(NativeMetricsCollector.batteryWatts(voltageMV: .nan, currentMA: 0))
        let reading = MetricReading(nil, unit: "W", source: "test")
        XCTAssertNil(reading.value); XCTAssertEqual(reading.quality, "unavailable")
    }
    func testRetentionQueryOrderingAndRollback() throws {
        let store = try MetricsStore(path: ":memory:")
        for time in [80.0, 95, 100] { try store.append(.init(timestamp: time), now: time, retention: 60) }
        try store.prune(now: 150, retention: 60)
        let result = try store.query(.init(limit: 1))
        XCTAssertEqual(result.samples.map(\.timestamp), [100]); XCTAssertTrue(result.truncated)
        XCTAssertEqual(try store.query(.init(since: 90, until: 97)).samples.map(\.timestamp), [95])
        try store.prune(now: 94, retention: 60) // clock rollback discards future rows
        XCTAssertEqual(try store.query(.init()).samples.map(\.timestamp), [95])
        try store.clear(); XCTAssertTrue(try store.query(.init()).samples.isEmpty)
    }
    func testConfigurationPersistsAndStartupPrunes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("metrics.db").path
        do {
            let store = try MetricsStore(path: path)
            try store.configure(.init(enabled: false, intervalSeconds: 10, retentionSeconds: 60), now: 100)
            try store.append(.init(timestamp: 100), now: 100, retention: 60)
        }
        let reopened = try MetricsStore(path: path)
        XCTAssertFalse(try reopened.configuration().enabled)
        XCTAssertEqual(try reopened.configuration().interval_seconds, 10)
        let service = try MetricsService(store: reopened, wall: { 200 })
        XCTAssertTrue(try service.query().samples.isEmpty)
    }
    func testSchedulingDisableAndReenable() throws {
        let collector = Collector(), store = try MetricsStore(path: ":memory:")
        var clock = 0.0
        let service = try MetricsService(store: store, collector: collector, clock: { clock }, wall: { 100 })
        service.tick(status: nil); service.tick(status: nil)
        XCTAssertEqual(collector.count, 1)
        clock = 5; service.tick(status: nil); XCTAssertEqual(collector.count, 2)
        try service.configure(.init(enabled: false))
        clock = 10; service.tick(status: nil); XCTAssertEqual(collector.count, 2)
        XCTAssertEqual(try service.query().samples.count, 2)
        try service.clear(); XCTAssertTrue(try service.query().samples.isEmpty)
        try service.configure(.init()); service.tick(status: nil); XCTAssertEqual(collector.count, 3)
    }
    func testBoundsAndSampleLimit() throws {
        XCTAssertThrowsError(try MetricsConfiguration(intervalSeconds: 0).validate())
        XCTAssertThrowsError(try MetricsConfiguration(retentionSeconds: .infinity).validate())
        XCTAssertThrowsError(try MetricsQuery(limit: 101).validate())
        XCTAssertThrowsError(try MetricsQuery(since: 5, until: 4).validate())
        let store = try MetricsStore(path: ":memory:")
        for i in 0..<10005 { try store.append(.init(timestamp: Double(i)), now: Double(i), retention: 86400) }
        let result = try store.query(.init(limit: 100))
        XCTAssertEqual(result.samples.count, 100); XCTAssertTrue(result.truncated)
        XCTAssertTrue(try store.query(.init(until: 4)).samples.isEmpty)
        XCTAssertEqual(try store.query(.init(until: 5)).samples.count, 1)
    }
    func testUnsafeStorePathRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let victim = directory.appendingPathComponent("victim"); try Data().write(to: victim)
        let link = directory.appendingPathComponent("metrics.db")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        XCTAssertThrowsError(try MetricsStore(path: link.path))
    }
}

extension MetricsTests {
    func testSamplingFaultVisibleAndNextTickRecovers() throws {
        final class InvalidCollector: MetricsCollector {
            var oversized = true
            func collect() -> MetricsSample {
                .init(timestamp: 100, readings: ["test": .init(2, unit: "W", source: oversized ? String(repeating: "x", count: 9000) : "test")])
            }
        }
        let collector = InvalidCollector(), store = try MetricsStore(path: ":memory:")
        var clock = 0.0
        let service = try MetricsService(store: store, collector: collector, clock: { clock }, wall: { 100 })
        service.tick(status: nil)
        XCTAssertNotNil(try service.query().collection_error)
        XCTAssertTrue(try service.query().samples.isEmpty)
        collector.oversized = false; clock = 5; service.tick(status: nil)
        XCTAssertNil(try service.query().collection_error)
        XCTAssertEqual(try service.query().samples.count, 1)
    }
    func testWireQueryDefaultsAndRejectsTypos() throws {
        XCTAssertEqual(try JSONDecoder().decode(MetricsQuery.self, from: Data("{}".utf8)).limit, 100)
        XCTAssertThrowsError(try JSONDecoder().decode(MetricsQuery.self, from: Data("{\"limt\":1}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(MetricsConfiguration.self, from: Data("{\"enabled\":false}".utf8)))
    }
}

extension MetricsTests {
    func testMetricsIPCAndHoldIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("s").path
        let registry = PowerHoldRegistry(backend: FakeBackend())
        let service = try MetricsService(store: MetricsStore(path: ":memory:"), collector: Collector(), wall: { 100 })
        let server = PowerSocketServer(registry: registry, path: path)
        server.metricsService = service
        try server.start(); defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let client = try PowerClient(path: path)
        let hold = try client.acquire()
        service.tick(status: try client.status())
        XCTAssertEqual(try client.metrics().samples.first?.active_holds, 1)
        XCTAssertTrue(try client.metrics().samples.first?.confirmed.idle == true)
        XCTAssertFalse(try client.configureMetrics(.init(enabled: false)).configuration.enabled)
        try client.clearMetrics(); XCTAssertTrue(try client.metrics().samples.isEmpty)
        XCTAssertTrue(try client.status().confirmed.idle)
        try client.release(hold.id)
    }
    func testMetricsStartupFailureDoesNotBreakHolds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = directory.appendingPathComponent("s").path
        let server = PowerSocketServer(registry: PowerHoldRegistry(backend: FakeBackend()), path: path)
        server.metricsError = "Metrics initialization failed"
        try server.start(); defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let client = try PowerClient(path: path)
        XCTAssertThrowsError(try client.metrics())
        let hold = try client.acquire(); XCTAssertTrue(try client.status().confirmed.idle)
        try client.release(hold.id); XCTAssertFalse(try client.status().confirmed.idle)
    }
}
