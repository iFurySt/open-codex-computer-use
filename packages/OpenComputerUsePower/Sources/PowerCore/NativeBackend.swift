import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import PowerNative

public struct HelperRequest: Codable {
    public var operation: String
    public var lease: String?
    public init(_ operation: String, lease: String? = nil) { self.operation = operation; self.lease = lease }
}
public struct HelperResponse: Codable {
    public var lease: String?
    public var sleepDisabled: Bool?
    public var error: String?
    public init(lease: String? = nil, sleepDisabled: Bool? = nil, error: String? = nil) {
        self.lease = lease; self.sleepDisabled = sleepDisabled; self.error = error
    }
}
public func callPowerHelper(_ request: HelperRequest) throws -> HelperResponse {
    let data = try JSONEncoder().encode(request)
    guard let text = String(data: data, encoding: .utf8), let ptr = ocu_power_helper_request(text) else { throw PowerFailure.backend("No helper response") }
    defer { ocu_power_free(ptr) }
    let response = try JSONDecoder().decode(HelperResponse.self, from: Data(String(cString: ptr).utf8))
    if let error = response.error { throw PowerFailure.backend(error) }
    return response
}
public final class NativePowerBackend: PowerBackend {
    private var idleID: IOPMAssertionID = 0, displayID: IOPMAssertionID = 0
    private var lease: String?
    public private(set) var lidStateKnown = true
    private var nextRenewal = 0.0
    public var confirmed: PowerNeeds { .init(idle: idleID != 0, display: displayID != 0, lid: lease != nil) }
    public init() {}
    deinit { if idleID != 0 { IOPMAssertionRelease(idleID) }; if displayID != 0 { IOPMAssertionRelease(displayID) } }
    private func create(_ type: CFString) throws -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Open Computer Use explicit power hold" as CFString, &id)
        guard result == kIOReturnSuccess else { throw PowerFailure.backend("IOKit assertion failed: \(result)") }
        return id
    }
    public func apply(_ needs: PowerNeeds) throws {
        // Create new ordinary assertions before modifying existing ones.
        var newIdle: IOPMAssertionID = 0, newDisplay: IOPMAssertionID = 0
        do {
            if needs.idle && idleID == 0 { newIdle = try create(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString) }
            if needs.display && displayID == 0 { newDisplay = try create(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString) }
            if needs.lid && lease == nil {
                let response = try callPowerHelper(.init("acquire"))
                guard let token = response.lease, response.sleepDisabled == true else { throw PowerFailure.backend("Helper did not confirm lid sleep override") }
                lease = token; lidStateKnown = true; nextRenewal = PowerClock.now + 5
            } else if !needs.lid, let token = lease {
                _ = try callPowerHelper(.init("release", lease: token)); lease = nil; lidStateKnown = true
            }
        } catch {
            if newIdle != 0 { IOPMAssertionRelease(newIdle) }
            if newDisplay != 0 { IOPMAssertionRelease(newDisplay) }
            if needs.lid || lease != nil { lidStateKnown = false }
            throw error
        }
        if newIdle != 0 { idleID = newIdle }
        if newDisplay != 0 { displayID = newDisplay }
        if !needs.idle && idleID != 0 { let r = IOPMAssertionRelease(idleID); if r == kIOReturnSuccess { idleID = 0 } else { throw PowerFailure.backend("Idle assertion release failed: \(r)") } }
        if !needs.display && displayID != 0 { let r = IOPMAssertionRelease(displayID); if r == kIOReturnSuccess { displayID = 0 } else { throw PowerFailure.backend("Display assertion release failed: \(r)") } }
    }
    public func refresh() throws {
        for id in [idleID, displayID] where id != 0 {
            let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any]
            if (properties?[kIOPMAssertionLevelKey] as? NSNumber)?.intValue != kIOPMAssertionLevelOn {
                _ = IOPMAssertionRelease(id)
                if idleID == id { idleID = 0 }
                if displayID == id { displayID = 0 }
            }
        }
        if lease == nil && !lidStateKnown {
            if let state = try? callPowerHelper(.init("status")), state.sleepDisabled == false { lidStateKnown = true }
            return
        }
        guard let token = lease, PowerClock.now >= nextRenewal else { return }
        do {
            let response = try callPowerHelper(.init("renew", lease: token))
            guard response.sleepDisabled == true else { throw PowerFailure.backend("Lid override is no longer active") }
            nextRenewal = PowerClock.now + 5
        } catch { lease = nil; lidStateKnown = false; throw error }
    }
    public static func environment() -> PowerEnvironment {
        var result = PowerEnvironment(seriousThermalState: ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical)
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                result.onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
                if let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 { result.batteryPercent = current * 100 / maximum }
            }
        }
        return result
    }
}
