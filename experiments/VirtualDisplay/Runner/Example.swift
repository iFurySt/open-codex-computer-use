import AppKit
import CoreGraphics
import Foundation
import OpenComputerUseKit

func exampleChecks() throws {
    let registry = VirtualDisplaySessionRegistry.shared
    let originalDisplays = Set(VirtualDisplaySessionRegistry.onlineDisplayIDs())
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let observer = InputObservation(); observer.start(); defer { observer.stop() }
    let containment = WindowContainmentObservation(); containment.start()
    defer { _ = containment.stop(targets: []) }
    let session = try registry.create()
    defer { try? registry.destroy(sessionID: session.sessionID) }
    var ownedPIDs: Set<Int32> = []
    var containmentReported = false
    defer {
        if !containmentReported {
            let observation = containment.stop(targets: ownedPIDs)
            report("window_containment", ["physical_window_samples": observation.physicalSamples, "owned_app_activated": observation.activated, "sample_interval_ms": 16])
        }
    }
    let kernel = VirtualDisplayNotebookKernel(sessionID: session.sessionID)
    for cell in VirtualDisplayExample.cells {
        let result = try kernel.run(source: cell.source)
        ownedPIDs = Set(try registry.state(sessionID: session.sessionID).applications.map(\.pid))
        report("window_containment_checkpoint", ["title": cell.title, "physical_samples_by_pid": containment.counts(targets: ownedPIDs)])
        let output = VirtualDisplayNotebookOutput(result)
        report("example_cell", ["title": cell.title, "result": output.json, "has_tree": output.uiTree != nil, "screenshots": output.images.count])
        try ensure(!result.isError, "Example cell failed: \(cell.title)")
        if cell.title.hasPrefix("Calculate") { try ensure(output.json.contains("714"), "Actual Calculator result was not 714") }
        if cell.title == "Inspect the finished document" { try ensure(output.uiTree?.contains("42 × 17 = 714") == true, "Final TextEdit UI did not contain the Calculator result") }
        if cell.title.hasPrefix("Inspect") { try ensure(!output.images.isEmpty && output.uiTree != nil, "Real AX/SCK snapshot missing") }
        try ensure(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost, "Example changed foreground application")
    }
    let document = try registry.ownedDocument(sessionID: session.sessionID, app: "com.apple.TextEdit")
    let pids = try registry.state(sessionID: session.sessionID).applications.map(\.pid)
    let visibility = containment.stop(targets: Set(pids))
    containmentReported = true
    report("window_containment", ["physical_window_samples": visibility.physicalSamples, "owned_app_activated": visibility.activated, "sample_interval_ms": 16])
    try ensure(visibility.physicalSamples == 0 && !visibility.activated, "An owned app flashed on a physical screen or activated")
    let observation = observer.observation()
    try ensure(observation.available && observation.global == 0, "Global input reached the physical desktop")
    try registry.destroy(sessionID: session.sessionID)
    try ensure(pids.allSatisfy { NSRunningApplication(processIdentifier: $0) == nil }, "Owned apps remained")
    try ensure(!FileManager.default.fileExists(atPath: document.deletingLastPathComponent().path), "Owned temporary document remained")
    try ensure(Set(VirtualDisplaySessionRegistry.onlineDisplayIDs()) == originalDisplays, "Display remained")
    report("example_complete", ["foreground_preserved": true, "global_input_events": observation.global, "document_ui_verified_and_cleaned": true])
}
