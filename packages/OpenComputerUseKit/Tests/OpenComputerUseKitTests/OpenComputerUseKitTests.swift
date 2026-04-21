import AppKit
import XCTest
@testable import OpenComputerUseKit

final class OpenComputerUseKitTests: XCTestCase {
    func testCLIRecognizesGlobalHelpAndVersionFlags() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["-h"]), .help(command: nil))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["--help"]), .help(command: nil))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["-v"]), .version)
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["--version"]), .version)
    }

    func testCLIRecognizesCommandSpecificHelp() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["help", "snapshot"]), .help(command: "snapshot"))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["snapshot", "--help"]), .help(command: "snapshot"))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["doctor", "-h"]), .help(command: "doctor"))
    }

    func testCLIRequiresSnapshotArgument() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(
                    message: "snapshot requires an app name or bundle identifier",
                    helpCommand: "snapshot"
                )
            )
        }
    }

    func testCLIRejectsUnknownOption() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["--verbose"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(
                    message: "Unknown option: --verbose",
                    helpCommand: nil
                )
            )
        }
    }

    func testGeneralHelpListsCommandsAndGlobalFlags() {
        let help = openComputerUseHelpText()

        XCTAssertTrue(help.contains("open-computer-use [command] [options]"))
        XCTAssertTrue(help.contains("snapshot <app>"))
        XCTAssertTrue(help.contains("-h, --help"))
        XCTAssertTrue(help.contains("-v, --version"))
    }

    func testResolvedVersionFallsBackWhenBundleHasNoVersionMetadata() {
        XCTAssertEqual(resolvedOpenComputerUseVersion(bundle: Bundle(for: Self.self)), openComputerUseVersion)
    }

    func testToolDefinitionCount() {
        XCTAssertEqual(ToolDefinitions.all.count, 9)
    }

    func testPermissionDiagnosticsListsMissingPermissionsInCanonicalOrder() {
        let diagnostics = PermissionDiagnostics(
            accessibilityTrusted: false,
            screenCaptureGranted: true
        )

        XCTAssertEqual(diagnostics.missingPermissions, [.accessibility])
    }

    func testPermissionDiagnosticsHasNoMissingPermissionsWhenAllGranted() {
        let diagnostics = PermissionDiagnostics(
            accessibilityTrusted: true,
            screenCaptureGranted: true
        )

        XCTAssertTrue(diagnostics.missingPermissions.isEmpty)
    }

    func testPreferredPermissionAppBundleURLPrefersInstalledCopyOverTransientRunningCopy() {
        let installed = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/open-computer-use/dist/Open Computer Use.app")
        let running = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use/dist/Open Computer Use.app")
        let fallback = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use-debug/dist/Open Computer Use.app")

        let resolved = PermissionSupport.preferredPermissionAppBundleURL(
            preferredInstalledBundleURL: installed,
            runningBundleURL: running,
            fallbackDevelopmentBundleURL: fallback
        )

        XCTAssertEqual(resolved, installed)
    }

    func testPreferredPermissionAppBundleURLPrefersRunningDevelopmentCopy() {
        let installed = URL(fileURLWithPath: "/Applications/Open Computer Use.app")
        let running = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use/dist/Open Computer Use (Dev).app")
        let fallback = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use-debug/dist/Open Computer Use (Dev).app")

        let resolved = PermissionSupport.preferredPermissionAppBundleURL(
            preferredInstalledBundleURL: installed,
            runningBundleURL: running,
            fallbackDevelopmentBundleURL: fallback,
            preferRunningBundle: true
        )

        XCTAssertEqual(resolved, running)
    }

    func testPreferredInstalledAppBundleURLUsesFirstDiscoveredInstalledCopy() {
        let applications = URL(fileURLWithPath: "/Applications/Open Computer Use.app")
        let npm = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/open-computer-use/dist/Open Computer Use.app")
        let duplicateApplications = URL(fileURLWithPath: "/Applications/Open Computer Use.app")

        let resolved = PermissionSupport.preferredInstalledAppBundleURL(
            candidates: [applications, npm, duplicateApplications]
        )

        XCTAssertEqual(resolved, applications)
    }

    func testPermissionClientsKeepStableBundleIdentityAheadOfTransientAppPath() {
        let installed = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/open-computer-use/dist/Open Computer Use.app")
        let running = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use/dist/Open Computer Use.app")

        let clients = PermissionSupport.permissionClients(
            primaryBundleURL: installed,
            runningBundleURL: running,
            mainBundleIdentifier: PermissionSupport.bundleIdentifier
        )

        XCTAssertEqual(
            clients,
            [
                PermissionClientRecord(identifier: PermissionSupport.bundleIdentifier, type: 0),
                PermissionClientRecord(identifier: installed.path, type: 1),
                PermissionClientRecord(identifier: running.path, type: 1),
            ]
        )
    }

    func testPermissionClientsKeepDevelopmentBundleIdentitySeparateFromRelease() {
        let running = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use/dist/Open Computer Use (Dev).app")

        let clients = PermissionSupport.permissionClients(
            primaryBundleURL: running,
            runningBundleURL: running,
            mainBundleIdentifier: PermissionSupport.developmentBundleIdentifier,
            includeCanonicalBundleIdentifier: false
        )

        XCTAssertEqual(
            clients,
            [
                PermissionClientRecord(identifier: PermissionSupport.developmentBundleIdentifier, type: 0),
                PermissionClientRecord(identifier: running.path, type: 1),
            ]
        )
    }

    func testTCCAuthorizationGrantedTreatsAnyGrantedCandidateAsGranted() {
        XCTAssertTrue(tccAuthorizationGranted(authValues: [0, 2]))
        XCTAssertFalse(tccAuthorizationGranted(authValues: [0, nil]))
        XCTAssertFalse(tccAuthorizationGranted(authValues: []))
    }

    func testKeyPressParserSupportsCommandStyleChord() throws {
        let parsed = try KeyPressParser.parse("super+c")
        XCTAssertEqual(parsed.displayValue, "c")
        XCTAssertEqual(parsed.modifiers.count, 1)
    }

    func testInitializeResponseContainsToolsCapability() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.22"},"capabilities":{}}}"#)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains(#""name":"open-computer-use""#))
        XCTAssertTrue(response!.contains(#""tools":{"listChanged":false}"#))
    }

    func testInitializeResponseContainsComputerUseInstructions() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = try XCTUnwrap(
            server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.22"},"capabilities":{}}}"#)
        )
        let data = try XCTUnwrap(response.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let instructions = try XCTUnwrap(result["instructions"] as? String)

        XCTAssertEqual(instructions, computerUseServerInstructions)
    }

    func testWindowRelativeFrameUsesSharedGlobalCoordinates() {
        let window = CGRect(x: 1486, y: 556, width: 919, height: 644)
        let child = CGRect(x: 1486, y: 556, width: 919, height: 644)
        let textField = CGRect(x: 180, y: 176, width: 36, height: 18)
        let textFieldGlobal = CGRect(x: window.minX + textField.minX, y: window.minY + textField.minY, width: textField.width, height: textField.height)

        XCTAssertEqual(windowRelativeFrame(elementFrame: child, windowBounds: window), CGRect(x: 0, y: 0, width: 919, height: 644))
        XCTAssertEqual(windowRelativeFrame(elementFrame: textFieldGlobal, windowBounds: window), textField)
    }

    func testToolDescriptionsMatchOfficialComputerUseSurface() {
        let tools = Dictionary(uniqueKeysWithValues: ToolDefinitions.all.map { ($0.name, $0) })

        XCTAssertEqual(
            tools["get_app_state"]?.description,
            "Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app. This tool is part of plugin `Computer Use`."
        )
        XCTAssertTrue(tools["press_key"]?.description.contains("xdotool") == true)
        XCTAssertEqual(
            tools["click"]?.annotations["destructiveHint"] as? Bool,
            false
        )
        XCTAssertEqual(
            tools["get_app_state"]?.annotations["readOnlyHint"] as? Bool,
            true
        )
        XCTAssertEqual(
            tools["click"]?.inputSchema["additionalProperties"] as? Bool,
            false
        )
        XCTAssertEqual(
            ((tools["click"]?.inputSchema["properties"] as? [String: [String: Any]])?["mouse_button"]?["enum"] as? [String]) ?? [],
            ["left", "right", "middle"]
        )
    }

    func testSnapshotRenderedTextStartsDirectlyWithAppHeader() {
        let snapshot = makeSnapshot(
            treeLines: ["\t0 standard window Feishu"],
            focusedSummary: "247 text entry area"
        )

        let rendered = snapshot.renderedText(style: .actionResult)
        let lines = rendered.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "App=com.electron.lark (pid 18465)")
        XCTAssertEqual(lines.dropFirst().first, "Window: \"Feishu\", App: Feishu.")
        XCTAssertFalse(rendered.contains("Computer Use state (CUA App Version: 750)"))
        XCTAssertFalse(rendered.contains("<app_state>"))
        XCTAssertFalse(rendered.contains("</app_state>"))
    }

    func testSnapshotSelectedTextUsesOfficialSingleLineFormat() {
        let snapshot = makeSnapshot(
            treeLines: ["\t38 search text field (settable, string) Codex"],
            focusedSummary: nil,
            selectedText: "Codex"
        )

        let rendered = snapshot.renderedText(style: .actionResult)

        XCTAssertTrue(rendered.contains("Selected text: [Codex]"))
        XCTAssertFalse(rendered.contains("Selected text: ```"))
        XCTAssertFalse(rendered.contains("Pay special attention to the content selected by the user"))
    }

    func testComputerUseErrorsFormatLikeToolText() {
        XCTAssertEqual(ComputerUseError.appNotFound("Sublime Text").errorDescription, #"appNotFound("Sublime Text")"#)
        XCTAssertTrue(ComputerUseError.appNotFound("Sublime Text").toolResultIsError)
        XCTAssertTrue(ComputerUseError.invalidArguments("bad").toolResultIsError)
    }

    func testVisualCursorEnvFlagDefaultsToEnabled() {
        XCTAssertTrue(visualCursorEnabled(environment: [:]))
        XCTAssertTrue(visualCursorEnabled(environment: ["OPEN_COMPUTER_USE_VISUAL_CURSOR": "1"]))
        XCTAssertFalse(visualCursorEnabled(environment: ["OPEN_COMPUTER_USE_VISUAL_CURSOR": "0"]))
        XCTAssertFalse(visualCursorEnabled(environment: ["OPEN_COMPUTER_USE_VISUAL_CURSOR": "false"]))
    }

    func testInputFallbackDebugFlagDefaultsToDisabled() {
        XCTAssertFalse(inputFallbackDebugEnabled(environment: [:]))
        XCTAssertTrue(inputFallbackDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS": "1"]))
        XCTAssertTrue(inputFallbackDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS": "true"]))
        XCTAssertFalse(inputFallbackDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS": "0"]))
        XCTAssertFalse(inputFallbackDebugEnabled(environment: ["OPEN_COMPUTER_USE_DEBUG_INPUT_FALLBACKS": "off"]))
    }

    func testMakeVisualCursorTargetUsesWindowRelativeElementCenter() {
        let target = makeVisualCursorTarget(
            localFrame: CGRect(x: 24, y: 32, width: 120, height: 48),
            windowBounds: CGRect(x: 400, y: 220, width: 900, height: 640),
            targetWindowID: 321,
            targetWindowLayer: 8
        )

        XCTAssertEqual(
            target,
            VisualCursorTarget(
                point: CGPoint(x: 484, y: 276),
                window: CursorTargetWindow(windowID: 321, layer: 8)
            )
        )
    }

    func testMakeVisualCursorTargetReturnsNilWithoutWindowBounds() {
        XCTAssertNil(
            makeVisualCursorTarget(
                localFrame: CGRect(x: 24, y: 32, width: 120, height: 48),
                windowBounds: nil,
                targetWindowID: 321,
                targetWindowLayer: 8
            )
        )
    }

    func testCursorWindowGeometryAnchorsTipPosition() {
        let geometry = CursorWindowGeometry(
            windowSize: CGSize(width: 128, height: 128),
            tipAnchor: CGPoint(x: 44, y: 88)
        )
        let tipPosition = CGPoint(x: 1200, y: 800)

        XCTAssertEqual(geometry.origin(forTipPosition: tipPosition), CGPoint(x: 1156, y: 712))
        XCTAssertEqual(geometry.tipPosition(forOrigin: CGPoint(x: 1156, y: 712)), tipPosition)
    }

    func testSoftwareCursorGlyphMetricsMatchRuntimeProceduralCalibration() {
        XCTAssertEqual(SoftwareCursorGlyphMetrics.windowSize, CGSize(width: 126, height: 126))
        XCTAssertEqual(SoftwareCursorGlyphMetrics.tipAnchor.x, 60.35, accuracy: 0.01)
        XCTAssertEqual(SoftwareCursorGlyphMetrics.tipAnchor.y, 70.3, accuracy: 0.01)
        XCTAssertEqual(SoftwareCursorGlyphMetrics.referenceImageResourceName, "official-software-cursor-window-252")
    }

    func testSoftwareCursorGlyphLoadsCursorMotionReferenceImage() throws {
        let image = try XCTUnwrap(loadReferenceCursorWindowImage())
        let bitmap = try XCTUnwrap(image.representations.first)

        XCTAssertEqual(bitmap.pixelsWide, 252)
        XCTAssertEqual(bitmap.pixelsHigh, 252)
    }

    func testSoftwareCursorGlyphArtworkNeutralHeadingMatchesCursorMotionBaseline() {
        let correctedNeutralHeading = SoftwareCursorGlyphMetrics.proceduralContourNeutralHeading
            - SoftwareCursorGlyphMetrics.pointerArtworkRotation

        XCTAssertEqual(
            correctedNeutralHeading,
            SoftwareCursorGlyphMetrics.targetNeutralHeading,
            accuracy: 0.001
        )
        XCTAssertEqual(SoftwareCursorGlyphMetrics.targetNeutralHeading, -(3 * CGFloat.pi / 4), accuracy: 0.001)
    }

    func testSoftwareCursorGlyphConvertsScreenStateToAppKitDrawingState() {
        let screenState = SoftwareCursorGlyphRenderState(
            rotation: .pi / 3,
            cursorBodyOffset: CGVector(dx: 2, dy: -4),
            fogOffset: CGVector(dx: -3, dy: 5),
            fogOpacity: 0.2,
            fogScale: 1.1,
            clickProgress: 0.6
        )

        let drawingState = screenState.appKitDrawingState

        XCTAssertEqual(drawingState.rotation, -.pi / 3, accuracy: 0.0001)
        XCTAssertEqual(drawingState.cursorBodyOffset.dx, 2, accuracy: 0.0001)
        XCTAssertEqual(drawingState.cursorBodyOffset.dy, 4, accuracy: 0.0001)
        XCTAssertEqual(drawingState.fogOffset.dx, -3, accuracy: 0.0001)
        XCTAssertEqual(drawingState.fogOffset.dy, -5, accuracy: 0.0001)
        XCTAssertEqual(drawingState.fogOpacity, 0.2)
        XCTAssertEqual(drawingState.fogScale, 1.1)
        XCTAssertEqual(drawingState.clickProgress, 0.6)
    }

    func testDefaultVisualCursorInitialTipMatchesZeroWindowOrigin() {
        let geometry = CursorWindowGeometry(
            windowSize: CGSize(width: 126, height: 126),
            tipAnchor: CGPoint(x: 60.35, y: 70.3)
        )
        let start = defaultVisualCursorInitialTipPosition(
            windowOrigin: .zero,
            tipAnchor: geometry.tipAnchor
        )

        XCTAssertEqual(geometry.origin(forTipPosition: start), .zero)
        XCTAssertEqual(start.x, geometry.tipAnchor.x, accuracy: 0.0001)
        XCTAssertEqual(start.y, geometry.tipAnchor.y, accuracy: 0.0001)
    }

    func testVisualCursorRuntimeMapsAppKitUpwardMotionToCursorMotionScreenState() {
        let renderBaseHeading = visualCursorRenderBaseHeading(
            artworkNeutralHeading: SoftwareCursorGlyphMetrics.targetNeutralHeading
        )
        let screenVelocity = visualCursorScreenStateVelocity(
            fromRuntimeVelocity: CGVector(dx: 0, dy: 1),
            yAxisMultiplier: visualCursorRuntimeRenderYAxisMultiplier()
        )
        let renderRotation = normalizedAngle(atan2(screenVelocity.dy, screenVelocity.dx) - renderBaseHeading)
        let appKitForwardHeading = visualCursorAppKitForwardHeading(
            renderRotation: renderRotation,
            artworkNeutralHeading: SoftwareCursorGlyphMetrics.targetNeutralHeading
        )

        XCTAssertEqual(renderBaseHeading, -(3 * CGFloat.pi / 4), accuracy: 0.0001)
        XCTAssertEqual(screenVelocity.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(screenVelocity.dy, -1, accuracy: 0.0001)
        XCTAssertEqual(renderRotation, CGFloat.pi / 4, accuracy: 0.0001)
        XCTAssertEqual(normalizedAngle(appKitForwardHeading), CGFloat.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(
            visualCursorAppKitForwardHeading(
                renderRotation: 0,
                artworkNeutralHeading: SoftwareCursorGlyphMetrics.targetNeutralHeading
            ),
            3 * CGFloat.pi / 4,
            accuracy: 0.0001
        )
    }

    func testCursorMotionPathStartsAndEndsAtExpectedPoints() {
        let path = CursorMotionPath(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 210, y: 120)
        )

        XCTAssertEqual(path.point(at: 0), CGPoint(x: 10, y: 20))
        XCTAssertEqual(path.point(at: 1), CGPoint(x: 210, y: 120))

        let midpoint = path.point(at: 0.5)
        XCTAssertNotEqual(midpoint.x, 110)
        XCTAssertNotEqual(midpoint.y, 70)
    }

    func testCursorMotionPathSupportsStraightVariantForConservativeFallback() {
        let straightPath = CursorMotionPath(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 210, y: 120),
            curveDirection: 0,
            curveScale: 0
        )

        XCTAssertEqual(straightPath.curveScale, 0)
        XCTAssertEqual(straightPath.point(at: 0), CGPoint(x: 10, y: 20))
        XCTAssertEqual(straightPath.point(at: 1), CGPoint(x: 210, y: 120))

        let midpoint = straightPath.point(at: 0.5)
        XCTAssertEqual(midpoint.x, 110, accuracy: 0.001)
        XCTAssertEqual(midpoint.y, 70, accuracy: 0.001)
    }

    func testOfficialCursorMotionModelBuildsTwentyCandidates() {
        let candidates = OfficialCursorMotionModel.makeCandidates(
            start: CGPoint(x: 100, y: 120),
            end: CGPoint(x: 720, y: 380),
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        XCTAssertEqual(candidates.count, 20)
    }

    func testOfficialCursorMotionModelChoosesScaledBaseForReferenceSample() {
        let candidates = OfficialCursorMotionModel.makeCandidates(
            start: CGPoint(x: 100, y: 120),
            end: CGPoint(x: 720, y: 380),
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        let chosen = OfficialCursorMotionModel.chooseBestCandidate(from: candidates)

        XCTAssertEqual(chosen?.identifier, "a1.05-b1.00-positive")
        XCTAssertEqual(chosen?.kind, .arched)
    }

    func testOfficialCursorMotionGuideProjectionFollowsPathBasisInsteadOfFixedScreenBias() throws {
        let rightUpCandidates = OfficialCursorMotionModel.makeCandidates(
            start: CGPoint(x: 120, y: 620),
            end: CGPoint(x: 960, y: 140),
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )
        let leftUpCandidates = OfficialCursorMotionModel.makeCandidates(
            start: CGPoint(x: 960, y: 620),
            end: CGPoint(x: 120, y: 140),
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        let rightUpStartControl = try XCTUnwrap(
            rightUpCandidates.first(where: { $0.identifier == "base-full-guide" })?.path.startControl
        )
        let leftUpStartControl = try XCTUnwrap(
            leftUpCandidates.first(where: { $0.identifier == "base-full-guide" })?.path.startControl
        )

        XCTAssertLessThan(rightUpStartControl.x, 120)
        XCTAssertGreaterThan(leftUpStartControl.x, 960)
    }

    func testOfficialCursorMotionSpringCloseEnoughTimeMatchesRecoveredReference() {
        XCTAssertEqual(OfficialCursorMotionModel.closeEnoughTime, 1.429166666666663, accuracy: 0.000_001)
    }

    func testHeadingDrivenMotionPrefersNearDirectPathWhenHeadingsAlreadyAlign() throws {
        let start = CGPoint(x: 120, y: 120)
        let end = CGPoint(x: 920, y: 320)
        let direction = normalizedVector(from: start, to: end)

        let candidates = HeadingDrivenCursorMotionModel.makeCandidates(
            start: start,
            end: end,
            bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
            startForward: direction,
            endForward: direction
        )
        let chosen = try XCTUnwrap(HeadingDrivenCursorMotionModel.chooseBestCandidate(from: candidates))
        let directDistance = hypot(end.x - start.x, end.y - start.y)

        XCTAssertEqual(chosen.side, 0)
        XCTAssertLessThan(chosen.measurement.totalTurn, 0.45)
        XCTAssertLessThan(chosen.measurement.length, directDistance * 1.03)
    }

    func testHeadingDrivenMotionPrefersTurnaroundArcWhenStartHeadingOpposesTravel() throws {
        let start = CGPoint(x: 220, y: 520)
        let end = CGPoint(x: 900, y: 280)
        let direction = normalizedVector(from: start, to: end)
        let opposite = CGVector(dx: -direction.dx, dy: -direction.dy)

        let directReference = try XCTUnwrap(
            HeadingDrivenCursorMotionModel.chooseBestCandidate(
                from: HeadingDrivenCursorMotionModel.makeCandidates(
                    start: start,
                    end: end,
                    bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
                    startForward: direction,
                    endForward: direction
                )
            )
        )
        let turnaround = try XCTUnwrap(
            HeadingDrivenCursorMotionModel.chooseBestCandidate(
                from: HeadingDrivenCursorMotionModel.makeCandidates(
                    start: start,
                    end: end,
                    bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
                    startForward: opposite,
                    endForward: direction
                )
            )
        )

        XCTAssertNotEqual(turnaround.side, 0)
        XCTAssertGreaterThan(turnaround.measurement.totalTurn, directReference.measurement.totalTurn + 0.8)
        XCTAssertGreaterThan(turnaround.measurement.length, directReference.measurement.length * 1.04)
    }

    func testCursorVisualDynamicsOvershootsAfterTargetStops() {
        let samples = simulateCursorVisualDynamics(
            stopTime: 0.18,
            targetDistance: 320,
            totalTime: 0.75
        )

        let maxX = samples.map(\.tipPosition.x).max() ?? 0
        XCTAssertGreaterThan(maxX, 320.5)
        XCTAssertLessThan(samples[32].fogOffset.dx, -0.25)
    }

    func testCursorVisualDynamicsKeepsAngleInertiaAfterTargetStops() {
        let samples = simulateCursorVisualDynamics(
            stopTime: 0.16,
            targetDistance: 280,
            totalTime: 0.92
        )

        let rotationJustAfterStop = abs(samples[42].rotation)
        let finalRotation = abs(samples.last?.rotation ?? 0)

        XCTAssertGreaterThan(rotationJustAfterStop, 0.03)
        XCTAssertLessThan(finalRotation, 0.02)
    }

    func testCursorVisualDynamicsTracksMovementHeadingInsteadOfOnlyWiggling() {
        let samples = simulateCursorVisualDynamics(
            stopTime: 0.45,
            targetDistance: 360,
            totalTime: 0.50
        )

        let peakRotation = samples.prefix(120).map { abs($0.rotation) }.max() ?? 0

        XCTAssertGreaterThan(peakRotation, 1.5)
    }

    private func makeSnapshot(treeLines: [String], focusedSummary: String?, selectedText: String? = nil) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "Feishu",
                bundleIdentifier: "com.electron.lark",
                pid: 18_465,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Feishu",
            windowBounds: nil,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .accessibility,
            treeLines: treeLines,
            focusedSummary: focusedSummary,
            selectedText: selectedText,
            elements: [:]
        )
    }

    private func simulateCursorVisualDynamics(
        stopTime: CGFloat,
        targetDistance: CGFloat,
        totalTime: CGFloat,
        stepCount: Int = 240
    ) -> [CursorVisualRenderState] {
        var state = CursorVisualDynamicsAnimator.state(at: CGPoint(x: 0, y: 0))
        var samples: [CursorVisualRenderState] = []

        for step in 1...stepCount {
            let time = totalTime * (CGFloat(step) / CGFloat(stepCount))
            let targetX: CGFloat
            if time < stopTime {
                targetX = targetDistance * (time / stopTime)
            } else {
                targetX = targetDistance
            }

            let result = CursorVisualDynamicsAnimator.advance(
                state: state,
                targetTipPosition: CGPoint(x: targetX, y: 0),
                targetTime: time,
                baseHeading: -(3 * .pi / 4)
            )
            state = result.state
            samples.append(result.renderState)
        }

        return samples
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle
        while value > .pi {
            value -= 2 * .pi
        }
        while value < -.pi {
            value += 2 * .pi
        }
        return value
    }

    private func normalizedVector(from start: CGPoint, to end: CGPoint) -> CGVector {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}
