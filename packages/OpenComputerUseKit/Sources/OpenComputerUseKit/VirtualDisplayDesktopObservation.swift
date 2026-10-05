import AppKit
import CoreGraphics
import Foundation

/// Read-only geometry observations. Does not change Dock preferences or synthesize pointer events.
public struct VirtualDisplayDesktopObservation: Sendable {
    public let mainDisplayID: UInt32
    public let physicalFrames: [UInt32: CGRect]
    public let dockFrame: CGRect?
    public let dockDisplayID: UInt32?
    public let foregroundPID: Int32?
    public static func current(excluding virtualIDs: Set<UInt32> = []) -> Self {
        let frames = Dictionary(uniqueKeysWithValues: VirtualDisplaySessionRegistry.onlineDisplayIDs().filter { !virtualIDs.contains($0) }.map { ($0, CGDisplayBounds($0)) })
        var dockFrame: CGRect?
        if let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }),
           let children = VirtualDisplayWindowAccess.attribute(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute) as? [AXUIElement] {
            dockFrame = children.first(where: { VirtualDisplayWindowAccess.attribute($0, kAXRoleAttribute) as? String == "AXList" }).flatMap { VirtualDisplayWindowAccess.frame($0) }
        }
        // Some Dock versions expose no usable AX list. Record the on-screen Dock host geometry instead.
        if dockFrame == nil {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            if let dock = windows.first(where: { $0[kCGWindowOwnerName as String] as? String == "Dock" && $0[kCGWindowName as String] as? String == "Dock" }),
               let bounds = dock[kCGWindowBounds as String] as? [String: Any] { dockFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) }
        }
        let display = dockFrame.flatMap { frame in
            frames.max { left, right in Self.area(left.value.intersection(frame)) < Self.area(right.value.intersection(frame)) }.flatMap { Self.area($0.value.intersection(frame)) > 0 ? $0.key : nil }
        }
        return .init(mainDisplayID: CGMainDisplayID(), physicalFrames: frames, dockFrame: dockFrame, dockDisplayID: display, foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }
    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }
    public var dictionary: [String: Any] {
        var value: [String: Any] = ["main_display_id": mainDisplayID, "physical_displays": physicalFrames.sorted { $0.key < $1.key }.map { ["id": $0.key, "frame": Self.rect($0.value)] }]
        value["dock_display_id"] = dockDisplayID
        value["dock_frame"] = dockFrame.map(Self.rect)
        value["foreground_pid"] = foregroundPID
        return value
    }
    private static func rect(_ frame: CGRect) -> [String: Double] { ["x":frame.minX,"y":frame.minY,"width":frame.width,"height":frame.height] }
}
