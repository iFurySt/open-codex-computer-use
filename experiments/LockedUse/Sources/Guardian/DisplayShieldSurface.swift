import AppKit
import Foundation

private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shared visual surface for both the isolated preview and guarded rehearsal.
@MainActor
final class DisplayShieldSurface {
    private var windows: [CGDirectDisplayID: ShieldWindow] = [:]
    private var labels: [CGDirectDisplayID: NSTextField] = [:]
    private var topology = ""
    var count: Int { windows.count }

    func updateMessage(_ message: String) {
        for (id, label) in labels {
            label.stringValue = message
            windows[id]?.displayIfNeeded()
        }
    }

    func close() {
        for window in windows.values { window.close() }
        windows.removeAll()
        labels.removeAll()
    }

    private func screenIDs() -> [(CGDirectDisplayID, NSScreen)] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen)
        }
    }

    func displayTopology() -> String {
        screenIDs().sorted { $0.0 < $1.0 }.map { id, screen in
            "\(id):\(NSStringFromRect(screen.frame)):\(screen.backingScaleFactor)"
        }.joined(separator: "|")
    }

    func coverDisplays(message: String, levelOffset: Int = 0) throws {
        let screens = screenIDs()
        guard !screens.isEmpty else { throw GuardianError.message("No display available") }
        topology = displayTopology()
        for (id, screen) in screens {
            let window = ShieldWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: true)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + levelOffset)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .black
            window.isOpaque = true
            window.alphaValue = 1
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.sharingType = .none
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: message)
            label.alignment = .center
            label.textColor = .white
            label.font = .systemFont(ofSize: 22)
            label.translatesAutoresizingMaskIntoConstraints = false
            if let view = window.contentView {
                view.addSubview(label)
                NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            }
            window.orderFrontRegardless()
            window.displayIfNeeded()
            windows[id] = window
            labels[id] = label
        }
    }

    /// WindowServer evidence, not just `isVisible`. Other secure/system overlays
    /// and hotplug races still require live validation; this is not a proof that
    /// ordinary windows provide an OS-enforced privacy barrier.
    func coverageHealthy() -> Bool { coverageFailure() == nil }

    func coverageFailure() -> String? {
        guard displayTopology() == topology else { return "topologyChanged" }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 64 else { return "activeDisplayCountUnavailable" }
        var active = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &active, &count) == .success else { return "activeDisplayListUnavailable" }
        for id in active.prefix(Int(count)) {
            let mirrored = CGDisplayMirrorsDisplay(id)
            guard windows[id] != nil || (mirrored != kCGNullDirectDisplay && windows[mirrored] != nil) else { return "activeDisplayUncovered" }
        }
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return "windowListUnavailable" }
        for (id, window) in windows {
            guard window.isVisible else { return "shieldNotVisible" }
            guard let info = infos.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == window.windowNumber }) else { return "shieldNotInWindowServer" }
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid() else { return "shieldOwnerMismatch" }
            guard (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 1 else { return "shieldAlphaMismatch" }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == window.level.rawValue else { return "shieldLayerMismatch" }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return "shieldBoundsUnavailable" }
            guard rect == CGDisplayBounds(id) else { return "shieldBoundsMismatch" }
        }
        return nil
    }

}
