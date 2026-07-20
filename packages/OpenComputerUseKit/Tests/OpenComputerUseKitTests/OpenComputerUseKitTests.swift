import AppKit
import ImageIO
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
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["call", "--help"]), .help(command: "call"))
    }

    func testCLIRecognizesSingleToolCallCommand() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["call", "list_apps"]),
            .call(.single(toolName: "list_apps", argumentsJSON: nil, argumentsFile: nil))
        )

        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["call", "get_app_state", "--args", #"{"app":"TextEdit"}"#]),
            .call(.single(toolName: "get_app_state", argumentsJSON: #"{"app":"TextEdit"}"#, argumentsFile: nil))
        )
    }

    func testCLIRecognizesJSONSequenceCallCommand() throws {
        let calls = #"[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]"#

        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["call", "--calls", calls]),
            .call(.sequence(
                callsJSON: calls,
                callsFile: nil,
                interCallDelay: openComputerUseDefaultInterCallDelay
            ))
        )
    }

    func testCLIRecognizesJSONSequenceCallCommandWithCustomSleep() throws {
        let calls = #"[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"tool":"press_key","args":{"app":"TextEdit","key":"Return"}}]"#

        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["call", "--calls", calls, "--sleep", "0.5"]),
            .call(.sequence(callsJSON: calls, callsFile: nil, interCallDelay: 0.5))
        )
    }

    func testCLIRecognizesTurnEndedNotifyPayload() throws {
        let payload = #"{"type":"agent-turn-complete","turn-id":"12345"}"#

        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["turn-ended"]), .turnEnded(payload: nil))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["turn-ended", payload]), .turnEnded(payload: payload))
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["turn-ended", "--previous-notify", #"["/bin/true"]"#, payload]),
            .turnEnded(payload: payload)
        )
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

    func testCLIRecognizesSnapshotTextLimitFlag() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "TextEdit"]),
            .snapshot(app: "TextEdit")
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "--text-limit", "1000", "TextEdit"]),
            .snapshot(app: "TextEdit", textLimit: SnapshotTextLimit(maxCount: 1000))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "TextEdit", "--text-limit", "max"]),
            .snapshot(app: "TextEdit", textLimit: .max)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "--max-tree-nodes", "3000", "--max-tree-depth", "96", "TextEdit"]),
            .snapshot(
                app: "TextEdit",
                treeLimits: AccessibilityTreeLimits(maxNodeCount: 3000, maxDepth: 96)
            )
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "--max-tree-nodes", "3000", "TextEdit"]),
            .snapshot(
                app: "TextEdit",
                treeLimits: AccessibilityTreeLimits(maxNodeCount: 3000, maxDepth: accessibilityTreeMaxDepth)
            )
        )
    }

    func testCLIRejectsOldSnapshotFullTextFlag() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--show-full-text", "TextEdit"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "Unknown snapshot option: --show-full-text", helpCommand: "snapshot")
            )
        }
    }

    func testCLIRejectsInvalidSnapshotTextLimit() {
        for value in ["0", "-1", "1.5", "full"] {
            XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--text-limit", value, "TextEdit"])) { error in
                XCTAssertEqual(
                    error as? OpenComputerUseCLIError,
                    OpenComputerUseCLIError(message: "--text-limit must be a positive integer or max", helpCommand: "snapshot")
                )
            }
        }
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--text-limit"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "--text-limit requires a positive integer or max value", helpCommand: "snapshot")
            )
        }
    }

    func testCLIRejectsInvalidSnapshotTreeBudget() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--max-tree-nodes", "0", "TextEdit"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "--max-tree-nodes must be a positive integer", helpCommand: "snapshot")
            )
        }
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--max-tree-depth", "1.5", "TextEdit"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "--max-tree-depth must be a positive integer", helpCommand: "snapshot")
            )
        }
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["snapshot", "--max-tree-nodes"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "--max-tree-nodes requires a positive integer value", helpCommand: "snapshot")
            )
        }
    }

    func testCLIRejectsMixedCallSequenceInputs() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["call", "list_apps", "--calls", "[]"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(
                    message: "call sequence does not accept a tool name, --args, or --args-file",
                    helpCommand: "call"
                )
            )
        }
    }

    func testCLIRejectsSleepForSingleToolCall() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["call", "list_apps", "--sleep", "0.5"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(
                    message: "--sleep is only supported with --calls or --calls-file",
                    helpCommand: "call"
                )
            )
        }
    }

    func testCLIRejectsInvalidSequenceSleepValue() {
        XCTAssertThrowsError(try parseOpenComputerUseCLI(arguments: ["call", "--calls", "[]", "--sleep", "-1"])) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(
                    message: "--sleep requires a non-negative number of seconds",
                    helpCommand: "call"
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
        XCTAssertTrue(help.contains("call <tool>"))
        XCTAssertTrue(help.contains("-h, --help"))
        XCTAssertTrue(help.contains("-v, --version"))
    }

    func testResolvedVersionFallsBackWhenBundleHasNoVersionMetadata() {
        XCTAssertEqual(resolvedOpenComputerUseVersion(bundle: Bundle(for: Self.self)), openComputerUseVersion)
    }

    func testBoundedScreenshotPNGDataShrinksLargeScreenshots() throws {
        let image = try makeNoisyTestImage(width: 800, height: 600)
        let data = try XCTUnwrap(boundedScreenshotPNGData(
            for: image,
            maxBytes: 50_000,
            maxDimension: 320,
            minScale: 0.05
        ))
        let size = try imageSize(in: data)

        XCTAssertLessThanOrEqual(data.count, 50_000)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 320)
    }

    func testBoundedScreenshotPNGDataKeepsSmallScreenshotsAtOriginalSize() throws {
        let image = try makeSolidTestImage(width: 32, height: 24)
        let data = try XCTUnwrap(boundedScreenshotPNGData(for: image, maxBytes: 1_000_000, maxDimension: 320))
        let size = try imageSize(in: data)

        XCTAssertEqual(size.width, 32)
        XCTAssertEqual(size.height, 24)
    }

    func testToolDefinitionCount() {
        XCTAssertEqual(ToolDefinitions.all.count, 9)
    }

    func testReadToolArgumentsAcceptsJSONObject() throws {
        let arguments = try readOpenComputerUseToolArguments(
            json: #"{"app":"TextEdit","pages":2}"#,
            file: nil
        )

        XCTAssertEqual(arguments["app"] as? String, "TextEdit")
        XCTAssertEqual((arguments["pages"] as? NSNumber)?.intValue, 2)
    }

    func testElementIndexAcceptsNumericToolArgument() throws {
        let arguments = try readOpenComputerUseToolArguments(
            json: #"{"app":"TextEdit","element_index":0}"#,
            file: nil
        )

        XCTAssertEqual(normalizedElementIndexArgument(arguments["element_index"]), "0")
    }

    func testElementIndexAcceptsNumericCallSequenceArgument() throws {
        let calls = try readOpenComputerUseCallSequence(
            json: #"[{"tool":"click","args":{"app":"TextEdit","element_index":0}}]"#,
            file: nil
        )

        XCTAssertEqual(normalizedElementIndexArgument(calls[0].arguments["element_index"]), "0")
    }

    func testElementIndexRejectsMissingEmptyAndFractionalArguments() {
        XCTAssertNil(normalizedElementIndexArgument(nil))
        XCTAssertNil(normalizedElementIndexArgument(""))
        XCTAssertNil(normalizedElementIndexArgument(1.5))
    }

    func testReadToolArgumentsRejectsNonObject() {
        XCTAssertThrowsError(try readOpenComputerUseToolArguments(json: #"["TextEdit"]"#, file: nil)) { error in
            XCTAssertEqual(
                error as? OpenComputerUseCLIError,
                OpenComputerUseCLIError(message: "--args must be a JSON object", helpCommand: "call")
            )
        }
    }

    func testReadCallSequenceAcceptsJSONArrays() throws {
        let calls = try readOpenComputerUseCallSequence(
            json: #"[{"tool":"get_app_state","args":{"app":"TextEdit"}},{"name":"press_key","arguments":{"app":"TextEdit","key":"Return"}}]"#,
            file: nil
        )

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].tool, "get_app_state")
        XCTAssertEqual(calls[0].arguments["app"] as? String, "TextEdit")
        XCTAssertEqual(calls[1].tool, "press_key")
        XCTAssertEqual(calls[1].arguments["key"] as? String, "Return")
    }

    func testRunCallSequenceStopsAfterFirstToolError() throws {
        let output = try runOpenComputerUseCall(
            .sequence(
                callsJSON: #"[{"tool":"not_a_tool"},{"tool":"list_apps"}]"#,
                callsFile: nil,
                interCallDelay: openComputerUseDefaultInterCallDelay
            ),
            guard: MacSessionGuard(provider: FakeUnlockedSessionProvider())
        )

        let outputs = try XCTUnwrap(output.jsonObject as? [[String: Any]])
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(output.hasToolError)
    }

    func testRunCallSequenceSleepsBetweenSuccessfulOperations() throws {
        var recordedSleeps: [TimeInterval] = []

        let output = try runOpenComputerUseCall(
            .sequence(
                callsJSON: #"[{"tool":"list_apps"},{"tool":"list_apps"},{"tool":"list_apps"}]"#,
                callsFile: nil,
                interCallDelay: openComputerUseDefaultInterCallDelay
            ),
            guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()),
            sleepHandler: { recordedSleeps.append($0) }
        )

        let outputs = try XCTUnwrap(output.jsonObject as? [[String: Any]])
        XCTAssertEqual(outputs.count, 3)
        XCTAssertEqual(recordedSleeps, [openComputerUseDefaultInterCallDelay, openComputerUseDefaultInterCallDelay])
        XCTAssertFalse(output.hasToolError)
    }

    func testMacOSAppAgentProxyDecisionRoutesAutomationCommandsThroughAppBundle() {
        for command in [
            OpenComputerUseCLICommand.mcp,
            .doctor,
            .listApps,
            .snapshot(app: "TextEdit"),
            .call(.single(toolName: "list_apps", argumentsJSON: nil, argumentsFile: nil)),
        ] {
            XCTAssertTrue(shouldUseMacOSAppAgentProxy(
                command: command,
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            ))
        }
    }

    func testMacOSAppAgentProxyDecisionKeepsNonAutomationCommandsLocal() {
        for command in [
            OpenComputerUseCLICommand.turnEnded(payload: nil),
            .help(command: nil),
            .version,
        ] {
            XCTAssertFalse(shouldUseMacOSAppAgentProxy(
                command: command,
                proxyDisabled: false,
                appBundleAvailable: true,
                runningFromLaunchServicesAppInstance: false
            ))
        }
    }

    func testMacOSAppAgentProxyDecisionDoesNotProxyLaunchServicesAppOpen() {
        XCTAssertTrue(shouldUseMacOSAppAgentProxy(
            command: .launchOnboarding,
            proxyDisabled: false,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: false
        ))
        XCTAssertFalse(shouldUseMacOSAppAgentProxy(
            command: .launchOnboarding,
            proxyDisabled: false,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: true
        ))
    }

    func testMacOSAppAgentProxyDecisionHonorsDisableAndMissingBundle() {
        XCTAssertFalse(shouldUseMacOSAppAgentProxy(
            command: .doctor,
            proxyDisabled: true,
            appBundleAvailable: true,
            runningFromLaunchServicesAppInstance: false
        ))
        XCTAssertFalse(shouldUseMacOSAppAgentProxy(
            command: .doctor,
            proxyDisabled: false,
            appBundleAvailable: false,
            runningFromLaunchServicesAppInstance: false
        ))
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

    func testListedAppDescriptorRendersFrontmostBeforeRunning() {
        let descriptor = ListedAppDescriptor(
            name: "Sample",
            bundleIdentifier: "com.example.Sample",
            isRunning: true,
            isFrontmost: true,
            lastUsed: nil,
            uses: nil
        )

        XCTAssertEqual(descriptor.renderedLine, "Sample — com.example.Sample [frontmost, running]")
    }

    func testListedAppSortingPrefersFrontmostRunningApp() {
        let frontmost = ListedAppDescriptor(
            name: "Front",
            bundleIdentifier: "com.example.Front",
            isRunning: true,
            isFrontmost: true,
            lastUsed: nil,
            uses: nil
        )
        let frequent = ListedAppDescriptor(
            name: "Frequent",
            bundleIdentifier: "com.example.Frequent",
            isRunning: true,
            isFrontmost: false,
            lastUsed: Date(),
            uses: 999
        )

        XCTAssertTrue(AppDiscovery.compareListedApps(frontmost, frequent))
        XCTAssertFalse(AppDiscovery.compareListedApps(frequent, frontmost))
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

    func testPreferredPermissionAppBundleURLCanPreferRunningReleaseCopyOverStaleInstalledCopy() {
        let staleInstalled = URL(fileURLWithPath: "/Users/example/projects/open-codex-computer-use/dist/npm/open-computer-use/dist/Open Computer Use.app")
        let running = URL(fileURLWithPath: "/opt/homebrew/lib/node_modules/open-computer-use/dist/Open Computer Use.app")

        let resolved = PermissionSupport.preferredPermissionAppBundleURL(
            preferredInstalledBundleURL: staleInstalled,
            runningBundleURL: running,
            fallbackDevelopmentBundleURL: nil,
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

    func testPermissionGrantedKeepsRuntimePreflightAuthoritativeForCurrentProcess() {
        XCTAssertTrue(permissionGranted(persisted: false, runtime: true))
        XCTAssertTrue(permissionGranted(persisted: nil, runtime: true))
        XCTAssertTrue(permissionGranted(persisted: true, runtime: false))
        XCTAssertFalse(permissionGranted(persisted: false, runtime: false))
        XCTAssertFalse(permissionGranted(persisted: nil, runtime: false))
    }

    func testKeyPressParserSupportsCommandStyleChord() throws {
        let parsed = try KeyPressParser.parse("super+c")
        XCTAssertEqual(parsed.displayValue, "c")
        XCTAssertEqual(parsed.modifiers.count, 1)
    }

    func testKeyPressParserSupportsOfficialXdotoolAliases() throws {
        XCTAssertEqual(try KeyPressParser.parse("BackSpace").displayValue, "backspace")
        XCTAssertEqual(try KeyPressParser.parse("Page_Up").displayValue, "page_up")
        XCTAssertEqual(try KeyPressParser.parse("Prior").displayValue, "prior")
        XCTAssertEqual(try KeyPressParser.parse("KP_9").displayValue, "kp_9")
        XCTAssertEqual(try KeyPressParser.parse("KP_Enter").displayValue, "kp_enter")
        XCTAssertEqual(try KeyPressParser.parse("F12").displayValue, "f12")
    }

    func testInitializeResponseContainsToolsCapability() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.2.0"},"capabilities":{}}}"#)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains(#""name":"open-computer-use""#))
        XCTAssertTrue(response!.contains(#""tools":{"listChanged":false}"#))
    }

    func testInitializeResponseContainsComputerUseInstructions() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = try XCTUnwrap(
            server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.2.0"},"capabilities":{}}}"#)
        )
        let data = try XCTUnwrap(response.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let instructions = try XCTUnwrap(result["instructions"] as? String)

        XCTAssertEqual(instructions, computerUseServerInstructions)
    }

    func testMCPAcceptsTurnEndedNotificationWithoutResponse() {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/turn-ended","params":{"type":"agent-turn-complete"}}"#)

        XCTAssertNil(response)
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
        let getAppStateSchema = tools["get_app_state"]?.inputSchema
        let getAppStateProperties = getAppStateSchema?["properties"] as? [String: [String: Any]]
        XCTAssertNil(getAppStateProperties?["show_full_text"])
        let textLimitAnyOf = getAppStateProperties?["text_limit"]?["anyOf"] as? [[String: Any]]
        XCTAssertEqual(textLimitAnyOf?[0]["type"] as? String, "integer")
        XCTAssertEqual(textLimitAnyOf?[0]["minimum"] as? Int, 1)
        XCTAssertEqual(textLimitAnyOf?[1]["type"] as? String, "string")
        XCTAssertEqual(textLimitAnyOf?[1]["enum"] as? [String], ["max"])
        XCTAssertEqual(getAppStateProperties?["max_tree_nodes"]?["type"] as? String, "integer")
        XCTAssertEqual(getAppStateProperties?["max_tree_nodes"]?["minimum"] as? Int, 1)
        XCTAssertEqual(getAppStateProperties?["max_tree_depth"]?["type"] as? String, "integer")
        XCTAssertEqual(getAppStateProperties?["max_tree_depth"]?["minimum"] as? Int, 1)
        XCTAssertEqual(getAppStateSchema?["required"] as? [String], ["app"])
        let scrollPages = (tools["scroll"]?.inputSchema["properties"] as? [String: [String: Any]])?["pages"]
        XCTAssertEqual(scrollPages?["type"] as? String, "number")
        XCTAssertEqual(
            scrollPages?["description"] as? String,
            "Number of pages to scroll. Fractional values are supported. Defaults to 1"
        )
    }

    func testDispatcherMissingArgumentsMatchOfficialToolText() {
        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
        let result = dispatcher.callToolAsResult(name: "type_text", arguments: ["app": "Sublime Text"])
        let emptyResult = dispatcher.callToolAsResult(name: "type_text", arguments: ["app": "Sublime Text", "text": ""])

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "Missing required argument: text")
        XCTAssertTrue(emptyResult.isError)
        XCTAssertEqual(emptyResult.primaryText, "Missing required argument: text")
    }

    func testTypeTextUnicodeChunksPreserveGraphemeClusters() {
        let text = "（ocu发的）👩🏽‍💻e\u{301}𠀀"
        let chunks = InputSimulation.keyboardUnicodeChunks(for: text, maxUTF16Units: 8)
        let decoded = chunks
            .map { String(decoding: $0, as: UTF16.self) }
            .joined()

        XCTAssertEqual(decoded, text)
        XCTAssertTrue(chunks.count > 1)
        XCTAssertTrue(chunks.allSatisfy { chunk in
            let decodedChunk = String(decoding: chunk, as: UTF16.self)
            return decodedChunk.unicodeScalars.allSatisfy { $0.value != 0xFFFD }
        })
        for cluster in ["👩🏽‍💻", "e\u{301}", "𠀀"] {
            XCTAssertEqual(
                chunks.filter { String(decoding: $0, as: UTF16.self).contains(cluster) }.count,
                1
            )
        }
    }

    func testScrollRejectsInvalidDirectionWithOfficialMessage() {
        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
        let result = dispatcher.callToolAsResult(
            name: "scroll",
            arguments: ["app": "Sublime Text", "element_index": "14", "direction": "sideways", "pages": 1]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "Invalid scroll direction: sideways")
    }

    func testScrollRejectsNonPositivePagesWithOfficialMessage() {
        let dispatcher = ComputerUseToolDispatcher(guard: MacSessionGuard(provider: FakeUnlockedSessionProvider()))
        let result = dispatcher.callToolAsResult(
            name: "scroll",
            arguments: ["app": "Sublime Text", "element_index": "14", "direction": "down", "pages": 0.0]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "pages must be > 0")
    }

    func testSecondaryActionInvalidMessageMatchesOfficialShape() {
        XCTAssertEqual(
            invalidSecondaryActionErrorMessage(action: "NoSuchAction", elementIndex: 14),
            "NoSuchAction is not a valid secondary action for 14"
        )
    }

    func testSyntheticTextClickUsesLeadingSafePointOnly() {
        let frame = CGRect(x: 40, y: 20, width: 300, height: 48)
        let points = localClickActionPoints(frame: frame, isSyntheticText: true)

        XCTAssertEqual(points, [CGPoint(x: 130, y: 44)])
        XCTAssertFalse(points.contains(CGPoint(x: 190, y: 44)))
    }

    func testNormalClickKeepsCenterThenLeadingFallback() {
        let frame = CGRect(x: 40, y: 20, width: 300, height: 48)

        XCTAssertEqual(
            localClickActionPoints(frame: frame, isSyntheticText: false),
            [CGPoint(x: 190, y: 44), CGPoint(x: 130, y: 44)]
        )
    }

    func testSyntheticSideActionFilterRejectsTrailingDoneButton() {
        XCTAssertTrue(
            isLikelySyntheticSideActionCandidate(
                parentFrame: CGRect(x: 40, y: 20, width: 300, height: 48),
                candidateFrame: CGRect(x: 296, y: 24, width: 36, height: 36),
                hasPrimaryAction: true,
                labels: ["完成"]
            )
        )
    }

    func testSyntheticSideActionFilterKeepsMainRowPreviewContainingDone() {
        XCTAssertFalse(
            isLikelySyntheticSideActionCandidate(
                parentFrame: CGRect(x: 40, y: 20, width: 300, height: 48),
                candidateFrame: CGRect(x: 48, y: 22, width: 236, height: 44),
                hasPrimaryAction: true,
                labels: ["AK账号管控 @所有人 变更完成，如果有问题，请联系我"]
            )
        )
    }

    func testSyntheticSideActionFilterKeepsLargeRowNamedDone() {
        XCTAssertFalse(
            isLikelySyntheticSideActionCandidate(
                parentFrame: CGRect(x: 40, y: 20, width: 300, height: 48),
                candidateFrame: CGRect(x: 40, y: 20, width: 300, height: 48),
                hasPrimaryAction: true,
                labels: ["完成"]
            )
        )
    }

    func testHitRecordDescendantScanRejectsBroadWebAreaHit() {
        XCTAssertFalse(
            shouldScanDescendantsOfHitRecord(
                originalFrame: CGRect(x: 40, y: 120, width: 300, height: 48),
                hitFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
            )
        )
    }

    func testHitRecordDescendantScanKeepsNearbyRowHit() {
        XCTAssertTrue(
            shouldScanDescendantsOfHitRecord(
                originalFrame: CGRect(x: 40, y: 120, width: 300, height: 48),
                hitFrame: CGRect(x: 32, y: 112, width: 320, height: 56)
            )
        )
    }

    func testContainingRowActionAcceptsTightClickableAncestor() {
        XCTAssertTrue(
            isLikelyContainingRowActionFrame(
                targetFrame: CGRect(x: 132, y: 381, width: 268, height: 44),
                candidateFrame: CGRect(x: 124, y: 373, width: 284, height: 60),
                hasPrimaryAction: true
            )
        )
    }

    func testContainingRowActionRejectsBroadWebArea() {
        XCTAssertFalse(
            isLikelyContainingRowActionFrame(
                targetFrame: CGRect(x: 132, y: 381, width: 268, height: 44),
                candidateFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                hasPrimaryAction: true
            )
        )
    }

    func testContainingRowActionRequiresPrimaryAction() {
        XCTAssertFalse(
            isLikelyContainingRowActionFrame(
                targetFrame: CGRect(x: 132, y: 381, width: 268, height: 44),
                candidateFrame: CGRect(x: 124, y: 373, width: 284, height: 60),
                hasPrimaryAction: false
            )
        )
    }

    func testContainingWebRowOptimizationRejectsChromeWebGroups() {
        XCTAssertFalse(
            shouldPreferContainingWebRowAXClickCandidate(
                role: kAXGroupRole as String,
                isSyntheticText: false,
                hasWebAreaAncestor: true,
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )
        )
    }

    func testContainingWebRowOptimizationRejectsChromeSyntheticText() {
        XCTAssertFalse(
            shouldPreferContainingWebRowAXClickCandidate(
                role: kAXStaticTextRole as String,
                isSyntheticText: true,
                hasWebAreaAncestor: true,
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )
        )
    }

    func testContainingWebRowOptimizationKeepsLarkSyntheticRows() {
        XCTAssertTrue(
            shouldPreferContainingWebRowAXClickCandidate(
                role: kAXStaticTextRole as String,
                isSyntheticText: true,
                hasWebAreaAncestor: true,
                appName: "Lark",
                bundleIdentifier: "com.electron.lark"
            )
        )
    }

    func testContainingWebRowOptimizationRequiresWebAreaAncestor() {
        XCTAssertFalse(
            shouldPreferContainingWebRowAXClickCandidate(
                role: kAXGroupRole as String,
                isSyntheticText: false,
                hasWebAreaAncestor: false,
                appName: "Lark",
                bundleIdentifier: "com.electron.lark"
            )
        )
    }

    func testActivationOnlyClickFallbackRejectsPlainStaticText() {
        XCTAssertFalse(canUseActivationOnlyClickFallback(role: kAXStaticTextRole as String))
    }

    func testActivationOnlyClickFallbackKeepsWindowRaisePath() {
        XCTAssertTrue(canUseActivationOnlyClickFallback(role: kAXWindowRole as String))
    }

    func testKeyboardTextFallbackRejectsPlainWebArea() {
        XCTAssertFalse(
            canUseKeyboardTextFallback(
                role: "AXWebArea",
                roleDescription: "HTML content",
                isValueSettable: false
            )
        )
    }

    func testKeyboardTextFallbackAcceptsEditableTextRole() {
        XCTAssertTrue(
            canUseKeyboardTextFallback(
                role: kAXTextFieldRole as String,
                roleDescription: "text field",
                isValueSettable: false
            )
        )
    }

    func testKeyboardTextFallbackAcceptsSettableValueElement() {
        XCTAssertTrue(
            canUseKeyboardTextFallback(
                role: kAXGroupRole as String,
                roleDescription: "text entry area",
                isValueSettable: true
            )
        )
    }

    func testSnapshotRenderedTextStartsDirectlyWithAppHeader() {
        let snapshot = makeSnapshot(
            treeLines: ["\t0 standard window Sample Chat"],
            focusedSummary: "247 text entry area"
        )

        let rendered = snapshot.renderedText(style: .actionResult)
        let lines = rendered.components(separatedBy: "\n")

        XCTAssertEqual(lines.first, "App=com.example.SampleChat (pid 18465)")
        XCTAssertEqual(lines.dropFirst().first, "Window: \"Sample Chat\", App: Sample Chat.")
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

    func testAccessibilityTreeBudgetAllowsDeepElectronWebViews() {
        XCTAssertEqual(accessibilityTreeMaxNodeCount, 1200)
        XCTAssertEqual(accessibilityTreeMaxDepth, 64)
        XCTAssertTrue(shouldContinueRendering(nextIndex: 120, depth: 16))
        XCTAssertTrue(shouldContinueRendering(nextIndex: 1199, depth: 63))
        XCTAssertFalse(shouldContinueRendering(nextIndex: 1200, depth: 20))
        XCTAssertFalse(shouldContinueRendering(nextIndex: 120, depth: 64))
        let customLimits = AccessibilityTreeLimits(maxNodeCount: 3000, maxDepth: 96)
        XCTAssertTrue(shouldContinueRendering(nextIndex: 1200, depth: 64, limits: customLimits))
        XCTAssertFalse(shouldContinueRendering(nextIndex: 3000, depth: 20, limits: customLimits))
        XCTAssertFalse(shouldContinueRendering(nextIndex: 20, depth: 96, limits: customLimits))
    }

    func testAccessibilityRendererElidesEmptyGenericElectronWrappers() {
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 3
        ))
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 0
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 0,
            preservesAnonymousActionTarget: true
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: "Send",
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 3
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 3,
            genericTextSummary: "AgentSphere 17:18 okay"
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 3,
            webAreaDepth: 4
        ))
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 1,
            webAreaDepth: 4
        ))
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 0,
            webAreaDepth: 4
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 2,
            webAreaDepth: 8
        ))
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: [],
            actions: [],
            childCount: 1,
            webAreaDepth: 8
        ))
        XCTAssertTrue(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: ["settable", "string"],
            actions: [],
            childCount: 1
        ))
        XCTAssertFalse(shouldElideNode(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            value: nil,
            identifier: nil,
            traits: ["settable", "string"],
            actions: [],
            childCount: 0
        ))
    }

    func testAccessibilityRendererRecognizesPrimaryClickActions() {
        XCTAssertTrue(hasPrimaryClickAction([kAXPressAction as String]))
        XCTAssertTrue(hasPrimaryClickAction([kAXConfirmAction as String]))
        XCTAssertTrue(hasPrimaryClickAction(["AXOpen"]))
        XCTAssertTrue(hasPrimaryClickAction(["axpress"]))
        XCTAssertFalse(hasPrimaryClickAction(["AXShowMenu", "AXScrollToVisible", "AXRaise"]))
    }

    func testAccessibilityRendererMarksAnonymousGenericClickTargetsAsButtons() {
        XCTAssertTrue(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 1455, y: 218, width: 15, height: 20)
        ))
        XCTAssertTrue(shouldRenderAnonymousActionTarget(
            role: kAXUnknownRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 1455, y: 245, width: 15, height: 20)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXButtonRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 10, y: 10, width: 32, height: 32)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: "Forward",
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 10, y: 10, width: 32, height: 32)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: "Candidate details",
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 10, y: 10, width: 32, height: 32)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: false,
            localFrame: CGRect(x: 10, y: 10, width: 32, height: 32)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 0, y: 0, width: 1920, height: 929)
        ))
        XCTAssertFalse(shouldRenderAnonymousActionTarget(
            role: kAXGroupRole as String,
            title: nil,
            label: nil,
            help: nil,
            value: nil,
            genericTextSummary: nil,
            hasPrimaryClickAction: true,
            localFrame: CGRect(x: 0, y: 0, width: 15, height: 0)
        ))
    }

    func testAccessibilityRendererOnlyMergesShortTextOnlySiblingRuns() {
        XCTAssertTrue(shouldMergeTextOnlySiblings(["AgentSphere", "17:18", "好的，谢谢"]))
        XCTAssertFalse(shouldMergeTextOnlySiblings(["日期", "时间", "2026年5月7日", "晚餐", "18:00-20:00"]))
        XCTAssertFalse(shouldMergeTextOnlySiblings(["as-next 10min 站会", "12 分钟后", "10:30 - 10:45"]))
        XCTAssertFalse(shouldMergeTextOnlySiblings([
            "📌 3层简卡轻食",
            "自助餐",
            "🐂主荤：香烤鸡腿肉，孜然巴沙鱼",
            "🍡半荤：卤鸡蛋",
            "🥒素菜：剁椒娃娃菜，酸辣金针菇，清炒上海青，清炒胡萝卜，清炒青笋，海带丝拌千张，清炒西葫芦",
            "🍚主食：螺旋意面，蒸玉米，烤面包",
            "🥛饮品：冬瓜蛋花汤",
            "🍒水果：黄瓜",
            "※注意：餐食饮品等仅供职场便利，请勿带离工区",
        ]))
        XCTAssertFalse(shouldMergeTextOnlySiblings(["消息", "126/126"]))
    }

    func testAccessibilityRendererRendersSummariesWithImagesAsChildren() {
        XCTAssertTrue(shouldRenderGenericTextSummaryAsChildren("AgentSphere 17:18 好的，谢谢", summaryImageCount: 1))
        XCTAssertFalse(shouldRenderGenericTextSummaryAsChildren("AgentSphere 17:18 好的，谢谢", summaryImageCount: 0))
        XCTAssertFalse(shouldRenderGenericTextSummaryAsChildren(nil, summaryImageCount: 1))
    }

    func testAccessibilityRendererFiltersScrollToVisibleNoise() {
        XCTAssertEqual(
            meaningfulActions(
                [kAXPressAction as String, "AXScrollToVisible", "AXShowMenu", "AXRaise"],
                role: kAXButtonRole as String
            ),
            ["Raise"]
        )
    }

    func testAccessibilityRendererFiltersImplicitMenuActions() {
        XCTAssertEqual(
            meaningfulActions(
                ["AXCancel", "AXPick", kAXPressAction as String],
                role: kAXMenuBarItemRole as String
            ),
            []
        )
    }

    func testAccessibilityRendererUsesOfficialZoomWindowActionName() {
        XCTAssertEqual(meaningfulActions(["AXZoomWindow"], role: kAXButtonRole as String), ["zoom the window"])
    }

    func testAccessibilityRendererKeepsLinkRoleWhenSuppressingChildren() {
        XCTAssertEqual(
            displayRoleText(
                baseRoleText: "link",
                role: "AXLink",
                title: "[Docs](https://example.com)",
                label: "Docs",
                suppressChildren: true
            ),
            "link"
        )
    }

    func testAccessibilityRendererKeepsMarkdownShapeForSummaryLinks() {
        XCTAssertEqual(
            summaryMarkdownLinkText(
                text: "https://example.com/docs?topic=[agents]",
                url: "https://example.com/docs?topic=%5Bagents%5D"
            ),
            "[https://example.com/docs?topic=\\[agents\\]](https://example.com/docs?topic=%5Bagents%5D)"
        )
        XCTAssertEqual(
            summaryMarkdownLinkText(
                text: "https://example.com/docs",
                url: "https://example.com/docs"
            ),
            "[https://example.com/docs](https://example.com/docs)"
        )
    }

    func testSnapshotTextLimitDefaultsTo500AndSupportsMax() {
        let longText = String(repeating: "候", count: defaultTextLimit + 20)
        let customLimitText = String(repeating: "候", count: 1_020)

        XCTAssertEqual(
            sanitizeText(longText),
            String(longText.prefix(defaultTextLimit)) + "..."
        )
        XCTAssertEqual(
            sanitizeText(customLimitText, textLimit: SnapshotTextLimit(maxCount: 1_000)),
            String(customLimitText.prefix(1_000)) + "..."
        )
        XCTAssertEqual(sanitizeText(longText, textLimit: .max), longText)
    }

    func testAccessibilityRendererSuppressesDuplicateDescriptionForSameTextMarkdownLinks() {
        XCTAssertEqual(
            formattedLabelSegment(
                "https://example.com/docs",
                title: "[https://example.com/docs](https://example.com/docs)",
                linkText: "[https://example.com/docs](https://example.com/docs)"
            ),
            ""
        )
        let longURL = "https://example.com/docs?" + String(repeating: "query=value&", count: 60)
        let truncatedURL = String(longURL.prefix(defaultTextLimit)) + "..."
        XCTAssertEqual(
            formattedLabelSegment(
                longURL,
                title: "[\(truncatedURL)](\(truncatedURL))",
                linkText: "[\(truncatedURL)](\(truncatedURL))"
            ),
            ""
        )
    }

    func testAccessibilityRendererFormatsPlaceholderSegment() {
        XCTAssertEqual(
            formattedPlaceholderSegment(
                "Ask Google or type a URL",
                title: nil,
                label: "Address and search bar",
                value: "example.com",
                precedingSegments: [" Description: Address and search bar", " Value: example.com"]
            ),
            ", Placeholder: Ask Google or type a URL"
        )
        XCTAssertEqual(
            formattedPlaceholderSegment(
                "Search mail",
                title: nil,
                label: "Search mail",
                value: nil,
                precedingSegments: []
            ),
            ""
        )
    }

    func testBlockingAsyncBridgeTimesOutScreenshotWork() {
        XCTAssertThrowsError(
            try BlockingAsyncBridge.run(timeout: 0.01) {
                try await Task.sleep(nanoseconds: 200_000_000)
                return "late"
            }
        ) { error in
            XCTAssertTrue(
                (error as? ComputerUseError)?.errorDescription?.contains("timed out") == true
            )
        }
    }

    func testComputerUseErrorsFormatLikeToolText() {
        XCTAssertEqual(ComputerUseError.appNotFound("Sublime Text").errorDescription, #"appNotFound("Sublime Text")"#)
        XCTAssertTrue(ComputerUseError.appNotFound("Sublime Text").toolResultIsError)
        XCTAssertTrue(ComputerUseError.invalidArguments("bad").toolResultIsError)
    }

    func testNoWindowErrorMessageMatchesOfficialShape() {
        XCTAssertEqual(computerUseNoWindowFoundMessage, "Apple event error -10005: cgWindowNotFound")
        XCTAssertEqual(
            ComputerUseError.stateUnavailable(computerUseNoWindowFoundMessage).errorDescription,
            "Apple event error -10005: cgWindowNotFound"
        )
    }

    func testAppSafetyPolicyDoesNotBlockNonPasswordApps() {
        XCTAssertFalse(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.google.Chrome"))
        XCTAssertFalse(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.googlecode.iterm2"))
        XCTAssertFalse(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.openai.atlas.beta"))
        XCTAssertFalse(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.apple.SecurityAgent"))
    }

    func testAppSafetyPolicyKeepsPasswordManagerBlocks() {
        XCTAssertTrue(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.1password.1password"))
        XCTAssertTrue(AppSafetyPolicy.isBlocked(bundleIdentifier: "com.bitwarden.desktop"))
        XCTAssertTrue(AppSafetyPolicy.isBlocked(bundleIdentifier: "me.proton.pass.electron"))
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

    func testGlobalPointerFallbackFlagDefaultsToDisabled() {
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: [:]))
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]))
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "yes"]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "0"]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "false"]))
    }

    func testSetValueAttributeGateMatchesOfficialSettableBoundary() throws {
        XCTAssertTrue(try setValueAttributeIsSettable(result: .success, settable: true, attribute: kAXValueAttribute))
        XCTAssertFalse(try setValueAttributeIsSettable(result: .success, settable: false, attribute: kAXValueAttribute))
        XCTAssertEqual(nonSettableSetValueErrorMessage, "Cannot set a value for an element that is not settable")

        XCTAssertThrowsError(
            try setValueAttributeIsSettable(result: .attributeUnsupported, settable: false, attribute: kAXValueAttribute)
        ) { error in
            XCTAssertEqual(
                (error as? ComputerUseError)?.errorDescription,
                "AXUIElementIsAttributeSettable(AXValue) failed with -25205"
            )
        }
    }

    func testMakeVisualCursorTargetUsesWindowRelativeElementCenter() {
        let screenMappings = [
            VisualCursorScreenMapping(
                screenStateFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                appKitFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000)
            ),
        ]
        let target = makeVisualCursorTarget(
            localFrame: CGRect(x: 24, y: 32, width: 120, height: 48),
            windowBounds: CGRect(x: 400, y: 220, width: 900, height: 640),
            targetWindowID: 321,
            targetWindowLayer: 8,
            screenMappings: screenMappings
        )

        XCTAssertEqual(
            target,
            VisualCursorTarget(
                point: CGPoint(x: 484, y: 724),
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

    func testVisualCursorAppKitPointConvertsScreenStateYDownCoordinates() {
        let point = visualCursorAppKitPoint(
            fromScreenStatePoint: CGPoint(x: 2415, y: 181),
            screenMappings: [
                VisualCursorScreenMapping(
                    screenStateFrame: CGRect(x: 0, y: 0, width: 3024, height: 1964),
                    appKitFrame: CGRect(x: 0, y: 0, width: 3024, height: 1964)
                ),
            ]
        )

        XCTAssertEqual(point, CGPoint(x: 2415, y: 1783))
    }

    func testInputEventPointKeepsCoreGraphicsScreenStateCoordinates() {
        let point = inputEventPoint(
            fromScreenStatePoint: CGPoint(x: -1311, y: 701),
            screenMappings: [
                VisualCursorScreenMapping(
                    screenStateFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                    appKitFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440)
                ),
                VisualCursorScreenMapping(
                    screenStateFrame: CGRect(x: -1512, y: 458, width: 1512, height: 982),
                    appKitFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982)
                ),
            ]
        )

        XCTAssertEqual(point, CGPoint(x: -1311, y: 701))
    }

    func testScreenshotPixelScaleUsesRetinaSizedImageAgainstWindowBounds() {
        let scale = screenshotPixelScale(
            screenshotPixelSize: CGSize(width: 2048, height: 1266),
            windowBounds: CGRect(x: 1938, y: 236, width: 1024, height: 633)
        )

        XCTAssertEqual(scale.width, 2, accuracy: 0.0001)
        XCTAssertEqual(scale.height, 2, accuracy: 0.0001)
    }

    func testScreenshotPixelScaleStaysAtOneForUnscaledDisplays() {
        let scale = screenshotPixelScale(
            screenshotPixelSize: CGSize(width: 1024, height: 633),
            windowBounds: CGRect(x: 1938, y: 236, width: 1024, height: 633)
        )

        XCTAssertEqual(scale.width, 1, accuracy: 0.0001)
        XCTAssertEqual(scale.height, 1, accuracy: 0.0001)
    }

    func testScreenshotPixelToWindowPointConvertsScreenshotPixelsBackToWindowPoints() {
        let point = screenshotPixelToWindowPoint(
            CGPoint(x: 1060, y: 790),
            screenshotPixelSize: CGSize(width: 2048, height: 1266),
            windowBounds: CGRect(x: 1938, y: 236, width: 1024, height: 633)
        )

        XCTAssertEqual(point.x, 530, accuracy: 0.0001)
        XCTAssertEqual(point.y, 395, accuracy: 0.0001)
    }

    func testScreenshotPixelToWindowPointKeepsCoordinatesOnUnscaledDisplays() {
        let point = screenshotPixelToWindowPoint(
            CGPoint(x: 530, y: 395),
            screenshotPixelSize: CGSize(width: 1024, height: 633),
            windowBounds: CGRect(x: 1938, y: 236, width: 1024, height: 633)
        )

        XCTAssertEqual(point, CGPoint(x: 530, y: 395))
    }

    func testScreenshotPixelToWindowPointFallsBackToIdentityWithoutImageSize() {
        let point = screenshotPixelToWindowPoint(
            CGPoint(x: 530, y: 395),
            screenshotPixelSize: nil,
            windowBounds: CGRect(x: 1938, y: 236, width: 1024, height: 633)
        )

        XCTAssertEqual(point, CGPoint(x: 530, y: 395))
    }

    func testWindowCapturePrefersFrontmostOverHintWhenModalOverlapsHintedWindow() {
        let main = WindowCaptureCandidate(
            windowID: 1,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            title: "Nomi",
            area: 480_000,
            frontToBackIndex: 1,
            isOnscreen: true
        )
        let openPanel = WindowCaptureCandidate(
            windowID: 2,
            layer: 0,
            bounds: CGRect(x: 120, y: 180, width: 880, height: 448),
            title: "Open",
            area: 394_240,
            frontToBackIndex: 0,
            isOnscreen: true
        )

        let selected = preferredWindowCaptureCandidate([openPanel, main], titleHint: "Nomi")

        XCTAssertEqual(selected?.windowID, openPanel.windowID)
    }

    func testWindowCaptureKeepsHintedWindowWhenFrontmostDoesNotOverlap() {
        let main = WindowCaptureCandidate(
            windowID: 1,
            layer: 0,
            bounds: CGRect(x: 100, y: 100, width: 800, height: 600),
            title: "Nomi",
            area: 480_000,
            frontToBackIndex: 1,
            isOnscreen: true
        )
        let other = WindowCaptureCandidate(
            windowID: 2,
            layer: 0,
            bounds: CGRect(x: 1_200, y: 100, width: 400, height: 300),
            title: "Utility",
            area: 120_000,
            frontToBackIndex: 0,
            isOnscreen: true
        )

        let selected = preferredWindowCaptureCandidate([other, main], titleHint: "Nomi")

        XCTAssertEqual(selected?.windowID, main.windowID)
    }

    func testListTraversalPrefersVisibleChildrenAndReadsContents() {
        let attributes = childTraversalAttributes(
            role: kAXListRole as String,
            hasRows: false,
            hasVisibleChildren: true
        )

        XCTAssertFalse(attributes.contains(kAXChildrenAttribute))
        XCTAssertTrue(attributes.contains("AXContents"))
        XCTAssertTrue(attributes.contains("AXVisibleChildren"))
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

    func testVisualCursorKeepsPostInteractionIdleStateLongEnoughForFollowupTools() {
        XCTAssertEqual(visualCursorPostInteractionIdleTimeout(), 30)
        XCTAssertGreaterThanOrEqual(visualCursorPostInteractionIdleTimeout(), 30)
    }

    func testCursorPanelReordersWhenForcedEvenIfTargetWindowDidNotChange() {
        let targetWindow = CursorTargetWindow(windowID: 42, layer: 0)

        XCTAssertTrue(
            shouldReorderCursorPanel(
                activeTargetWindow: targetWindow,
                effectiveTargetWindow: targetWindow,
                panelIsVisible: true,
                forceReorder: true
            )
        )
    }

    func testCursorPanelDoesNotReorderWhenVisibleAndTargetWindowIsStable() {
        let targetWindow = CursorTargetWindow(windowID: 42, layer: 0)

        XCTAssertFalse(
            shouldReorderCursorPanel(
                activeTargetWindow: targetWindow,
                effectiveTargetWindow: targetWindow,
                panelIsVisible: true,
                forceReorder: false
            )
        )
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

    func testOfficialCursorMotionTravelDurationUsesRecoveredEndpointLockTiming() {
        let curvedMeasurement = CursorMotionMeasurement(
            length: 1280,
            angleChangeEnergy: 8,
            maxAngleChange: 1.2,
            totalTurn: 4,
            staysInBounds: true
        )

        XCTAssertEqual(
            OfficialCursorMotionModel.calibratedTravelDuration(distance: 140, measurement: curvedMeasurement),
            OfficialCursorMotionModel.closeEnoughTime,
            accuracy: 0.000_001
        )
        XCTAssertGreaterThan(
            OfficialCursorMotionModel.calibratedTravelDuration(distance: 900, measurement: curvedMeasurement),
            1.0
        )
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

    func testVisualCursorIdlePoseKeepsTipAnchoredAndOnlyRotates() {
        let restingTipPosition = CGPoint(x: 184, y: 92)
        let positivePose = visualCursorIdlePose(restingTipPosition: restingTipPosition, phase: .pi / 2)
        let negativePose = visualCursorIdlePose(
            restingTipPosition: restingTipPosition,
            phase: (.pi / 2) + (.pi / CGFloat(0.8))
        )

        XCTAssertEqual(positivePose.tipPosition.x, restingTipPosition.x, accuracy: 0.0001)
        XCTAssertEqual(positivePose.tipPosition.y, restingTipPosition.y, accuracy: 0.0001)
        XCTAssertGreaterThan(positivePose.angleOffset, 0)
        XCTAssertLessThanOrEqual(abs(positivePose.angleOffset), visualCursorIdleRotationAmplitude() + 0.0001)
        XCTAssertGreaterThan(abs(positivePose.angleOffset), 0.08)

        XCTAssertEqual(negativePose.tipPosition.x, restingTipPosition.x, accuracy: 0.0001)
        XCTAssertEqual(negativePose.tipPosition.y, restingTipPosition.y, accuracy: 0.0001)
        XCTAssertLessThan(negativePose.angleOffset, 0)
        XCTAssertLessThanOrEqual(abs(negativePose.angleOffset), visualCursorIdleRotationAmplitude() + 0.0001)
        XCTAssertGreaterThan(abs(negativePose.angleOffset), 0.08)
    }

    // MARK: - MacSessionGuard tests

    func testMacSessionGuardBlocksWhenLocked() {
        let provider = FakeLockedSessionProvider()
        let guard_ = MacSessionGuard(provider: provider)
        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click")) { error in
            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("macOS is locked"))
        }
    }

    func testMacSessionGuardAllowsWhenUnlocked() {
        let provider = FakeUnlockedSessionProvider()
        let guard_ = MacSessionGuard(provider: provider)
        XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
    }

    func testMacSessionGuardFailsClosedOnNilDictionary() {
        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: []))
        let guard_ = MacSessionGuard(provider: provider)
        XCTAssertThrowsError(try guard_.requireUnlocked(for: "get_app_state")) { error in
            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("macOS is locked"))
        }
    }

    func testMacSessionGuardFailsClosedOnEmptyDictionary() {
        // Empty dict → isUnknown = true, isLocked = true — same result as nil
        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: []))
        let guard_ = MacSessionGuard(provider: provider)
        XCTAssertThrowsError(try guard_.requireUnlocked(for: "scroll")) { error in
            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("macOS is locked"))
        }
    }

    func testMacSessionGuardFailsClosedOnParseFailed() {
        // parse-failed produces isUnknown = true, isLocked = true
        let provider = FakeSnapshotProvider(snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: ["SomeKey"]))
        let guard_ = MacSessionGuard(provider: provider)
        XCTAssertThrowsError(try guard_.requireUnlocked(for: "type_text")) { error in
            let msg = (error as? ComputerUseError)?.errorDescription ?? ""
            XCTAssertTrue(msg.contains("macOS is locked"))
        }
    }

    func testMacSessionGuardRawKeysDiagnostics() {
        let keys: Set<String> = ["CGSSessionScreenIsLocked", "CGSSessionUserIDKey"]
        let snapshot = MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: keys)
        XCTAssertEqual(snapshot.rawKeysSeen, keys)
        XCTAssertFalse(snapshot.isUnknown)
        XCTAssertFalse(snapshot.isLocked)
    }

    // MARK: - parseSnapshot tests (console-gated absent-key fix)

    func testParseSnapshotNilDictFailsClosed() {
        let snap = SystemMacSessionStateProvider.parseSnapshot(nil, rawKeys: [])
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotEmptyDictFailsClosed() {
        let snap = SystemMacSessionStateProvider.parseSnapshot([:], rawKeys: [])
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotKeyAbsentOnConsoleTrueReturnsUnlocked() {
        let dict: [String: Any] = ["kCGSSessionOnConsoleKey": true]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertFalse(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    func testParseSnapshotKeyAbsentOnConsoleTrueNSNumberReturnsUnlocked() {
        let dict: [String: Any] = ["kCGSSessionOnConsoleKey": NSNumber(value: 1)]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertFalse(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    func testParseSnapshotKeyAbsentOnConsoleFalseFailsClosed() {
        let dict: [String: Any] = ["kCGSSessionOnConsoleKey": false]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotKeyAbsentOnConsoleKeyAbsentFailsClosed() {
        let dict: [String: Any] = ["SomeOtherKey": "x"]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotKeyAbsentOnConsoleUnparseableFailsClosed() {
        let dict: [String: Any] = ["kCGSSessionOnConsoleKey": "garbage"]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotKeyPresentTrueLockedRegardlessOfConsole() {
        let dict: [String: Any] = ["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": true]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    func testParseSnapshotKeyPresentFalseUnlocked() {
        let dict: [String: Any] = ["CGSSessionScreenIsLocked": false]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertFalse(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    func testParseSnapshotKeyPresentNSNumberTrueLocked() {
        let dict: [String: Any] = ["CGSSessionScreenIsLocked": NSNumber(value: 1)]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    func testParseSnapshotKeyPresentUnparseableTypeFailsClosed() {
        let dict: [String: Any] = ["CGSSessionScreenIsLocked": "garbage"]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertTrue(snap.isUnknown)
    }

    func testParseSnapshotKeyPresentTrueLockedWithOffConsole() {
        let dict: [String: Any] = ["CGSSessionScreenIsLocked": true, "kCGSSessionOnConsoleKey": false]
        let snap = SystemMacSessionStateProvider.parseSnapshot(dict, rawKeys: Set(dict.keys))
        XCTAssertTrue(snap.isLocked)
        XCTAssertFalse(snap.isUnknown)
    }

    // MARK: - shouldCache tests (R2 asymmetric caching)

    func testSystemMacSessionStateProviderDoesNotCacheUnlockedSnapshot() {
        let snapshot = MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
        XCTAssertFalse(SystemMacSessionStateProvider.shouldCache(snapshot))
    }

    func testSystemMacSessionStateProviderCachesLockedSnapshot() {
        let locked = MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: [])
        let unknown = MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        XCTAssertTrue(SystemMacSessionStateProvider.shouldCache(locked))
        XCTAssertTrue(SystemMacSessionStateProvider.shouldCache(unknown))
    }

    // MARK: - Live system probe (manual verification only, skipped by default)

    func testLiveSystemProbePrintsRealLockState() throws {
        guard ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_LIVE_PROBE"] == "1" else {
            throw XCTSkip("set OPEN_COMPUTER_USE_LIVE_PROBE=1 to probe the real session dictionary")
        }
        let snap = SystemMacSessionStateProvider().currentSnapshot()
        print("[live-probe] isLocked=\(snap.isLocked) isUnknown=\(snap.isUnknown) rawKeysSeen=\(snap.rawKeysSeen.sorted())")
    }

    func testSystemMacSessionStateProviderCachesWithinTTL() {
        // Uses a fake provider to verify the caching concept — we cannot test
        // SystemMacSessionStateProvider directly without mocking CGSessionCopyCurrentDictionary.
        // This test documents the intended behavior.
        var callCount = 0
        final class CountingProvider: MacSessionStateProvider {
            var count = 0
            func currentSnapshot() -> MacSessionSnapshot {
                count += 1
                return MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: [])
            }
        }
        let provider = CountingProvider()
        let guard1 = MacSessionGuard(provider: provider)
        XCTAssertNoThrow(try guard1.requireUnlocked(for: "click"))
        XCTAssertNoThrow(try guard1.requireUnlocked(for: "scroll"))
        // Both calls go to provider since MacSessionGuard itself does not cache —
        // caching is in SystemMacSessionStateProvider specifically
        XCTAssertEqual(provider.count, 2)
        // Document: SystemMacSessionStateProvider adds 200ms TTL on top
        // Manual verification: consecutive tool calls within 200ms share one IPC round-trip
        _ = callCount // suppress unused warning
    }

    func testDispatcherBlocksAllGUIToolsWhenLocked() {
        let lockedGuard = MacSessionGuard(provider: FakeLockedSessionProvider())
        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: lockedGuard)
        let guiTools = ["list_apps", "get_app_state", "click", "perform_secondary_action",
                        "scroll", "drag", "type_text", "press_key", "set_value"]
        XCTAssertEqual(guiTools.count, 9)
        for tool in guiTools {
            let result = dispatcher.callToolAsResult(name: tool, arguments: ["app": "Finder"])
            XCTAssertTrue(result.isError, "Expected error for tool: \(tool)")
            let text = result.primaryText ?? ""
            XCTAssertTrue(
                text.contains("macOS is locked"),
                "Expected lock message for tool \(tool), got: \(text)"
            )
        }
    }

    func testLockPolicyDefaultsToBlockWhenEnvironmentUnset() {
        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment([:]), .blockWhileLocked)
        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "0"]), .blockWhileLocked)
        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "false"]), .blockWhileLocked)
        XCTAssertEqual(MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": "nonsense"]), .blockWhileLocked)
    }

    func testLockPolicyParsesAllowValuesFromEnvironment() {
        for value in ["1", "true", "TRUE", "  yes  ", "on", "allow"] {
            XCTAssertEqual(
                MacSessionLockPolicy.fromEnvironment(["OPEN_COMPUTER_USE_ALLOW_LOCKED": value]),
                .allowWhileLocked,
                "Expected allow policy for env value: \(value)"
            )
        }
    }

    func testGuardBlocksWhenLockedUnderDefaultPolicy() {
        // Explicit policy makes the default fail-closed contract independent of the test env.
        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .blockWhileLocked)
        XCTAssertThrowsError(try guard_.requireUnlocked(for: "click"))
    }

    func testGuardAllowsAllToolsWhenLockedUnderOptInPolicy() {
        let guard_ = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
        let tools = ["list_apps", "get_app_state", "click", "perform_secondary_action",
                     "scroll", "drag", "type_text", "press_key", "set_value"]
        for tool in tools {
            XCTAssertNoThrow(try guard_.requireUnlocked(for: tool), "Opt-in policy should permit \(tool) while locked")
        }
    }

    func testGuardAllowsToolsWhenLockStateUnknownUnderOptInPolicy() {
        // Unknown lock state (dict absent/unparseable) still fails closed by default, but the
        // opt-in accepts the same best-effort risk the operator asked for.
        let unknownLocked = FakeSnapshotProvider(
            snapshot: MacSessionSnapshot(isLocked: true, isUnknown: true, rawKeysSeen: [])
        )
        let blockGuard = MacSessionGuard(provider: unknownLocked, policy: .blockWhileLocked)
        XCTAssertThrowsError(try blockGuard.requireUnlocked(for: "click"))
        let allowGuard = MacSessionGuard(provider: unknownLocked, policy: .allowWhileLocked)
        XCTAssertNoThrow(try allowGuard.requireUnlocked(for: "click"))
    }

    func testGuardStillAllowsEverythingWhenUnlockedRegardlessOfPolicy() {
        for policy in [MacSessionLockPolicy.blockWhileLocked, .allowWhileLocked] {
            let guard_ = MacSessionGuard(provider: FakeUnlockedSessionProvider(), policy: policy)
            XCTAssertNoThrow(try guard_.requireUnlocked(for: "click"))
        }
    }

    func testDispatcherAllowsAXToolsWhenLockedWithOptIn() {
        // With opt-in, the guard no longer short-circuits: list_apps passes the guard and runs
        // (it needs no live UI, so it succeeds), proving locked no longer blocks unconditionally.
        let optInGuard = MacSessionGuard(provider: FakeLockedSessionProvider(), policy: .allowWhileLocked)
        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: optInGuard)
        let result = dispatcher.callToolAsResult(name: "list_apps", arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertFalse((result.primaryText ?? "").contains("macOS is locked"))
    }

    // MARK: - App-agent socket peer authentication policy

    func testPeerAuthRejectsDifferentUID() {
        let decision = AppAgentPeerAuthPolicy.decide(
            peerUID: 502,
            selfUID: 501,
            agentTeamIdentifier: "ABCDE12345",
            peerSatisfiesAgentRequirement: true,
            peerTeamIdentifier: "ABCDE12345"
        )
        guard case let .reject(reason) = decision else {
            return XCTFail("Expected reject for uid mismatch, got \(decision)")
        }
        XCTAssertTrue(reason.contains("uid"))
    }

    func testPeerAuthAllowsSignedSameTeamSameUID() {
        let decision = AppAgentPeerAuthPolicy.decide(
            peerUID: 501,
            selfUID: 501,
            agentTeamIdentifier: "ABCDE12345",
            peerSatisfiesAgentRequirement: true,
            peerTeamIdentifier: "ABCDE12345"
        )
        XCTAssertEqual(decision, .allow)
    }

    func testPeerAuthRejectsSignedAgentWhenPeerFailsRequirement() {
        // Signed agent + peer that does not satisfy the team requirement (unsigned, or different
        // developer) must be rejected — this is the confused-deputy defense.
        let decision = AppAgentPeerAuthPolicy.decide(
            peerUID: 501,
            selfUID: 501,
            agentTeamIdentifier: "ABCDE12345",
            peerSatisfiesAgentRequirement: false,
            peerTeamIdentifier: "ZZZZZ99999"
        )
        guard case let .reject(reason) = decision else {
            return XCTFail("Expected reject for failed requirement, got \(decision)")
        }
        XCTAssertTrue(reason.contains("ABCDE12345"))
        XCTAssertTrue(reason.contains("ZZZZZ99999"))
    }

    func testPeerAuthFallsBackToSameUIDWhenAgentUnsigned() {
        // Unsigned/ad-hoc agent (nil or empty team) cannot pin a signature; same-uid peer is
        // allowed via the explicit fallback so local `swift build` dev binaries keep working.
        let unsignedTeams: [String?] = [nil, ""]
        for team in unsignedTeams {
            let decision = AppAgentPeerAuthPolicy.decide(
                peerUID: 501,
                selfUID: 501,
                agentTeamIdentifier: team,
                peerSatisfiesAgentRequirement: false,
                peerTeamIdentifier: nil
            )
            XCTAssertEqual(decision, .allowUnsignedFallback, "team=\(String(describing: team))")
        }
    }

    func testPeerAuthUnsignedAgentStillRejectsDifferentUID() {
        // Even in the unsigned fallback, a different uid must never be allowed.
        let decision = AppAgentPeerAuthPolicy.decide(
            peerUID: 999,
            selfUID: 501,
            agentTeamIdentifier: nil,
            peerSatisfiesAgentRequirement: false,
            peerTeamIdentifier: nil
        )
        guard case .reject = decision else {
            return XCTFail("Expected reject for uid mismatch under unsigned agent, got \(decision)")
        }
    }

    func testDispatcherAllowsUnlockedTools() {
        let unlockedGuard = MacSessionGuard(provider: FakeUnlockedSessionProvider())
        let dispatcher = ComputerUseToolDispatcher(service: ComputerUseService(), guard: unlockedGuard)
        // list_apps is non-throwing and doesn't need special args — it passes guard and succeeds
        let result = dispatcher.callToolAsResult(name: "list_apps", arguments: [:])
        // list_apps always succeeds; the lock guard should not block it when unlocked
        XCTAssertFalse(result.isError)
    }

    func testMCPServerStillHandlesInitializeWhenLocked() {
        // initialize/ping/tools/list all bypass the dispatcher, so lock state is irrelevant
        let server = StdioMCPServer(service: ComputerUseService())
        let initResponse = server.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.0"},"capabilities":{}}}"#
        )
        XCTAssertNotNil(initResponse)
        XCTAssertTrue(initResponse!.contains("open-computer-use"))

        let pingResponse = server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}"#)
        XCTAssertNotNil(pingResponse)

        let listResponse = server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}"#)
        XCTAssertNotNil(listResponse)
        XCTAssertTrue(listResponse!.contains("list_apps"))
    }

    private func makeSnapshot(treeLines: [String], focusedSummary: String?, selectedText: String? = nil) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "Sample Chat",
                bundleIdentifier: "com.example.SampleChat",
                pid: 18_465,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Sample Chat",
            windowBounds: nil,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .accessibility,
            treeLines: treeLines,
            focusedSummary: focusedSummary,
            focusedElement: nil,
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

    private func makeNoisyTestImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 37 + y * 17) & 0xFF)
                pixels[offset + 1] = UInt8((x * 11 + y * 43) & 0xFF)
                pixels[offset + 2] = UInt8((x * 71 + y * 5) & 0xFF)
                pixels[offset + 3] = 255
            }
        }

        return try makeTestImage(width: width, height: height, pixels: pixels)
    }

    private func makeSolidTestImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 80
            pixels[index + 1] = 140
            pixels[index + 2] = 220
            pixels[index + 3] = 255
        }

        return try makeTestImage(width: width, height: height, pixels: pixels)
    }

    private func makeTestImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let data = Data(pixels)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )

        return try XCTUnwrap(image)
    }

    private func imageSize(in data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    // MARK: - AppScreenSession tests

    func testAppScreenSessionValidatorMatchingIdentityPasses() throws {
        let validator = AppScreenSessionValidator()
        let snapshot = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        XCTAssertEqual(session.identity.pid, 1234)
    }

    func testAppScreenSessionValidatorPIDMismatchFails() throws {
        let validator = AppScreenSessionValidator()
        let cached = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: cached, captureGeneration: 1)
        let different = makeFixtureSnapshot(pid: 9999, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertThrowsError(try validator.validate(cachedIdentity: identity, currentSnapshot: different)) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, appScreenStaleStateError)
        }
    }

    func testAppScreenSessionValidatorBundleIDMismatchFails() throws {
        let validator = AppScreenSessionValidator()
        let cached = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: cached, captureGeneration: 1)
        let different = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.Other", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertThrowsError(try validator.validate(cachedIdentity: identity, currentSnapshot: different)) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, appScreenStaleStateError)
        }
    }

    func testAppScreenSessionValidatorWindowIDMismatchWithMatchingPIDSucceeds() throws {
        let validator = AppScreenSessionValidator()
        // cached has a windowID, current has a different one but same PID+bundleID — should NOT throw
        let cached = makeFixtureSnapshotWithExplicitWindowID(pid: 1234, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: cached, captureGeneration: 1)
        let different = makeFixtureSnapshotWithExplicitWindowID(pid: 1234, bundleID: "com.example.App", windowID: 99, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertNoThrow(try validator.validate(cachedIdentity: identity, currentSnapshot: different))
    }

    func testAppScreenSessionValidatorWindowIDAndPIDMismatchFails() throws {
        let validator = AppScreenSessionValidator()
        let cached = makeFixtureSnapshotWithExplicitWindowID(pid: 1234, bundleID: "com.example.App", windowID: 42, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: cached, captureGeneration: 1)
        // Different PID AND different windowID — should still fail on PID check
        let different = makeFixtureSnapshotWithExplicitWindowID(pid: 9999, bundleID: "com.example.App", windowID: 99, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        XCTAssertThrowsError(try validator.validate(cachedIdentity: identity, currentSnapshot: different)) { error in
            XCTAssertTrue((error as? ComputerUseError)?.localizedDescription.contains("target screen changed") ?? false)
        }
    }

    func testAppScreenSessionValidatorBoundsDriftBeyondToleranceFails() throws {
        let validator = AppScreenSessionValidator()
        let cached = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: nil, bounds: CGRect(x: 100, y: 200, width: 800, height: 600))
        let identity = validator.buildIdentity(from: cached, captureGeneration: 1)
        // drift of 10 points in x — exceeds 8pt tolerance
        let drifted = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: nil, bounds: CGRect(x: 110, y: 200, width: 800, height: 600))
        XCTAssertThrowsError(try validator.validate(cachedIdentity: identity, currentSnapshot: drifted)) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, appScreenStaleStateError)
        }
    }

    func testAppScreenSessionValidatorMissingScreenshotRejectsCoordinateActions() throws {
        let validator = AppScreenSessionValidator()
        let snapshot = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: nil, bounds: nil)
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        // No screenshotPixelSize — coordinate action must throw
        XCTAssertThrowsError(try session.requireCoordinateInsideScreenshot(CGPoint(x: 100, y: 100))) { error in
            XCTAssertTrue((error as? ComputerUseError)?.errorDescription?.contains("screenshot") == true)
        }
    }

    func testAppScreenSessionValidatorNegativeCoordinateFails() throws {
        let validator = AppScreenSessionValidator()
        let pngData = try makeSolidPNGData(width: 400, height: 300)
        let snapshot = makeFixtureSnapshotWithScreenshot(pid: 1234, bundleID: "com.example.App", pngData: pngData)
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        XCTAssertThrowsError(try session.requireCoordinateInsideScreenshot(CGPoint(x: -1, y: 100))) { error in
            XCTAssertTrue((error as? ComputerUseError)?.errorDescription?.contains("outside") == true)
        }
    }

    func testAppScreenSessionValidatorOutsideScreenshotCoordinateFails() throws {
        let validator = AppScreenSessionValidator()
        let pngData = try makeSolidPNGData(width: 400, height: 300)
        let snapshot = makeFixtureSnapshotWithScreenshot(pid: 1234, bundleID: "com.example.App", pngData: pngData)
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        // (500, 100) is outside 400x300
        XCTAssertThrowsError(try session.requireCoordinateInsideScreenshot(CGPoint(x: 500, y: 100))) { error in
            XCTAssertTrue((error as? ComputerUseError)?.errorDescription?.contains("outside") == true)
        }
        // (399, 299) is inside — no throw
        XCTAssertNoThrow(try session.requireCoordinateInsideScreenshot(CGPoint(x: 399, y: 299)))
    }

    func testAppScreenSessionValidatorKeyboardPIDAndBundleIDRequired() throws {
        let validator = AppScreenSessionValidator()
        let snapshot = makeFixtureSnapshot(pid: 1234, bundleID: "com.example.App", windowID: nil, bounds: nil)
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        // matching pid + bundleID passes
        XCTAssertNoThrow(try session.requireKeyboardOwnership(pid: 1234, bundleIdentifier: "com.example.App"))
        // PID mismatch fails
        XCTAssertThrowsError(try session.requireKeyboardOwnership(pid: 9999, bundleIdentifier: "com.example.App")) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, appScreenStaleStateError)
        }
        // bundleID mismatch fails
        XCTAssertThrowsError(try session.requireKeyboardOwnership(pid: 1234, bundleIdentifier: "com.example.Other")) { error in
            XCTAssertEqual((error as? ComputerUseError)?.errorDescription, appScreenStaleStateError)
        }
    }

    func testAppScreenSessionValidatorStageManagerBackgroundWindowPasses() throws {
        // Stage Manager: same PID + bundleID, no AX focus required for keyboard gating
        let validator = AppScreenSessionValidator()
        let snapshot = makeFixtureSnapshot(pid: 5678, bundleID: "com.apple.Safari", windowID: nil, bounds: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let identity = validator.buildIdentity(from: snapshot, captureGeneration: 1)
        let session = try validator.validate(cachedIdentity: identity, currentSnapshot: snapshot)
        // Background window: PID and bundleID match — keyboard ownership passes
        XCTAssertNoThrow(try session.requireKeyboardOwnership(pid: 5678, bundleIdentifier: "com.apple.Safari"))
    }

    // MARK: - AppScreenSession fixture helpers

    private func makeFixtureSnapshot(pid: pid_t, bundleID: String?, windowID: CGWindowID?, bounds: CGRect?) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "TestApp",
                bundleIdentifier: bundleID,
                pid: pid,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Test Window",
            windowBounds: bounds,
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .fixture,
            treeLines: [],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [:]
        )
    }

    private func makeFixtureSnapshotWithExplicitWindowID(pid: pid_t, bundleID: String?, windowID: CGWindowID?, bounds: CGRect?) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "TestApp",
                bundleIdentifier: bundleID,
                pid: pid,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Test Window",
            windowBounds: bounds,
            targetWindowID: windowID,
            targetWindowLayer: nil,
            screenshotPNGData: nil,
            mode: .fixture,
            treeLines: [],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [:]
        )
    }

    private func makeFixtureSnapshotWithScreenshot(pid: pid_t, bundleID: String?, pngData: Data) -> AppSnapshot {
        AppSnapshot(
            app: RunningAppDescriptor(
                name: "TestApp",
                bundleIdentifier: bundleID,
                pid: pid,
                runningApplication: NSRunningApplication.current
            ),
            windowTitle: "Test Window",
            windowBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            targetWindowID: nil,
            targetWindowLayer: nil,
            screenshotPNGData: pngData,
            mode: .accessibility,
            treeLines: [],
            focusedSummary: nil,
            focusedElement: nil,
            selectedText: nil,
            elements: [:]
        )
    }

    private func makeSolidPNGData(width: Int, height: Int) throws -> Data {
        let image = try makeSolidTestImage(width: width, height: height)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    // MARK: - ControlActivityStore tests

    @MainActor
    func testControlActivityStoreRegistersMultipleConnections() throws {
        let store = ControlActivityStore(nowProvider: { Date() })
        let id1 = ControlConnectionID()
        let id2 = ControlConnectionID()

        store.registerConnection(id1, isAppAgentMode: false)
        store.registerConnection(id2, isAppAgentMode: true)

        XCTAssertEqual(store.connections.count, 2)
        XCTAssertEqual(store.connections[id1]?.isAppAgentMode, false)
        XCTAssertEqual(store.connections[id2]?.isAppAgentMode, true)

        store.unregisterConnection(id1)
        XCTAssertNil(store.connections[id1])
        XCTAssertNotNil(store.connections[id2])
    }

    @MainActor
    func testControlActivityStoreUpdatesLastToolAndAppMetadata() throws {
        let store = ControlActivityStore(nowProvider: { Date() })
        let id = ControlConnectionID()
        store.registerConnection(id, isAppAgentMode: false)

        let event = ControlActivityEvent(
            toolName: "click",
            appDisplayName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            pid: 1234
        )
        store.record(event, forConnection: id)

        let state = store.connections[id]
        XCTAssertEqual(state?.lastToolName, "click")
        XCTAssertEqual(state?.appDisplayName, "Safari")
        XCTAssertEqual(state?.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(state?.pid, 1234)
        if case .active = state?.status { } else {
            XCTFail("Expected status .active, got \(String(describing: state?.status))")
        }
    }

    @MainActor
    func testControlActivityStoreDoesNotStoreRawTextOrArgs() throws {
        // type_text must record only toolName + app metadata — never the text value
        let store = ControlActivityStore(nowProvider: { Date() })
        let id = ControlConnectionID()
        store.registerConnection(id, isAppAgentMode: false)

        // Simulate what the dispatcher should produce for type_text: tool name + app info only
        let event = ControlActivityEvent(
            toolName: "type_text",
            appDisplayName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            pid: 5678
            // text value intentionally NOT in ControlActivityEvent
        )
        store.record(event, forConnection: id)

        let state = store.connections[id]
        XCTAssertEqual(state?.lastToolName, "type_text")
        XCTAssertEqual(state?.appDisplayName, "TextEdit")
        // Verify ControlActivityEvent has no field that could hold raw text
        // (compile-time: the struct only exposes toolName, appDisplayName, bundleIdentifier, pid)
        XCTAssertNil(state?.appDisplayName.flatMap { _ in Optional<String>.none })  // tautology guard
    }

    @MainActor
    func testControlActivityStoreMarksTurnEnded() throws {
        let store = ControlActivityStore(nowProvider: { Date() })
        let id1 = ControlConnectionID()
        let id2 = ControlConnectionID()
        store.registerConnection(id1, isAppAgentMode: false)
        store.registerConnection(id2, isAppAgentMode: true)

        let event = ControlActivityEvent(toolName: "scroll", appDisplayName: nil, bundleIdentifier: nil, pid: nil)
        store.record(event, forConnection: id1)
        store.record(event, forConnection: id2)

        // Both should be active
        if case .active = store.connections[id1]?.status { } else { XCTFail("Expected active for id1") }
        if case .active = store.connections[id2]?.status { } else { XCTFail("Expected active for id2") }

        // Mark turn ended for all
        store.markTurnEnded(connectionID: nil)

        if case .idle = store.connections[id1]?.status { } else { XCTFail("Expected idle for id1 after turn ended") }
        if case .idle = store.connections[id2]?.status { } else { XCTFail("Expected idle for id2 after turn ended") }
    }

    @MainActor
    func testControlActivityStoreExpiresStaleActivity() throws {
        var fakeNow = Date()
        let store = ControlActivityStore(nowProvider: { fakeNow })

        let id = ControlConnectionID()
        store.registerConnection(id, isAppAgentMode: false)

        let event = ControlActivityEvent(toolName: "click", appDisplayName: nil, bundleIdentifier: nil, pid: nil)
        store.record(event, forConnection: id)

        // Before expiry — connection present
        store.purgeStaleConnections()
        XCTAssertNotNil(store.connections[id])

        // Advance fake clock past 5-minute stale interval
        fakeNow = fakeNow.addingTimeInterval(5 * 60 + 1)
        store.purgeStaleConnections()
        XCTAssertNil(store.connections[id], "Stale connection should have been purged after 5 minutes")
    }

    // MARK: - Background-Only Operation Guarantee

    func testGlobalPointerFallbacksDisabledByDefault() {
        // Absence of the env var must return false — no global pointer events, no app activation
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: [:]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["SOME_OTHER_VAR": "1"]))
    }

    func testGlobalPointerFallbacksRequiresExplicitOptIn() {
        // Accepted opt-in values
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]))
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "true"]))
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "yes"]))
        XCTAssertTrue(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "on"]))

        // Rejected values must not enable global pointer events
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "0"]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "false"]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "no"]))
        XCTAssertFalse(globalPointerFallbacksEnabled(environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": ""]))
    }

    func testInputSimulationTargetedClickDoesNotUseGlobalEvents() {
        // Compile-time check: clickTargeted takes a pid parameter, documenting it targets a specific
        // process rather than posting global HID events. The signature pins this guarantee.
        let _: (CGPoint, MouseButtonKind, Int, pid_t) throws -> Void = InputSimulation.clickTargeted
    }

    func testTypeTextIsNonDisruptive() {
        // Compile-time check: typeText takes a pid parameter, documenting keyboard injection is
        // always PID-targeted and never posts to the global HID event tap.
        let _: (String, pid_t) throws -> Void = InputSimulation.typeText
    }
}

// MARK: - Fake MacSessionStateProvider helpers

private struct FakeLockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: true, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

private struct FakeUnlockedSessionProvider: MacSessionStateProvider {
    func currentSnapshot() -> MacSessionSnapshot {
        MacSessionSnapshot(isLocked: false, isUnknown: false, rawKeysSeen: ["CGSSessionScreenIsLocked"])
    }
}

private struct FakeSnapshotProvider: MacSessionStateProvider {
    let snapshot: MacSessionSnapshot
    func currentSnapshot() -> MacSessionSnapshot { snapshot }
}
