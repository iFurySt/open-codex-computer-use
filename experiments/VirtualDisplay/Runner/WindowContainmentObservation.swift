import AppKit
import CoreGraphics
import Foundation
import OpenComputerUseKit

/// 60 Hz metadata-only sampling: no user pixels, keyboard contents, or window titles.
final class WindowContainmentObservation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ocu.window-containment-observation")
    private let lock = NSLock()
    private let originalPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
    private let physicalFrames = VirtualDisplayDesktopObservation.current().physicalFrames.values.map { $0 }
    private var timer: DispatchSourceTimer?
    private var observer: NSObjectProtocol?
    private var physicalSamples: [Int32: Int] = [:]
    private var activations: Set<Int32> = []
    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.lock.lock(); self.activations.insert(app.processIdentifier); self.lock.unlock()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer; timer.resume()
    }
    private func sample() {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, !originalPIDs.contains(pid),
                  window[kCGWindowLayer as String] as? Int == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  physicalFrames.contains(where: { let hit = $0.intersection(frame); return !hit.isNull && hit.width * hit.height > 0 }) else { continue }
            lock.lock(); physicalSamples[pid, default: 0] += 1; lock.unlock()
        }
    }
    func counts(targets: Set<Int32>) -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: targets.map { (String($0), physicalSamples[$0] ?? 0) })
    }
    func stop(targets: Set<Int32>) -> (physicalSamples: Int, activated: Bool) {
        timer?.cancel(); queue.sync {}; timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observer = nil
        lock.lock(); defer { lock.unlock() }
        return (targets.reduce(0) { $0 + (physicalSamples[$1] ?? 0) }, !activations.isDisjoint(with: targets))
    }
}
