import Foundation
import IOKit
import PowerNative

public struct MetricReading: Codable, Equatable {
    public let value: Double?
    public let unit: String
    public let source: String
    public let quality: String
    public let unavailable_reason: String?
    public init(_ value: Double?, unit: String, source: String, quality: String = "reported_sensor", reason: String? = nil) {
        self.value = value?.isFinite == true ? value : nil
        self.unit = unit; self.source = source; self.quality = self.value == nil ? "unavailable" : quality
        unavailable_reason = self.value == nil ? reason ?? "sensor_missing_or_invalid" : nil
    }
}
public struct MetricsSample: Codable, Equatable {
    public let timestamp: Double
    public let uptime_seconds: Double
    public var readings: [String: MetricReading]
    public var thermal_state: String
    public var on_battery: Bool?
    public var charging: Bool?
    public var lid_closed: Bool?
    public var active_holds: Int
    public var requested: PowerNeeds
    public var confirmed: PowerNeeds
    public var lid_state_known: Bool
    public init(timestamp: Double = Date().timeIntervalSince1970, uptime: Double = PowerClock.now, readings: [String: MetricReading] = [:], thermal: String = "unknown", onBattery: Bool? = nil, charging: Bool? = nil, lidClosed: Bool? = nil, activeHolds: Int = 0, requested: PowerNeeds = .init(), confirmed: PowerNeeds = .init(), lidStateKnown: Bool = true) {
        self.timestamp = timestamp; uptime_seconds = uptime; self.readings = readings
        thermal_state = thermal; on_battery = onBattery; self.charging = charging; lid_closed = lidClosed
        active_holds = activeHolds; self.requested = requested; self.confirmed = confirmed; lid_state_known = lidStateKnown
    }
}
public struct MetricsConfiguration: Codable, Equatable {
    public var enabled: Bool
    public var interval_seconds: Double
    public var retention_seconds: Double
    public init(enabled: Bool = true, intervalSeconds: Double = 5, retentionSeconds: Double = 3600) {
        self.enabled = enabled; interval_seconds = intervalSeconds; retention_seconds = retentionSeconds
    }
    enum CodingKeys: String, CodingKey { case enabled, interval_seconds, retention_seconds }
    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["enabled", "interval_seconds", "retention_seconds"])
        let box = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try box.decode(Bool.self, forKey: .enabled)
        interval_seconds = try box.decode(Double.self, forKey: .interval_seconds)
        retention_seconds = try box.decode(Double.self, forKey: .retention_seconds)
    }
    public func validate() throws {
        guard interval_seconds.isFinite, (1...300).contains(interval_seconds), retention_seconds.isFinite, (60...86400).contains(retention_seconds) else {
            throw PowerFailure.invalid("Metrics interval must be 1...300 seconds; retention must be 60...86400 seconds")
        }
    }
}
public struct MetricsQuery: Codable {
    public var since: Double?
    public var until: Double?
    public var limit: Int
    public init(since: Double? = nil, until: Double? = nil, limit: Int = 100) { self.since = since; self.until = until; self.limit = limit }
    enum CodingKeys: String, CodingKey { case since, until, limit }
    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["since", "until", "limit"])
        let box = try decoder.container(keyedBy: CodingKeys.self)
        since = try box.decodeIfPresent(Double.self, forKey: .since); until = try box.decodeIfPresent(Double.self, forKey: .until)
        limit = try box.decodeIfPresent(Int.self, forKey: .limit) ?? 100
    }
    public func validate() throws {
        guard (1...100).contains(limit), since?.isFinite != false, until?.isFinite != false, since == nil || until == nil || since! <= until! else { throw PowerFailure.invalid("Metrics query requires finite epoch bounds, since <= until and limit 1...100") }
    }
}
public struct MetricsReport: Codable {
    public let configuration: MetricsConfiguration
    public let samples: [MetricsSample]
    public let truncated: Bool
    public let max_samples: Int
    public let collection_error: String?
    public let sensor_freshness: String
    public init(configuration: MetricsConfiguration, samples: [MetricsSample], truncated: Bool = false, error: String? = nil) {
        self.configuration = configuration; self.samples = samples; self.truncated = truncated
        max_samples = 10000; collection_error = error; sensor_freshness = "sample_time_is_read_time; hardware_refresh_interval_unknown"
    }
}
public protocol MetricsCollector { func collect() -> MetricsSample }
public struct NativeMetricsCollector: MetricsCollector {
    public init() {}
    private func properties(_ name: String) -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != 0 else { return [:] }; defer { IOObjectRelease(service) }
        var data: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &data, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return data?.takeRetainedValue() as? [String: Any] ?? [:]
    }
    // Apple publishes signed amperage in an OSNumber; old implementations expose
    // the signed 32-bit value through an unsigned container.
    public static func batteryWatts(voltageMV: Double?, currentMA: Int64?) -> Double? {
        guard let voltageMV, voltageMV.isFinite, voltageMV > 0, voltageMV < 100000, let raw = currentMA else { return nil }
        let current = raw >= 0 && raw <= Int64(UInt32.max) ? Int64(Int32(bitPattern: UInt32(raw))) : raw
        guard current > -100000, current < 100000 else { return nil }
        return voltageMV * Double(current) / 1_000_000
    }
    public func collect() -> MetricsSample {
        let battery = properties("AppleSmartBattery"), root = properties("IOPMrootDomain")
        let voltage = (battery["Voltage"] as? NSNumber)?.doubleValue
        let current = (battery["Amperage"] as? NSNumber)?.int64Value
        var system = 0.0
        let available = ocu_power_system_watts(&system) == 0
        var readings = [
            "system_power_watts": MetricReading(available ? system : nil, unit: "W", source: "AppleSMC.PSTR", reason: "PSTR_missing_unsupported_or_denied"),
            "battery_net_power_watts": MetricReading(Self.batteryWatts(voltageMV: voltage, currentMA: current), unit: "W", source: "AppleSmartBattery.Voltage*Amperage", quality: "derived_sensor"),
            "battery_voltage_volts": MetricReading(voltage.map { $0 / 1000 }, unit: "V", source: "AppleSmartBattery.Voltage")
        ]
        let environment = NativePowerBackend.environment()
        readings["battery_percent"] = MetricReading(environment.batteryPercent.map(Double.init), unit: "%", source: "IOPowerSources", quality: "reported_state")
        let rawTemp = (battery["Temperature"] as? NSNumber)?.doubleValue
        let celsius = rawTemp.map { $0 / 10 - 273.15 }
        readings["battery_temperature_celsius"] = MetricReading(celsius.flatMap { (-40...100).contains($0) ? $0 : nil }, unit: "C", source: "AppleSmartBattery.Temperature")
        let state: String
        switch ProcessInfo.processInfo.thermalState { case .nominal: state = "nominal"; case .fair: state = "fair"; case .serious: state = "serious"; case .critical: state = "critical"; @unknown default: state = "unknown" }
        return MetricsSample(readings: readings, thermal: state, onBattery: (battery["ExternalConnected"] as? Bool).map { !$0 }, charging: battery["IsCharging"] as? Bool, lidClosed: root["AppleClamshellState"] as? Bool)
    }
}

