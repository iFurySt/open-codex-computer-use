import Foundation

/// Deterministic lease slots are scoped by bundle/socket identity. Live serials are never reused.
enum VirtualDisplayIdentity {
    static func serial(identity: String, slot: UInt32) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in (identity + ":" + String(slot)).utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash == 0 ? UInt32.max : hash
    }
    static func availableSerial(identity: String, occupied: Set<UInt32>) throws -> UInt32 {
        for slot in UInt32(0)..<256 {
            let candidate = serial(identity: identity, slot: slot)
            if !occupied.contains(candidate) { return candidate }
        }
        throw ComputerUseError.message("No unoccupied virtual display identity slot")
    }
}
