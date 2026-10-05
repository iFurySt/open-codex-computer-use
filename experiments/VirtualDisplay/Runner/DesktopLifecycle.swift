import Foundation
import OpenComputerUseKit

func desktopLifecycleChecks(cycles: Int) throws {
    let registry = VirtualDisplaySessionRegistry.shared
    let original = VirtualDisplayDesktopObservation.current(excluding: registry.activeDisplayIDs)
    report("desktop_baseline", original.dictionary)
    for cycle in 1...cycles {
        let session = try registry.create()
        let created = VirtualDisplayDesktopObservation.current(excluding: registry.activeDisplayIDs)
        report("desktop_created", ["cycle": cycle,"desktop":created.dictionary,"session":session.dictionary])
        try registry.destroy(sessionID: session.sessionID, retainDisplay: false)
        Thread.sleep(forTimeInterval: 0.5)
        let ended = VirtualDisplayDesktopObservation.current(excluding: registry.activeDisplayIDs)
        report("desktop_ended", ["cycle":cycle,"desktop":ended.dictionary])
        try ensure(created.mainDisplayID == original.mainDisplayID && ended.mainDisplayID == original.mainDisplayID, "Main display changed")
        try ensure(created.physicalFrames == original.physicalFrames && ended.physicalFrames == original.physicalFrames, "Physical arrangement changed")
        if let dock = original.dockDisplayID {
            try ensure(created.dockDisplayID == dock && ended.dockDisplayID == dock, "Dock moved between physical displays")
        }
    }
    report("desktop_lifecycle_complete", ["cycles":cycles])
}