// A separate queue calls tick. Metrics never renews a hold or asserts wakefulness.
public final class MetricsService {
    private let lock = NSRecursiveLock()
    private let store: MetricsStore
    private let collector: MetricsCollector
    private let clock: () -> Double
    private let wall: () -> Double
    private var next = 0.0
    private var nextPrune = 0.0
    private var configuration: MetricsConfiguration
    private var fault: String?
    public init(store: MetricsStore, collector: MetricsCollector = NativeMetricsCollector(), clock: @escaping () -> Double = { PowerClock.now }, wall: @escaping () -> Double = { Date().timeIntervalSince1970 }) throws {
        self.store = store; self.collector = collector; self.clock = clock; self.wall = wall
        configuration = try store.configuration(); try store.prune(now: wall(), retention: configuration.retention_seconds)
    }
    public func configure(_ value: MetricsConfiguration) throws {
        try value.validate(); lock.lock(); defer { lock.unlock() }
        try store.configure(value, now: wall()); configuration = value; next = 0; fault = nil
    }
    public func clear() throws { lock.lock(); defer { lock.unlock() }; try store.clear(); fault = nil }
    public func tick(status: PowerStatus?) {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        if now >= nextPrune {
            nextPrune = now + 60
            do { try store.prune(now: wall(), retention: configuration.retention_seconds) } catch { fault = error.localizedDescription }
        }
        guard configuration.enabled, now >= next else { return }
        next = now + configuration.interval_seconds
        var sample = collector.collect()
        sample.readings["collection_duration_seconds"] = MetricReading(max(0, clock() - now), unit: "s", source: "coordinator.monotonic_clock", quality: "measured_interval")
        if let status {
            sample.active_holds = status.holds.filter { $0.phase == "active" }.count
            sample.requested = status.requested; sample.confirmed = status.confirmed; sample.lid_state_known = status.lidStateKnown
        }
        do { try store.append(sample, now: wall(), retention: configuration.retention_seconds); fault = nil }
        catch { fault = error.localizedDescription }
    }
    public func query(_ query: MetricsQuery = .init()) throws -> MetricsReport {
        lock.lock(); defer { lock.unlock() }
        try query.validate(); try store.prune(now: wall(), retention: configuration.retention_seconds)
        let result = try store.query(query)
        return .init(configuration: configuration, samples: result.samples, truncated: result.truncated, error: fault)
    }
}
