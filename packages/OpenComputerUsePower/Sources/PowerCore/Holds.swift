import Foundation

struct AnyPowerKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
func rejectUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: AnyPowerKey.self)
    let unexpected = Set(container.allKeys.map(\.stringValue)).subtracting(allowed)
    guard unexpected.isEmpty else { throw PowerFailure.invalid("Unknown option keys: " + unexpected.sorted().joined(separator: ", ")) }
}

public enum PowerFailure: Error, LocalizedError {
    case invalid(String), backend(String)
    public var errorDescription: String? { switch self { case .invalid(let s), .backend(let s): return s } }
}
public enum HoldLifetime: String, Codable { case manual, timed, connection }
public struct HoldOptions: Codable, Equatable {
    public var preventIdleSleep = true
    public var preventDisplaySleep = false
    public var preventLidSleep = false
    public var lifetime: HoldLifetime = .manual
    public var seconds: Double?
    public var batteryFloorPercent: Int?
    public var stopOnSeriousThermalState = false
    public init() {}
    public func validate() throws {
        guard preventIdleSleep || preventDisplaySleep || preventLidSleep else { throw PowerFailure.invalid("Enable at least one power capability") }
        if lifetime == .timed {
            guard let seconds, seconds.isFinite, seconds > 0 else { throw PowerFailure.invalid("Timed holds require finite positive seconds") }
        } else if seconds != nil { throw PowerFailure.invalid("seconds is only valid for timed holds") }
        if let floor = batteryFloorPercent, !(1...100).contains(floor) { throw PowerFailure.invalid("battery_floor_percent must be 1...100") }
    }
    enum CodingKeys: String, CodingKey {
        case preventIdleSleep = "prevent_idle_sleep", preventDisplaySleep = "prevent_display_sleep", preventLidSleep = "prevent_lid_sleep", lifetime, seconds
        case batteryFloorPercent = "battery_floor_percent", stopOnSeriousThermalState = "stop_on_serious_thermal_state"
    }
    public init(from decoder: Decoder) throws {
        self.init()
        try rejectUnknownKeys(decoder, allowed: Set(["prevent_idle_sleep", "prevent_display_sleep", "prevent_lid_sleep", "lifetime", "seconds", "battery_floor_percent", "stop_on_serious_thermal_state"]))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preventIdleSleep = try c.decodeIfPresent(Bool.self, forKey: .preventIdleSleep) ?? true
        preventDisplaySleep = try c.decodeIfPresent(Bool.self, forKey: .preventDisplaySleep) ?? false
        preventLidSleep = try c.decodeIfPresent(Bool.self, forKey: .preventLidSleep) ?? false
        lifetime = try c.decodeIfPresent(HoldLifetime.self, forKey: .lifetime) ?? .manual
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds)
        batteryFloorPercent = try c.decodeIfPresent(Int.self, forKey: .batteryFloorPercent)
        stopOnSeriousThermalState = try c.decodeIfPresent(Bool.self, forKey: .stopOnSeriousThermalState) ?? false
    }
}
public struct PowerNeeds: Codable, Equatable {
    public var idle = false, display = false, lid = false
    public init(idle: Bool = false, display: Bool = false, lid: Bool = false) { self.idle = idle; self.display = display; self.lid = lid }
    public static func aggregate(_ holds: [PowerHold]) -> Self {
        holds.filter { $0.phase == "active" }.reduce(Self()) { value, hold in
            Self(idle: value.idle || hold.options.preventIdleSleep, display: value.display || hold.options.preventDisplaySleep, lid: value.lid || hold.options.preventLidSleep)
        }
    }
}
public struct PowerHold: Codable {
    public let id: String
    public let uid: UInt32
    public let connectionID: String
    public let options: HoldOptions
    public let createdAt: Date
    public var phase: String
    public var reason: String?
    // Monotonic timer is never restored on restart.
    var deadline: Double?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); uid = try c.decode(UInt32.self, forKey: .uid)
        options = try c.decode(HoldOptions.self, forKey: .options); createdAt = try c.decode(Date.self, forKey: .createdAt)
        phase = try c.decode(String.self, forKey: .phase); reason = try c.decodeIfPresent(String.self, forKey: .reason)
        connectionID = ""; deadline = nil
    }
    init(id: String, uid: UInt32, connectionID: String, options: HoldOptions, createdAt: Date, phase: String, reason: String?, deadline: Double?) {
        self.id = id; self.uid = uid; self.connectionID = connectionID; self.options = options; self.createdAt = createdAt
        self.phase = phase; self.reason = reason; self.deadline = deadline
    }
    enum CodingKeys: String, CodingKey { case id, uid, options, createdAt = "created_at", phase, reason }
}
public struct PowerStatus: Codable {
    public let holds: [PowerHold]
    public let requested: PowerNeeds
    public let confirmed: PowerNeeds
    public let backendError: String?
    public let lidStateKnown: Bool
    enum CodingKeys: String, CodingKey { case holds, requested, confirmed, backendError = "backend_error", lidStateKnown = "lid_state_known" }
}
public struct PowerEnvironment {
    public var batteryPercent: Int?
    public var onBattery: Bool
    public var seriousThermalState: Bool
    public init(batteryPercent: Int? = nil, onBattery: Bool = false, seriousThermalState: Bool = false) {
        self.batteryPercent = batteryPercent; self.onBattery = onBattery; self.seriousThermalState = seriousThermalState
    }
}
public protocol PowerBackend: AnyObject {
    var confirmed: PowerNeeds { get }
    var lidStateKnown: Bool { get }
    func apply(_ needs: PowerNeeds) throws
    func refresh() throws
}
public extension PowerBackend { var lidStateKnown: Bool { true } }
public final class PowerHoldRegistry {
    private let lock = NSRecursiveLock()
    private let backend: PowerBackend
    private let clock: () -> Double
    private var holds: [PowerHold] = []
    private var lastError: String?
    public init(backend: PowerBackend, clock: @escaping () -> Double = { PowerClock.now }) {
        self.backend = backend; self.clock = clock
    }
    public func acquire(_ options: HoldOptions, uid: UInt32, connectionID: String) throws -> PowerHold {
        lock.lock(); defer { lock.unlock() }
        try options.validate()
        guard holds.filter({ $0.phase == "active" }).count < 1024 else { throw PowerFailure.invalid("Active hold limit reached") }
        let hold = PowerHold(id: UUID().uuidString, uid: uid, connectionID: connectionID, options: options,
                             createdAt: Date(), phase: "active", reason: nil,
                             deadline: options.seconds.map { clock() + $0 })
        do { try backend.apply(.aggregate(holds + [hold])); lastError = nil }
        catch { lastError = error.localizedDescription; throw error }
        holds.append(hold); prune()
        return hold
    }
    public func release(_ id: String, uid: UInt32) throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = holds.firstIndex(where: { $0.id == id && $0.uid == uid }) else { throw PowerFailure.invalid("Unknown hold for this user") }
        if holds[index].phase == "active" { holds[index].phase = "ended"; holds[index].reason = "released" }
        try reconcile()
    }
    public func disconnected(_ connectionID: String) {
        lock.lock(); defer { lock.unlock() }
        for i in holds.indices where holds[i].phase == "active" && holds[i].connectionID == connectionID && holds[i].options.lifetime == .connection {
            holds[i].phase = "ended"; holds[i].reason = "connection_closed"
        }
        try? reconcile()
    }
    public func tick(environment: PowerEnvironment = .init()) {
        lock.lock(); defer { lock.unlock() }
        for i in holds.indices where holds[i].phase == "active" {
            let h = holds[i]
            let reason: String?
            if let deadline = h.deadline, clock() >= deadline { reason = "timeout" }
            else if let floor = h.options.batteryFloorPercent, environment.onBattery, let percent = environment.batteryPercent, percent <= floor { reason = "battery_floor" }
            else if h.options.stopOnSeriousThermalState && environment.seriousThermalState { reason = "thermal_cutoff" }
            else { reason = nil }
            if let reason { holds[i].phase = "ended"; holds[i].reason = reason }
        }
        do { try backend.refresh(); try reconcile() }
        catch {
            lastError = error.localizedDescription
            // A failed lid lease cannot be silently reacquired after a helper restart or conflict.
            for i in holds.indices where holds[i].phase == "active" && holds[i].options.preventLidSleep {
                holds[i].phase = "failed"; holds[i].reason = error.localizedDescription
            }
            try? backend.apply(.aggregate(holds))
        }
        prune()
    }
    public func status(uid: UInt32, id: String? = nil) throws -> PowerStatus {
        lock.lock(); defer { lock.unlock() }
        let visible = holds.filter { $0.uid == uid && (id == nil || $0.id == id) }
        if id != nil && visible.isEmpty { throw PowerFailure.invalid("Unknown hold for this user") }
        return PowerStatus(holds: visible, requested: .aggregate(visible), confirmed: backend.confirmed, backendError: lastError, lidStateKnown: backend.lidStateKnown)
    }
    public func shutdown() throws {
        lock.lock(); defer { lock.unlock() }
        for i in holds.indices where holds[i].phase == "active" { holds[i].phase = "ended"; holds[i].reason = "coordinator_stopped" }
        try reconcile()
    }
    private func reconcile() throws {
        do { try backend.apply(.aggregate(holds)); lastError = nil }
        catch { lastError = error.localizedDescription; throw error }
    }
    private func prune() {
        let terminal = holds.filter { $0.phase != "active" }.suffix(256)
        holds = holds.filter { $0.phase == "active" } + terminal
    }
}
