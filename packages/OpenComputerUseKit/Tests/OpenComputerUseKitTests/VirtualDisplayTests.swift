import CoreGraphics
import XCTest
@testable import OpenComputerUseKit

final class VirtualDisplayTests: XCTestCase {
    func testDisplayLifecycleRejectsMalformedControlBeforeSideEffects() {
        let dispatcher = ComputerUseToolDispatcher()
        for (tool, arguments) in [
            ("create_virtual_display", ["reuse_display": "false"] as [String: Any]),
            ("create_virtual_display", ["reuse_display": 1]),
            ("destroy_virtual_display", ["session_id": "missing", "retain_display": 0]),
            ("release_virtual_displays", ["display_id": Int64(UInt32.max) + 1]),
            ("release_virtual_displays", ["display_id": -1]),
            ("delete_virtual_display", [:]),
            ("delete_virtual_display", ["display_id": Int64(UInt32.max) + 1])
        ] {
            let result = dispatcher.callToolAsResult(name: tool, arguments: arguments)
            XCTAssertTrue(result.isError, tool)
            XCTAssertFalse(result.primaryText?.contains("permissions are required") == true)
        }
    }

    func testAdoptionRequiresExplicitWindowAndLaunchRejectsAdoptionArguments() throws {
        XCTAssertNoThrow(try VirtualDisplayAttachmentIntent.validate(app: nil, pid: 12, windowID: 34, launch: false, newDocument: false))
        for (app, pid, window, launch, document) in [
            ("Example" as String?, nil as Int32?, nil as UInt32?, false, false),
            (nil, 12, nil, false, false),
            (nil, 12, 34, true, false),
            ("Example", 12, 34, true, false),
            ("Example", nil, nil, true, true),
            ("com.apple.TextEdit", 12, 34, false, true)
        ] {
            XCTAssertThrowsError(try VirtualDisplayAttachmentIntent.validate(app: app, pid: pid, windowID: window, launch: launch, newDocument: document))
        }
    }

    func testHideOwnershipRequiresNewMatchingVerifiableProcess() {
        let birth = Date()
        XCTAssertTrue(VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(pid: 2, previousPIDs: [1], requestedApp: "Example", actualApp: "example", birth: birth))
        XCTAssertFalse(VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(pid: 1, previousPIDs: [1], requestedApp: "Example", actualApp: "Example", birth: birth))
        XCTAssertFalse(VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(pid: 2, previousPIDs: [1], requestedApp: "Example", actualApp: "Other", birth: birth))
        XCTAssertFalse(VirtualDisplayAttachmentIntent.verifiedDedicatedInstance(pid: 2, previousPIDs: [1], requestedApp: "Example", actualApp: "Example", birth: nil))
    }

