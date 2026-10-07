import Darwin
import Foundation

/// App-agent requests are serialized across the process. This scope follows
/// synchronous dispatch onto AppKit's main thread as well as capture workers;
/// it cannot be selected from MCP arguments or environment variables.
public enum LockedUseActionScope {
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var validator: (@Sendable () throws -> Void)?
    }
    private static let storage = Storage()

    public static func withValidator<T>(_ validator: @escaping @Sendable () throws -> Void,
                                        body: () throws -> T) rethrows -> T {
        storage.lock.lock()
        precondition(storage.validator == nil, "GUI request dispatch must be serialized")
        storage.validator = validator
        storage.lock.unlock()
        defer {
            storage.lock.lock(); storage.validator = nil; storage.lock.unlock()
        }
        return try body()
    }

    static func validate() throws {
        storage.lock.lock(); let validator = storage.validator; storage.lock.unlock()
        if let validator { try validator() }
        else if FileManager.default.fileExists(atPath: LockedUseIPCEndpoint.observer.path) {
            // An unscoped caller must not use a desktop temporarily unlocked
            // for another client. Refuse on unavailable or untrusted Broker.
            let observer = try LockedUseIPCClient(endpoint: .observer,
                brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
            defer { observer.close() }
            let status = try observer.request(.init(operation: .status))
            guard status.phase == .idle || status.phase == .awaitingManualUnlock else {
                throw ComputerUseError.stateUnavailable("Locked Use belongs to another connection; GUI access is unavailable.")
            }
        }
    }
}
