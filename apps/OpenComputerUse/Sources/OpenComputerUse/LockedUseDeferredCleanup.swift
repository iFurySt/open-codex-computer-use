import Dispatch
import OpenComputerUseKit

/// A disconnected test client may leave the OS refusing Keychain deletion until
/// a normal unlock. Retain only this process's isolated probe objects and retry;
/// never enumerate existing Keychain items to discover cleanup targets.
final class LockedUseDeferredCleanup: @unchecked Sendable {
    private final class Item: @unchecked Sendable {
        let probe: LockedUseKeychainProbe
        init(_ probe: LockedUseKeychainProbe) { self.probe = probe }
    }
    static let shared = LockedUseDeferredCleanup()
    private let queue = DispatchQueue(label: "ocu.locked-use.keychain-cleanup")
    private var items: [Item] = []
    private var timer: DispatchSourceTimer?

    func retainIfNeeded(_ probe: LockedUseKeychainProbe) {
        guard !probe.cleanup() else { return }
        let item = Item(probe)
        queue.async { [self, item] in
            items.append(item)
            if timer == nil {
                let source = DispatchSource.makeTimerSource(queue: queue)
                source.schedule(deadline: .now() + 1, repeating: .seconds(1))
                source.setEventHandler { [self] in
                    guard LockedUseSession.current().state == .unlocked else { return }
                    items.removeAll { $0.probe.cleanup() }
                    if items.isEmpty { timer?.cancel(); timer = nil }
                }
                timer = source; source.resume()
            }
        }
    }
}