    func testUnmanagedBorrowedWindowsStayOutsideScopeAndUnknownDialogsPause() {
        XCTAssertFalse(VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: false, hidden: false, modal: false))
        XCTAssertFalse(VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: true, hidden: true, modal: false))
        XCTAssertTrue(VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: true, hidden: false, modal: false))
        XCTAssertTrue(VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: false, hidden: false, modal: true))
        XCTAssertTrue(VirtualDisplayAttachmentIntent.shouldPauseForUnmanagedWindow(owned: true, hidden: true, modal: true))
    }

    func testLaunchReuseErrorContainsCandidatesWithoutImplicitAuthorization() {
        let candidate = VirtualDisplayApplicationCandidate(pid: 12, app: "Example", name: "Example", windows: [], windowsAvailable: true)
        let error = VirtualDisplayLaunchReusedError(candidates: [candidate])
        XCTAssertEqual(error.dictionary["error"] as? String, "launch_reused_existing_instance")
        XCTAssertEqual((error.dictionary["candidates"] as? [[String: Any]])?.first?["pid"] as? Int32, 12)
    }

    func testCandidateQueryReadsRealProcessesWithoutClaimingWindows() throws {
        let registry = VirtualDisplaySessionRegistry.shared
        let before = registry.states().map(\.sessionID)
        let candidates = try registry.applicationCandidates()
        XCTAssertEqual(candidates.map(\.pid), candidates.map(\.pid).sorted())
        XCTAssertEqual(Set(candidates.map(\.pid)).count, candidates.count)
        for candidate in candidates {
            XCTAssertGreaterThan(candidate.pid, 0)
            XCTAssertTrue(candidate.windows.allSatisfy { $0.pid == candidate.pid })
            if !candidate.windowsAvailable { XCTAssertTrue(candidate.windows.isEmpty) }
        }
        XCTAssertTrue(try registry.applicationCandidates(app: "ocu.uninstalled.\(UUID().uuidString)").isEmpty)
        XCTAssertEqual(registry.states().map(\.sessionID), before)
    }

    func testHealthyEmptySessionStartsReadyAndLayoutFailureStillPauses() {
        XCTAssertNil(VirtualDisplaySessionStartupPolicy.creationPauseReason(physicalLayoutPreserved: true))
        XCTAssertNotNil(VirtualDisplaySessionStartupPolicy.creationPauseReason(physicalLayoutPreserved: false))
    }

    func testSpaceSetupNotificationDoesNotPauseEmptySessionButSafetyEventsDo() {
        XCTAssertFalse(VirtualDisplaySessionStartupPolicy.shouldPauseForDesktopChange(onlyManagedApplications: true, hasManagedApplications: false))
        XCTAssertTrue(VirtualDisplaySessionStartupPolicy.shouldPauseForDesktopChange(onlyManagedApplications: true, hasManagedApplications: true))
        XCTAssertTrue(VirtualDisplaySessionStartupPolicy.shouldPauseForDesktopChange(onlyManagedApplications: false, hasManagedApplications: false))
        XCTAssertTrue(VirtualDisplaySessionStartupPolicy.shouldPauseForDesktopChange(onlyManagedApplications: false, hasManagedApplications: true))
    }

    func testBrowserCursorAssetLoadsFromPackageResources() throws {
        let image = try XCTUnwrap(BrowserUseCursorArtwork.image)
        XCTAssertEqual(image.width, 46)
        XCTAssertEqual(image.height, 48)
        XCTAssertTrue(image.alphaInfo == .last || image.alphaInfo == .premultipliedLast)
    }

    func testStableDisplaySlotsNeverReuseAnOccupiedIdentity() throws {
        let first = try VirtualDisplayIdentity.availableSerial(occupied: [])
        let second = try VirtualDisplayIdentity.availableSerial(occupied: [first])
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try VirtualDisplayIdentity.availableSerial(occupied: []), first)
        let occupied = Set((UInt32(0)..<VirtualDisplayIdentity.slotCount).map { VirtualDisplayIdentity.serial(slot: $0) })
        XCTAssertEqual(occupied.count, 32)
        XCTAssertFalse(occupied.contains(0))
        XCTAssertThrowsError(try VirtualDisplayIdentity.availableSerial(occupied: occupied))
        var freed = occupied
        freed.remove(second)
        XCTAssertEqual(try VirtualDisplayIdentity.availableSerial(occupied: freed), second)
    }

    func testDisplayAllocationLockReleasesAfterFailure() throws {
        enum Expected: Error { case failure }
        XCTAssertThrowsError(try VirtualDisplayIdentity.withCreationLock { throw Expected.failure })
        XCTAssertEqual(try VirtualDisplayIdentity.withCreationLock { 42 }, 42)
    }

    func testRepeatedDisplayLifetimesUseBoundedPhysicalIdentity() throws {
        var observed = Set<UInt32>()
        for _ in 0..<1_000 {
            // Runtime namespace and bundle identity are deliberately absent from allocation.
            observed.insert(try VirtualDisplayIdentity.availableSerial(occupied: []))
        }
        XCTAssertEqual(observed, [VirtualDisplayIdentity.serial(slot: 0)])
    }
    func testVirtualSkyClickCannotSynthesizeActivationEvenWhenTargetIsInactive() {
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: 10, targetPID: 20, allowSyntheticFocus: false))
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: nil, targetPID: 20, allowSyntheticFocus: false))
        XCTAssertTrue(skyClickNeedsSyntheticFocus(frontmostPID: 10, targetPID: 20, allowSyntheticFocus: true))
        XCTAssertFalse(skyClickNeedsSyntheticFocus(frontmostPID: 20, targetPID: 20, allowSyntheticFocus: true))
    }
    func testExampleCommandsBindToSessionAndRejectMalformedOperands() throws {
        for cell in VirtualDisplayExample.cells {
            let spec = try VirtualDisplayNotebookKernel.boundCommand(source: cell.source, sessionID: "example")
            XCTAssertEqual(spec.arguments["session_id"] as? String, "example")
        }
        XCTAssertEqual(try VirtualDisplayExample.validatedNumber("-42.25"), "-42.25")
        for invalid: Any in ["1e4", "nan", "12; command", "123456789", true, 42] {
            XCTAssertThrowsError(try VirtualDisplayExample.validatedNumber(invalid))
        }
    }
    func testNotebookOutputSeparatesTreeAndImagesFromFormattedJSON() throws {
        let result = ToolCallResult(content: [.text(#"{"result":"714"}"#), .text("App=Calculator\n0 standard window"), .pngImage(Data([1, 2, 3]))])
        let output = VirtualDisplayNotebookOutput(result)
        XCTAssertEqual(output.uiTree, "App=Calculator\n0 standard window")
        XCTAssertEqual(output.images, [Data([1, 2, 3])])
        let json = try JSONSerialization.jsonObject(with: Data(output.json.utf8)) as? [String: Any]
        XCTAssertEqual((json?["result"] as? [String: String])?["result"], "714")
        XCTAssertFalse(output.json.contains("AQID"))
        let failure = VirtualDisplayNotebookOutput(.text("Delivery unverified", isError: true))
        XCTAssertTrue(failure.json.contains("Delivery unverified"))
        XCTAssertTrue(failure.json.contains("true"))
    }
    func testNotebookBindsSessionAndSelectedAppWithoutAllowingEscape() throws {
        let spec = try VirtualDisplayNotebookKernel.boundCommand(source: #"{"tool":"get_app_state","args":{"app":"$app","session_id":"$session","window_id":42}}"#, sessionID: "s1", app: "com.apple.calculator")
        XCTAssertEqual(spec.tool, "get_app_state")
        XCTAssertEqual(spec.arguments["session_id"] as? String, "s1")
        XCTAssertEqual(spec.arguments["app"] as? String, "com.apple.calculator")
        XCTAssertEqual(spec.arguments["window_id"] as? Int, 42)
        for invalid in [#"{"tool":"click","args":{"session_id":"other"}}"#, #"{"tool":"create_virtual_display"}"#, #"{"tool":"shell","args":{"command":"echo hi"}}"#, #"{"tool":"get_app_state","args":[]}"#] {
            XCTAssertThrowsError(try VirtualDisplayNotebookKernel.boundCommand(source: invalid, sessionID: "s1"))
        }
    }
    func testNotebookPreservesExplicitAppAndEnforcesVirtualInputBoundary() throws {
        let spec = try VirtualDisplayNotebookKernel.boundCommand(source: #"{"tool":"get_app_state","args":{"app":"TextEdit"}}"#, sessionID: "s1", app: "Calculator")
        XCTAssertEqual(spec.arguments["app"] as? String, "TextEdit")
        let kernel = VirtualDisplayNotebookKernel(sessionID: "not-present")
        let result = try kernel.run(source: #"{"tool":"click","args":{"app":"TextEdit","click_method":"global","x":1,"y":1}}"#)
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("Global input is forbidden") == true)
    }
    func testStateListingDoesNotRequireAParticularSession() throws {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "get_virtual_display_state", arguments: [:])
        XCTAssertFalse(result.isError)
        let text = try XCTUnwrap(result.primaryText)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        XCTAssertNotNil(object?["sessions"] as? [[String: Any]])
        let definition = try XCTUnwrap(ToolDefinitions.all.first { $0.name == "get_virtual_display_state" })
        XCTAssertFalse((definition.inputSchema["required"] as? [String] ?? []).contains("session_id"))
    }
    func testConfigurationUsesLogicalDimensionsAndBoundsPixelAllocation() throws {
        try VirtualDisplayConfiguration().validate()
        try VirtualDisplayConfiguration(width: 1920, height: 1080, scale: 2).validate()
        for invalid in [VirtualDisplayConfiguration(width: 0), VirtualDisplayConfiguration(scale: 3), VirtualDisplayConfiguration(width: 7680, scale: 2)] {
            XCTAssertThrowsError(try invalid.validate())
        }
    }
    func testCoordinateConversionHandlesRetinaNegativeOriginAndRejectsOutsidePoints() throws {
        let bounds = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let point = try VirtualDisplayCoordinates.globalPoint(pixel: CGPoint(x: 1920, y: 1080), pixelSize: CGSize(width: 3840, height: 2160), bounds: bounds)
        XCTAssertEqual(point, CGPoint(x: -960, y: 340))
        for outside in [CGPoint(x: -1, y: 20), CGPoint(x: 3840, y: 0), CGPoint(x: CGFloat.nan, y: 0)] {
            XCTAssertThrowsError(try VirtualDisplayCoordinates.globalPoint(pixel: outside, pixelSize: CGSize(width: 3840, height: 2160), bounds: bounds))
        }
    }
    func testVirtualInputRefusesGlobalBeforeSessionLookupEvenWhenEnabled() {
        let dispatcher = ComputerUseToolDispatcher()
        let result = dispatcher.callToolAsResult(name: "click", arguments: ["app": "TextEdit", "session_id": "absent", "click_method": "global", "x": 10, "y": 10])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("Global input is forbidden") == true)
    }
    func testUnverifiedDragIsRejectedBeforeSessionLookup() {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "drag", arguments: ["app": "TextEdit", "session_id": "absent", "from_x": 1, "from_y": 1, "to_x": 10, "to_y": 10])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("unsupported") == true)
        XCTAssertNil(normalizedElementIndexArgument(Double(Int.max)))
    }
    func testAdoptionDoesNotTruncateProcessAndWindowIdentifiers() {
        let result = ComputerUseToolDispatcher().callToolAsResult(name: "attach_app_to_virtual_display", arguments: ["app": "TextEdit", "session_id": "absent", "pid": Int64.max, "window_id": 1])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.primaryText?.contains("range") == true)
    }
    func testSessionSchemaIsAdditiveAndWindowSelectionIsSnapshotOnly() throws {
        let tools = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })
        for name in ["click", "get_app_state", "scroll", "drag", "type_text", "press_key", "set_value", "perform_secondary_action"] {
            let schema = try XCTUnwrap(tools[name]?.inputSchema)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertNotNil(properties["session_id"])
            XCTAssertEqual(properties["window_id"] != nil, name == "get_app_state")
            XCTAssertTrue((schema["required"] as? [String])?.contains("app") == true)
        }
        let list = try XCTUnwrap(tools["list_apps"]?.inputSchema["properties"] as? [String: Any])
        XCTAssertNil(list["session_id"])
    }
    func testUnknownSessionAndUnscopedWindowNeverReachLegacyDiscovery() {
        let dispatcher = ComputerUseToolDispatcher()
        let unknown = dispatcher.callToolAsResult(name: "get_app_state", arguments: ["app": "TextEdit", "session_id": "unknown"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.primaryText?.contains("Unknown virtual display") == true)
        let unscoped = dispatcher.callToolAsResult(name: "get_app_state", arguments: ["app": "TextEdit", "window_id": 1])
        XCTAssertTrue(unscoped.isError)
        XCTAssertTrue(unscoped.primaryText?.contains("requires session_id") == true)
    }
}
