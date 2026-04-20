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

    func testKeyPressParserSupportsCommandStyleChord() throws {
        let parsed = try KeyPressParser.parse("super+c")
        XCTAssertEqual(parsed.displayValue, "c")
        XCTAssertEqual(parsed.modifiers.count, 1)
    }

    func testInitializeResponseContainsToolsCapability() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.14"},"capabilities":{}}}"#)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains(#""name":"open-computer-use""#))
        XCTAssertTrue(response!.contains(#""tools":{"listChanged":false}"#))
    }

    func testInitializeResponseContainsComputerUseInstructions() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = try XCTUnwrap(
            server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.14"},"capabilities":{}}}"#)
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

    func testCursorWindowGeometryAnchorsTipPosition() {
        let geometry = CursorWindowGeometry(
            windowSize: CGSize(width: 128, height: 128),
            tipAnchor: CGPoint(x: 44, y: 88)
        )
        let tipPosition = CGPoint(x: 1200, y: 800)

        XCTAssertEqual(geometry.origin(forTipPosition: tipPosition), CGPoint(x: 1156, y: 712))
        XCTAssertEqual(geometry.tipPosition(forOrigin: CGPoint(x: 1156, y: 712)), tipPosition)
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
                baseHeading: 3 * .pi / 4
            )
            state = result.state
            samples.append(result.renderState)
        }

        return samples
    }

    private func normalizedVector(from start: CGPoint, to end: CGPoint) -> CGVector {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}
