import AppKit
import CoreGraphics
import Foundation

/// Sample a grid over `bounds`; the window looks unoccluded when at least one
/// sample point is not covered by any window above it. Mirrors Chromium's own
/// manual occlusion check closely enough to decide whether freezing the
/// visible state is safe (freezing while occluded would pin the page hidden).
func windowLooksUnoccluded(bounds: CGRect, coveringBounds: [CGRect], grid: Int = 16) -> Bool {
    guard bounds.width > 0, bounds.height > 0 else {
        return false
    }
    for row in 0..<grid {
        for column in 0..<grid {
            let point = CGPoint(
                x: bounds.minX + bounds.width * (CGFloat(column) + 0.5) / CGFloat(grid),
                y: bounds.minY + bounds.height * (CGFloat(row) + 0.5) / CGFloat(grid)
            )
            if !coveringBounds.contains(where: { $0.contains(point) }) {
                return true
            }
        }
    }
    return false
}

/// Chromium-derived engines (Chrome, Electron, CEF hosts) build their web
/// accessibility tree lazily after the first AX client request. Detect the
/// engine from the frameworks the app ships instead of a bundle-identifier
/// list; WebKit hosts expose their web area immediately and need no wait.
func appHasLazyWebAccessibility(bundleURL: URL?) -> Bool {
    guard let bundleURL else {
        return false
    }
    let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
    return names.contains { name in
        let lowered = name.lowercased()
        return lowered.contains("chrom") || lowered.contains("electron") || lowered.contains("cef")
    }
}

/// Keeps a driven window "visible" from its own app's point of view while the
/// agent works on it in the background.
///
/// Apps learn that a window is covered only through WindowServer occlusion
/// notifications (`NSWindow.occlusionState`). Web engines react by hiding the
/// page: Chromium, Electron and WebKit drop the web accessibility subtree and
/// pause rendering. Disabling those notifications for one window while it is
/// visible pins the app's notion at "visible", so covering the window later or
/// moving it to another Space no longer hides its content. This is a
/// WindowServer-level, app-agnostic switch, applied to every window the agent
/// drives; its prior state is restored when the server shuts down normally.
/// Nothing here activates, raises, or moves a window, and it cannot un-hide a
/// window that is already occluded when the agent first sees it.
final class WindowOcclusionKeepAlive: @unchecked Sendable {
    static let shared = WindowOcclusionKeepAlive()

    private let lock = NSLock()
    /// Preserve the state reported by the SPI so cleanup does not enable
    /// notifications that another owner had already disabled.
    private var frozenWindowPreviousStates: [CGWindowID: Bool] = [:]
    private var exitHookInstalled = false

    /// Returns `true` when the window's visible state is pinned (now or already).
    @discardableResult
    func keepVisible(
        windowID: CGWindowID,
        bounds: CGRect,
        spi: any WindowOcclusionControlling = SkyLightSPI.shared
    ) -> Bool {
        guard spi.occlusionCapability.isAvailable else {
            return false
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        if frozenWindowPreviousStates[windowID] != nil {
            return true
        }
        guard windowLooksUnoccluded(bounds: bounds, coveringBounds: coveringWindowBounds(above: windowID)) else {
            return false
        }
        do {
            let previousState = try spi.setWindowOcclusionNotificationsEnabled(false, windowID: windowID)
            frozenWindowPreviousStates[windowID] = previousState
        } catch {
            return false
        }
        installExitHookIfNeeded()
        return true
    }

    func isPinned(windowID: CGWindowID) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return frozenWindowPreviousStates[windowID] != nil
    }

    func releaseAll(spi: any WindowOcclusionControlling = SkyLightSPI.shared) {
        lock.lock()
        defer { lock.unlock() }
        for (windowID, previousState) in Array(frozenWindowPreviousStates) {
            do {
                try spi.setWindowOcclusionNotificationsEnabled(previousState, windowID: windowID)
                frozenWindowPreviousStates.removeValue(forKey: windowID)
            } catch {
                // Retain failed entries so a later cleanup can retry.
            }
        }
    }

    private func installExitHookIfNeeded() {
        guard !exitHookInstalled else {
            return
        }
        exitHookInstalled = true
        atexit {
            WindowOcclusionKeepAlive.shared.releaseAll()
        }
    }

}

/// Release process-owned background window state at the host's session
/// boundary. The exit hooks remain a final best-effort fallback.
public func resetOpenComputerUseBackgroundWindowState() {
    WindowOcclusionKeepAlive.shared.releaseAll()
    AgentDisplay.shared.restoreAll()
}
