import Foundation

/// Expensive first-peer signature checks must not run on the Broker queue that
/// handles guard heartbeats, revocation and recovery. Admission stays with the
/// caller, which must keep the socket alive until verification completes.
public final class LockedUsePeerAuthenticator: @unchecked Sendable {
    private let workers: OperationQueue

    public init() {
        workers = OperationQueue()
        workers.name = "ocu.locked-use.peer-verification"
        workers.maxConcurrentOperationCount = 4
        workers.qualityOfService = .userInitiated
    }

    public func verify<T: Sendable>(
        _ check: @escaping @Sendable () throws -> T,
        completion: @escaping @Sendable (Result<T, Error>) -> Void
    ) {
        workers.addOperation { completion(Result { try check() }) }
    }
}
