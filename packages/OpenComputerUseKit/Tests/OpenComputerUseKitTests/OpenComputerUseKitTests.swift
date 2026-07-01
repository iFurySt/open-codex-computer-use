import AppKit
import ImageIO
import XCTest
@testable import OpenComputerUseKit

private final class EventStreamStatusBox: @unchecked Sendable {
    var value: EventStreamRecordingStatus?
}

private final class JSONDictionaryBox: @unchecked Sendable {
    var value: [String: Any]?
}

private final class EventStreamInputHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []

    func append(_ value: (NSEvent.EventTypeMask, (NSEvent) -> Void)) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [(NSEvent.EventTypeMask, (NSEvent) -> Void)] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        return snapshot
    }
}

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
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "--help"]), .help(command: "event-stream"))
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

    func testCLIRecognizesEventStreamCommands() throws {
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "mcp"]), .eventStream(.mcp))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "start"]), .eventStream(.start(json: false)))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "start", "--json"]), .eventStream(.start(json: true)))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "status", "--json"]), .eventStream(.status(json: true)))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "stop", "--json"]), .eventStream(.stop(json: true)))
        XCTAssertEqual(try parseOpenComputerUseCLI(arguments: ["event-stream", "cancel", "--json"]), .eventStream(.cancel(json: true)))
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "wait", "--json", "--session-id", "session-123", "--timeout", "0.5"]),
            .eventStream(.wait(json: true, sessionID: "session-123", timeout: 0.5, notifyCommand: nil))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "wait", "--notify-command", #"["/bin/echo","done"]"#]),
            .eventStream(.wait(json: false, sessionID: nil, timeout: nil, notifyCommand: ["/bin/echo", "done"]))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "summarize", "--json", "--metadata-path", "/tmp/session/metadata.json"]),
            .eventStream(.summarize(inputPath: "/tmp/session/metadata.json", includeText: false, requireAction: false))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "summarize", "--include-text", "--require-action", "/tmp/session"]),
            .eventStream(.summarize(inputPath: "/tmp/session", includeText: true, requireAction: true))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "validate", "--json", "--strict-ocu", "--require-event-type", "mouse.click", "--require-skill-draft", "--metadata-path", "/tmp/session/metadata.json"]),
            .eventStream(.validate(
                inputPath: "/tmp/session/metadata.json",
                strictOCU: true,
                requiredEventTypes: ["mouse.click"],
                requireSkillDraft: true
            ))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["event-stream", "validate", "--json", "--require-skill-draft", "--events-path", "/tmp/session/events.jsonl"]),
            .eventStream(.validate(
                inputPath: "/tmp/session/events.jsonl",
                strictOCU: false,
                requiredEventTypes: [],
                requireSkillDraft: true
            ))
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: [
                "event-stream",
                "scaffold-skill",
                "--json",
                "--skill-name",
                "recorded-example-workflow",
                "--description",
                "Replay an example workflow.",
                "--output-dir",
                "/tmp/generated-skill",
                "--overwrite",
                "--metadata-path",
                "/tmp/session/metadata.json",
            ]),
            .eventStream(.scaffoldSkill(
                inputPath: "/tmp/session/metadata.json",
                skillName: "recorded-example-workflow",
                description: "Replay an example workflow.",
                outputDirectory: "/tmp/generated-skill",
                overwrite: true,
                includeText: false
            ))
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

    func testCLIRecognizesSnapshotFullTextFlag() throws {
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "TextEdit"]),
            .snapshot(app: "TextEdit", showFullText: false)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "--show-full-text", "TextEdit"]),
            .snapshot(app: "TextEdit", showFullText: true)
        )
        XCTAssertEqual(
            try parseOpenComputerUseCLI(arguments: ["snapshot", "TextEdit", "--show-full-text"]),
            .snapshot(app: "TextEdit", showFullText: true)
        )
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

    func testEventStreamToolDefinitionsMatchOfficialSurface() {
        XCTAssertEqual(EventStreamToolDefinitions.all.map(\.name), [
            "event_stream_start",
            "event_stream_status",
            "event_stream_stop",
        ])

        let status = EventStreamToolDefinitions.all[1].asDictionary
        let annotations = status["annotations"] as? [String: Any]
        XCTAssertEqual(annotations?["readOnlyHint"] as? Bool, true)
        XCTAssertEqual(annotations?["idempotentHint"] as? Bool, true)
    }

    func testEventStreamServiceWritesSessionFilesAndStops() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)

        let started = try service.start()
        XCTAssertTrue(started.isActive)
        XCTAssertEqual(started.state, .recording)
        XCTAssertNotNil(started.eventsPath)
        XCTAssertNotNil(started.metadataPath)
        XCTAssertNotNil(started.suppressedEventsPath)
        XCTAssertEqual(started.eventCount, 3)

        let repeatedStart = try service.start()
        XCTAssertEqual(repeatedStart.sessionID, started.sessionID)

        try service.appendSyntheticEventForTesting([
            "type": "mouse.click",
            "timestamp": "2026-06-26T00:00:00.000Z",
            "button": "left",
        ])

        let stopped = try service.stop()
        XCTAssertFalse(stopped.isActive)
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(stopped.endReason, "recording_controls_stopped")
        XCTAssertEqual(stopped.eventCount, 5)

        let eventsPath = try XCTUnwrap(stopped.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"session.started""#))
        XCTAssertTrue(events.contains(#""type":"window.changed""#))
        XCTAssertTrue(events.contains(#""type":"AX.focusedWindowChanged""#))
        XCTAssertTrue(events.contains(#""type":"mouse.click""#))
        XCTAssertTrue(events.contains(#""type":"session.ended""#))

        let metadataPath = try XCTUnwrap(stopped.metadataPath)
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        XCTAssertTrue(metadata.contains(#""state" : "stopped""#))
        let sessionAliasPath = URL(fileURLWithPath: metadataPath)
            .deletingLastPathComponent()
            .appendingPathComponent("session.json")
            .path
        let sessionAlias = try String(contentsOfFile: sessionAliasPath, encoding: .utf8)
        XCTAssertNotEqual(sessionAlias, metadata)
        let sessionAliasJSON = try jsonObject(contentsOf: URL(fileURLWithPath: sessionAliasPath))
        XCTAssertEqual(sessionAliasJSON["id"] as? String, stopped.sessionID)
        XCTAssertEqual(sessionAliasJSON["eventsPath"] as? String, stopped.eventsPath)
        XCTAssertEqual(sessionAliasJSON["endReason"] as? String, "recording_controls_stopped")
        XCTAssertNil(sessionAliasJSON["state"])
        XCTAssertNil(sessionAliasJSON["eventCount"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
    }

    func testEventStreamServiceWritesAXFullDiffAndCumulativePayloads() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            screenshotPolicy: .never
        )

        _ = try service.start()
        try service.appendFocusedWindowChangedForTesting(
            reason: "test-initial-ax-payload",
            appName: "Replay Fixture",
            bundleIdentifier: "dev.opencomputeruse.replay-fixture",
            snapshot: makeSnapshot(
                treeLines: [
                    "\t0 standard window \"Replay Fixture\"",
                    "\t1 static text \"Draft\"",
                ],
                focusedSummary: "1 static text Draft"
            )
        )
        try service.appendFocusedWindowChangedForTesting(
            reason: "test-updated-ax-payload",
            appName: "Replay Fixture",
            bundleIdentifier: "dev.opencomputeruse.replay-fixture",
            snapshot: makeSnapshot(
                treeLines: [
                    "\t0 standard window \"Replay Fixture\"",
                    "\t1 static text \"Published\"",
                    "\t2 button \"Done\"",
                ],
                focusedSummary: "2 button Done"
            )
        )

        let stopped = try service.stop()
        let eventsPath = try XCTUnwrap(stopped.eventsPath)
        let events = try jsonObjects(contentsOf: URL(fileURLWithPath: eventsPath))
        let initialEvent = try XCTUnwrap(events.first {
            $0["type"] as? String == "AX.focusedWindowChanged"
                && $0["reason"] as? String == "test-initial-ax-payload"
        })
        let updatedEvent = try XCTUnwrap(events.first {
            $0["type"] as? String == "AX.focusedWindowChanged"
                && $0["reason"] as? String == "test-updated-ax-payload"
        })

        let initialPayload = try XCTUnwrap(initialEvent["accessibilityInspectorPayload"] as? [String: Any])
        XCTAssertEqual(initialPayload["kind"] as? String, "full")
        XCTAssertEqual(initialPayload["diffFromPrevious"] as? Bool, false)
        XCTAssertEqual(initialPayload["cumulativeDiffFromInitial"] as? Bool, false)
        XCTAssertEqual(initialPayload["fullTree"] as? [String], [
            "\t0 standard window \"Replay Fixture\"",
            "\t1 static text \"Draft\"",
        ])

        let updatedPayload = try XCTUnwrap(updatedEvent["accessibilityInspectorPayload"] as? [String: Any])
        XCTAssertEqual(updatedPayload["kind"] as? String, "diff")
        XCTAssertEqual(updatedPayload["diffFromPrevious"] as? Bool, true)
        XCTAssertEqual(updatedPayload["cumulativeDiffFromInitial"] as? Bool, true)
        XCTAssertNil(updatedPayload["fullTree"])
        let treeLines = try XCTUnwrap(updatedPayload["treeLines"] as? [String])
        XCTAssertTrue(treeLines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("~") })
        XCTAssertTrue(treeLines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("+") })
        let cumulativeTreeLines = try XCTUnwrap(updatedPayload["cumulativeTreeLines"] as? [String])
        XCTAssertEqual(cumulativeTreeLines, treeLines)
        XCTAssertEqual(updatedEvent["diffFromPrevious"] as? Bool, true)
    }

    func testEventStreamServicePersistsAXScreenshotContext() throws {
        let root = try makeTemporaryDirectory()
        let image = try makeSolidTestImage(width: 24, height: 16)
        let screenshotData = try XCTUnwrap(boundedScreenshotPNGData(
            for: image,
            maxBytes: 1_000_000,
            maxDimension: 320
        ))
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            screenshotPolicy: .always
        )

        _ = try service.start()
        try service.appendFocusedWindowChangedForTesting(
            reason: "test-screenshot-context",
            appName: "Replay Fixture",
            bundleIdentifier: "dev.opencomputeruse.replay-fixture",
            snapshot: makeSnapshot(
                treeLines: [
                    "\t0 standard window \"Replay Fixture\"",
                    "\t1 button \"Done\"",
                ],
                focusedSummary: "1 button Done",
                screenshotPNGData: screenshotData
            )
        )

        let stopped = try service.stop()
        let eventsPath = try XCTUnwrap(stopped.eventsPath)
        let metadataPath = try XCTUnwrap(stopped.metadataPath)
        let sessionDirectory = URL(fileURLWithPath: metadataPath).deletingLastPathComponent()
        let events = try jsonObjects(contentsOf: URL(fileURLWithPath: eventsPath))
        let screenshotEvent = try XCTUnwrap(events.first {
            $0["type"] as? String == "AX.focusedWindowChanged"
                && $0["reason"] as? String == "test-screenshot-context"
        })
        let payload = try XCTUnwrap(screenshotEvent["accessibilityInspectorPayload"] as? [String: Any])

        XCTAssertEqual(payload["screenshotNeededForContext"] as? Bool, true)
        XCTAssertEqual(payload["screenshotAvailable"] as? Bool, true)
        let screenshotPath = try XCTUnwrap(payload["screenshotPath"] as? String)
        let screenshotURL = URL(fileURLWithPath: screenshotPath)
        XCTAssertEqual(screenshotURL.deletingLastPathComponent(), sessionDirectory.appendingPathComponent("screenshots", isDirectory: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath))
        let persistedSize = try imageSize(in: Data(contentsOf: screenshotURL))
        XCTAssertEqual(persistedSize.width, 24)
        XCTAssertEqual(persistedSize.height, 16)
    }

    func testEventStreamServiceRecordsInputMonitorMouseAndKeyboardEvents() throws {
        let root = try makeTemporaryDirectory()
        let installedHandlers = EventStreamInputHandlerBox()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: true,
            showsRecordingControls: false,
            screenshotPolicy: .never,
            installsCGEventTap: false,
            inputMonitorInstaller: { mask, handler in
                installedHandlers.append((mask, handler))
                return nil
            }
        )

        _ = try service.start(approvalDecision: .approved)
        let handlers = installedHandlers.snapshot()
        XCTAssertTrue(handlers.contains { $0.0.contains(.leftMouseDown) })
        XCTAssertTrue(handlers.contains { $0.0.contains(.leftMouseUp) })
        XCTAssertTrue(handlers.contains { $0.0.contains(.keyDown) })

        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 120, y: 180),
            modifierFlags: [],
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: 120, y: 180),
            modifierFlags: [],
            timestamp: 1.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ))
        let keyDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 1.2,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        for (mask, handler) in handlers where mask.contains(.leftMouseDown) {
            handler(mouseDown)
        }
        for (mask, handler) in handlers where mask.contains(.leftMouseUp) {
            handler(mouseUp)
        }
        for (mask, handler) in handlers where mask.contains(.keyDown) {
            handler(keyDown)
        }

        let stopped = try service.stop()
        let eventsPath = try XCTUnwrap(stopped.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"mouse.click""#))
        XCTAssertTrue(events.contains(#""button":"left""#))
        XCTAssertTrue(events.contains(#""clickCount":1"#))
        XCTAssertTrue(events.contains(#""type":"keyboard.text_input""#))
        XCTAssertTrue(events.contains(#""keyCode":0"#))
    }

    func testEventStreamServiceCancelUsesOfficialControlsEndReason() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)

        _ = try service.start()
        let cancelled = try service.cancel()

        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.endReason, "recording_controls_cancelled")

        let eventsPath = try XCTUnwrap(cancelled.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""endReason":"recording_controls_cancelled""#))
    }

    func testEventStreamStatusPersistsStaleActiveSessionAsUnavailable() throws {
        let root = try makeTemporaryDirectory()
        let sessionDirectory = root.appendingPathComponent("session-stale", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        let metadataURL = sessionDirectory.appendingPathComponent("metadata.json")
        let activeStatus = EventStreamRecordingStatus(
            sessionID: "session-stale",
            state: .recording,
            startedAt: "2026-06-26T00:00:00.000Z",
            endedAt: nil,
            endReason: nil,
            eventsPath: sessionDirectory.appendingPathComponent("events.jsonl").path,
            metadataPath: metadataURL.path,
            suppressedEventsPath: sessionDirectory.appendingPathComponent("suppressed.jsonl").path,
            currentSegmentEventsPath: sessionDirectory.appendingPathComponent("events.jsonl").path,
            currentSegmentMetadataPath: metadataURL.path,
            eventCount: 3,
            suppressedEventCount: 0
        )
        let activeData = try JSONSerialization.data(
            withJSONObject: activeStatus.asDictionary,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try activeData.write(to: root.appendingPathComponent("latest-session.json"), options: [.atomic])
        try activeData.write(to: root.appendingPathComponent("active-session.json"), options: [.atomic])

        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let status = service.status()

        XCTAssertEqual(status.sessionID, "session-stale")
        XCTAssertEqual(status.state, .stopped)
        XCTAssertEqual(status.endReason, "recording_process_unavailable")
        XCTAssertNil(status.currentSegmentEventsPath)
        XCTAssertNil(status.currentSegmentMetadataPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let persistedLatest = try String(
            contentsOf: root.appendingPathComponent("latest-session.json"),
            encoding: .utf8
        )
        XCTAssertTrue(persistedLatest.contains(#""state" : "stopped""#))
        XCTAssertTrue(persistedLatest.contains(#""endReason" : "recording_process_unavailable""#))

        let persistedMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertEqual(persistedLatest, persistedMetadata)
        let persistedAlias = try String(
            contentsOf: sessionDirectory.appendingPathComponent("session.json"),
            encoding: .utf8
        )
        XCTAssertEqual(persistedAlias, persistedMetadata)
    }

    func testEventStreamStartApprovalDeniedDoesNotCreateSession() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .deny
        )

        XCTAssertThrowsError(try service.start()) { error in
            XCTAssertEqual((error as? EventStreamStartApprovalError)?.decision, .denied)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, eventStreamStartApprovalDeniedMessage)
        }
        XCTAssertEqual(service.status(), .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
    }

    func testEventStreamStartApprovalCancelledDoesNotCreateSession() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .cancel
        )

        XCTAssertThrowsError(try service.start()) { error in
            XCTAssertEqual((error as? EventStreamStartApprovalError)?.decision, .cancelled)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, eventStreamStartApprovalCancelledMessage)
        }
        XCTAssertEqual(service.status(), .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
    }

    func testEventStreamServiceWaitReturnsAfterConcurrentStop() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let started = try service.start()
        let sessionID = try XCTUnwrap(started.sessionID)

        let expectation = expectation(description: "wait returned")
        let waitedStatus = EventStreamStatusBox()
        DispatchQueue.global().async {
            waitedStatus.value = service.wait(sessionID: sessionID, timeout: 2)
            expectation.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        let stopped = try service.stop()
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(waitedStatus.value?.sessionID, sessionID)
        XCTAssertEqual(waitedStatus.value?.state, .stopped)
        XCTAssertEqual(waitedStatus.value?.endReason, "recording_controls_stopped")
    }

    func testRunEventStreamCLIWaitReturnsAfterStop() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        let expectation = expectation(description: "cli wait returned")
        let waitedStatus = JSONDictionaryBox()
        DispatchQueue.global().async {
            let output = try? runOpenComputerUseEventStream(
                .wait(json: true, sessionID: sessionID, timeout: 2, notifyCommand: nil),
                service: service
            )
            waitedStatus.value = output?.jsonObject as? [String: Any]
            expectation.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        let stopped = try runOpenComputerUseEventStream(.stop(json: true), service: service)
        wait(for: [expectation], timeout: 3)

        let stoppedStatus = try XCTUnwrap(stopped.jsonObject as? [String: Any])
        XCTAssertEqual(stoppedStatus["state"] as? String, "stopped")
        XCTAssertEqual(waitedStatus.value?["sessionId"] as? String, sessionID)
        XCTAssertEqual(waitedStatus.value?["state"] as? String, "stopped")
        XCTAssertEqual(waitedStatus.value?["endReason"] as? String, "recording_controls_stopped")
        XCTAssertEqual(waitedStatus.value?["waitTimedOut"] as? Bool, false)
    }

    func testRunEventStreamCLIWaitReturnsImmediatelyAfterCompletedSession() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        _ = try runOpenComputerUseEventStream(.stop(json: true), service: service)

        let beforeWait = Date()
        let waited = try runOpenComputerUseEventStream(
            .wait(json: true, sessionID: sessionID, timeout: 5, notifyCommand: nil),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertLessThan(Date().timeIntervalSince(beforeWait), 0.5)
        XCTAssertEqual(waitedStatus["sessionId"] as? String, sessionID)
        XCTAssertEqual(waitedStatus["state"] as? String, "stopped")
        XCTAssertEqual(waitedStatus["endReason"] as? String, "recording_controls_stopped")
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, true)
    }

    func testRunEventStreamCLIWaitReturnsStoredCompletedSessionByID() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let firstStarted = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let firstStartedStatus = try XCTUnwrap(firstStarted.jsonObject as? [String: Any])
        let firstSessionID = try XCTUnwrap(firstStartedStatus["sessionId"] as? String)
        _ = try runOpenComputerUseEventStream(.stop(json: true), service: service)

        let secondStarted = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let secondStartedStatus = try XCTUnwrap(secondStarted.jsonObject as? [String: Any])
        let secondSessionID = try XCTUnwrap(secondStartedStatus["sessionId"] as? String)
        XCTAssertNotEqual(firstSessionID, secondSessionID)

        let beforeWait = Date()
        let waited = try runOpenComputerUseEventStream(
            .wait(json: true, sessionID: firstSessionID, timeout: 5, notifyCommand: nil),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertLessThan(Date().timeIntervalSince(beforeWait), 0.5)
        XCTAssertEqual(waitedStatus["sessionId"] as? String, firstSessionID)
        XCTAssertEqual(waitedStatus["state"] as? String, "stopped")
        XCTAssertEqual(waitedStatus["endReason"] as? String, "recording_controls_stopped")
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, true)

        let activeStatus = service.status()
        XCTAssertEqual(activeStatus.sessionID, secondSessionID)
        XCTAssertEqual(activeStatus.state, .recording)
        _ = try service.stop()
    }

    func testRunEventStreamCLIWaitForUnknownSessionDoesNotBlockOrNotify() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify.sh")
        let callbackMarkerPath = root.appendingPathComponent("called.txt")
        try """
        #!/bin/sh
        touch "$1"
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let beforeWait = Date()
        let waited = try runOpenComputerUseEventStream(
            .wait(
                json: true,
                sessionID: "session-20260626T000000000Z-missing",
                timeout: nil,
                notifyCommand: [callbackScript.path, callbackMarkerPath.path]
            ),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertLessThan(Date().timeIntervalSince(beforeWait), 0.5)
        XCTAssertFalse(waited.hasToolError)
        XCTAssertEqual(waitedStatus["state"] as? String, "idle")
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, true)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, false)
        let notification = try XCTUnwrap(waitedStatus["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, false)
        XCTAssertEqual(notification["skipped"] as? Bool, true)
        XCTAssertEqual(notification["reason"] as? String, "waitTimedOut")
        XCTAssertFalse(FileManager.default.fileExists(atPath: callbackMarkerPath.path))
    }

    func testRunEventStreamCLIWaitMarksTimeout() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        let waited = try runOpenComputerUseEventStream(
            .wait(json: true, sessionID: sessionID, timeout: 0.05, notifyCommand: nil),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertEqual(waitedStatus["sessionId"] as? String, sessionID)
        XCTAssertEqual(waitedStatus["state"] as? String, "recording")
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, true)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, true)

        _ = try service.stop()
    }

    func testRunEventStreamCLIWaitRunsNotifyCommandAfterStop() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify.sh")
        let callbackStatusPath = root.appendingPathComponent("notify-status.json")
        let callbackSessionPath = root.appendingPathComponent("notify-session.txt")
        let callbackReasonPath = root.appendingPathComponent("notify-reason.txt")
        try """
        #!/bin/sh
        cat > "$1"
        printf '%s' "$OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_ID" > "$2"
        printf '%s' "$OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON" > "$3"
        test "$OPEN_COMPUTER_USE_EVENT_STREAM_STATE" = "stopped"
        test -n "$OPEN_COMPUTER_USE_EVENT_STREAM_METADATA_PATH"
        test -f "$OPEN_COMPUTER_USE_EVENT_STREAM_SESSION_PATH"
        test -n "$OPEN_COMPUTER_USE_EVENT_STREAM_EVENTS_PATH"
        test -f "$OPEN_COMPUTER_USE_EVENT_STREAM_SUPPRESSED_EVENTS_PATH"
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        let expectation = expectation(description: "cli wait returned")
        let waitedStatus = JSONDictionaryBox()
        DispatchQueue.global().async {
            let output = try? runOpenComputerUseEventStream(
                .wait(
                    json: true,
                    sessionID: sessionID,
                    timeout: 2,
                    notifyCommand: [
                        callbackScript.path,
                        callbackStatusPath.path,
                        callbackSessionPath.path,
                        callbackReasonPath.path,
                    ]
                ),
                service: service
            )
            waitedStatus.value = output?.jsonObject as? [String: Any]
            expectation.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        _ = try runOpenComputerUseEventStream(.stop(json: true), service: service)
        wait(for: [expectation], timeout: 3)

        let waited = try XCTUnwrap(waitedStatus.value)
        XCTAssertEqual(waited["sessionId"] as? String, sessionID)
        XCTAssertEqual(waited["state"] as? String, "stopped")
        XCTAssertEqual(waited["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waited["waitSessionMatched"] as? Bool, true)
        let notification = try XCTUnwrap(waited["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, true)
        XCTAssertEqual(notification["skipped"] as? Bool, false)
        XCTAssertEqual(notification["ok"] as? Bool, true)
        XCTAssertEqual(notification["exitCode"] as? Int, 0)

        let callbackStatus = try jsonObject(contentsOf: callbackStatusPath)
        XCTAssertEqual(callbackStatus["sessionId"] as? String, sessionID)
        XCTAssertEqual(callbackStatus["state"] as? String, "stopped")
        XCTAssertEqual(callbackStatus["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(callbackStatus["waitSessionMatched"] as? Bool, true)
        let callbackSession = try String(contentsOf: callbackSessionPath, encoding: .utf8)
        XCTAssertEqual(callbackSession, sessionID)
        let callbackReason = try String(contentsOf: callbackReasonPath, encoding: .utf8)
        XCTAssertEqual(callbackReason, "recording_controls_stopped")
    }

    func testRunEventStreamCLIWaitRunsNotifyCommandAfterCancel() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify.sh")
        let callbackStatusPath = root.appendingPathComponent("notify-status.json")
        let callbackReasonPath = root.appendingPathComponent("notify-reason.txt")
        try """
        #!/bin/sh
        cat > "$1"
        printf '%s' "$OPEN_COMPUTER_USE_EVENT_STREAM_END_REASON" > "$2"
        test "$OPEN_COMPUTER_USE_EVENT_STREAM_STATE" = "cancelled"
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        let expectation = expectation(description: "cli wait returned after cancel")
        let waitedStatus = JSONDictionaryBox()
        DispatchQueue.global().async {
            let output = try? runOpenComputerUseEventStream(
                .wait(
                    json: true,
                    sessionID: sessionID,
                    timeout: 2,
                    notifyCommand: [callbackScript.path, callbackStatusPath.path, callbackReasonPath.path]
                ),
                service: service
            )
            waitedStatus.value = output?.jsonObject as? [String: Any]
            expectation.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        _ = try runOpenComputerUseEventStream(.cancel(json: true), service: service)
        wait(for: [expectation], timeout: 3)

        let waited = try XCTUnwrap(waitedStatus.value)
        XCTAssertEqual(waited["sessionId"] as? String, sessionID)
        XCTAssertEqual(waited["state"] as? String, "cancelled")
        XCTAssertEqual(waited["endReason"] as? String, "recording_controls_cancelled")
        XCTAssertEqual(waited["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waited["waitSessionMatched"] as? Bool, true)
        let notification = try XCTUnwrap(waited["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, true)
        XCTAssertEqual(notification["ok"] as? Bool, true)

        let callbackStatus = try jsonObject(contentsOf: callbackStatusPath)
        XCTAssertEqual(callbackStatus["sessionId"] as? String, sessionID)
        XCTAssertEqual(callbackStatus["state"] as? String, "cancelled")
        XCTAssertEqual(callbackStatus["endReason"] as? String, "recording_controls_cancelled")
        let callbackReason = try String(contentsOf: callbackReasonPath, encoding: .utf8)
        XCTAssertEqual(callbackReason, "recording_controls_cancelled")
    }

    func testRunEventStreamCLIWaitSkipsNotifyCommandOnTimeout() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify.sh")
        let callbackMarkerPath = root.appendingPathComponent("called.txt")
        try """
        #!/bin/sh
        touch "$1"
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)

        let waited = try runOpenComputerUseEventStream(
            .wait(
                json: true,
                sessionID: sessionID,
                timeout: 0.05,
                notifyCommand: [callbackScript.path, callbackMarkerPath.path]
            ),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertFalse(waited.hasToolError)
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, true)
        let notification = try XCTUnwrap(waitedStatus["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, false)
        XCTAssertEqual(notification["skipped"] as? Bool, true)
        XCTAssertEqual(notification["ok"] as? Bool, true)
        XCTAssertEqual(notification["reason"] as? String, "waitTimedOut")
        XCTAssertFalse(FileManager.default.fileExists(atPath: callbackMarkerPath.path))

        _ = try service.stop()
    }

    func testRunEventStreamCLIWaitReportsNotifyCommandNonZeroExit() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify-fail.sh")
        try """
        #!/bin/sh
        exit 7
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)
        _ = try runOpenComputerUseEventStream(.stop(json: true), service: service)

        let waited = try runOpenComputerUseEventStream(
            .wait(json: true, sessionID: sessionID, timeout: 1, notifyCommand: [callbackScript.path]),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertTrue(waited.hasToolError)
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, true)
        let notification = try XCTUnwrap(waitedStatus["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, true)
        XCTAssertEqual(notification["skipped"] as? Bool, false)
        XCTAssertEqual(notification["ok"] as? Bool, false)
        XCTAssertEqual(notification["exitCode"] as? Int, 7)
        XCTAssertEqual(notification["timedOut"] as? Bool, false)
        XCTAssertEqual(notification["reason"] as? String, "nonZeroExit")
    }

    func testRunEventStreamCLIWaitReportsNotifyCommandTimeout() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let callbackScript = root.appendingPathComponent("notify-sleep.sh")
        try """
        #!/bin/sh
        sleep 2
        """.write(to: callbackScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callbackScript.path)

        let started = try runOpenComputerUseEventStream(.start(json: true), service: service)
        let startedStatus = try XCTUnwrap(started.jsonObject as? [String: Any])
        let sessionID = try XCTUnwrap(startedStatus["sessionId"] as? String)
        _ = try runOpenComputerUseEventStream(.stop(json: true), service: service)

        setenv("OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS", "0.1", 1)
        defer {
            unsetenv("OPEN_COMPUTER_USE_EVENT_STREAM_NOTIFY_TIMEOUT_SECONDS")
        }

        let waited = try runOpenComputerUseEventStream(
            .wait(json: true, sessionID: sessionID, timeout: 1, notifyCommand: [callbackScript.path]),
            service: service
        )
        let waitedStatus = try XCTUnwrap(waited.jsonObject as? [String: Any])

        XCTAssertTrue(waited.hasToolError)
        XCTAssertEqual(waitedStatus["waitTimedOut"] as? Bool, false)
        XCTAssertEqual(waitedStatus["waitSessionMatched"] as? Bool, true)
        let notification = try XCTUnwrap(waitedStatus["notification"] as? [String: Any])
        XCTAssertEqual(notification["attempted"] as? Bool, true)
        XCTAssertEqual(notification["skipped"] as? Bool, false)
        XCTAssertEqual(notification["ok"] as? Bool, false)
        XCTAssertEqual(notification["timedOut"] as? Bool, true)
        XCTAssertEqual(notification["reason"] as? String, "timeout")
        XCTAssertEqual(notification["timeoutSeconds"] as? Double, 0.1)
    }

    func testEventStreamRecordingSummaryRedactsTextByDefault() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))

        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 3)
        XCTAssertEqual(summary["includesRawText"] as? Bool, false)

        let jsonData = try JSONSerialization.data(withJSONObject: summary)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? ""
        XCTAssertFalse(jsonText.contains("secret-value"))
        XCTAssertFalse(jsonText.contains("selected-secret"))
        XCTAssertTrue(jsonText.contains("valueLength"))
        XCTAssertTrue(jsonText.contains("selectedTextLength"))

        let runtimeInputs = try XCTUnwrap(summary["runtimeInputs"] as? [[String: Any]])
        XCTAssertEqual(runtimeInputs.count, 2)
        XCTAssertEqual(runtimeInputs.first?["kind"] as? String, "text")
        XCTAssertEqual(runtimeInputs.first?["sourceEventType"] as? String, "keyboard.text_input")
        XCTAssertEqual(runtimeInputs.first?["textLength"] as? Int, 6)
        XCTAssertEqual(runtimeInputs.first?["sensitive"] as? Bool, true)
        XCTAssertEqual(runtimeInputs.last?["kind"] as? String, "selection")
        XCTAssertEqual(runtimeInputs.last?["sourceEventType"] as? String, "selection.changed")

        let summaryLimits = try XCTUnwrap(summary["summaryLimits"] as? [String: Any])
        XCTAssertEqual(summaryLimits["hasTruncatedSummary"] as? Bool, false)
        let omittedCounts = try XCTUnwrap(summaryLimits["omittedCounts"] as? [String: Int])
        XCTAssertEqual(omittedCounts["actionSequence"], 0)

        let safetySignals = try XCTUnwrap(summary["safetySignals"] as? [[String: Any]])
        XCTAssertEqual(safetySignals.count, 1)
        XCTAssertEqual(safetySignals.first?["sourceEventType"] as? String, "mouse.click")
        XCTAssertEqual(safetySignals.first?["reason"] as? String, "saveAction")
        XCTAssertEqual(safetySignals.first?["confirmationRequired"] as? Bool, true)
        let safetyTarget = try XCTUnwrap(safetySignals.first?["target"] as? [String: Any])
        XCTAssertEqual(safetyTarget["title"] as? String, "Save")

        let skillEvidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(skillEvidence["hasActionEvents"] as? Bool, true)
        XCTAssertEqual(skillEvidence["hasPointerEvents"] as? Bool, true)
        XCTAssertEqual(skillEvidence["hasInputEvents"] as? Bool, true)
        XCTAssertEqual(skillEvidence["hasRedactionSignals"] as? Bool, true)
        XCTAssertEqual(skillEvidence["hasSafetySignals"] as? Bool, true)

        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "needsReview")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, true)
        XCTAssertEqual(skillReadiness["requiresHumanReview"] as? Bool, true)
        let readinessReasons = try XCTUnwrap(skillReadiness["reasons"] as? [String])
        XCTAssertTrue(readinessReasons.contains("recording has no AX focused window context"))
        XCTAssertTrue(readinessReasons.contains("recording includes redaction or secureInput signals"))
        XCTAssertTrue(readinessReasons.contains("recording includes actions that may require explicit user confirmation"))
    }

    func testEventStreamRecordingSummaryReportsTruncatedFields() throws {
        let root = try makeTemporaryDirectory()
        let eventsURL = root.appendingPathComponent("events.jsonl")
        let metadataURL = root.appendingPathComponent("metadata.json")

        var events: [[String: Any]] = [
            [
                "type": "session.started",
                "timestamp": "2026-06-26T00:00:00.000Z",
                "sessionId": "summary-long-fixture",
            ],
            [
                "type": "window.changed",
                "timestamp": "2026-06-26T00:00:01.000Z",
                "sessionId": "summary-long-fixture",
                "appName": "Fixture",
                "windowTitle": "Long Demo",
            ],
        ]
        for index in 0 ..< 55 {
            events.append([
                "type": "mouse.click",
                "timestamp": "2026-06-26T00:00:\(String(format: "%02d", index + 2)).000Z",
                "sessionId": "summary-long-fixture",
                "appName": "Fixture",
                "windowTitle": "Long Demo",
                "targetAccessibilityElement": [
                    "role": "AXButton",
                    "title": "Step \(index)",
                ],
            ])
        }
        events.append([
            "type": "session.ended",
            "timestamp": "2026-06-26T00:01:00.000Z",
            "sessionId": "summary-long-fixture",
            "endReason": "recording_controls_stopped",
        ])

        let lines = try events.map { event -> String in
            let data = try JSONSerialization.data(withJSONObject: event, options: [.withoutEscapingSlashes])
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")
        try (lines + "\n").write(to: eventsURL, atomically: true, encoding: .utf8)
        try [
            "sessionId": "summary-long-fixture",
            "state": "stopped",
            "active": false,
            "endReason": "recording_controls_stopped",
            "eventCount": events.count,
            "suppressedEventCount": 0,
            "eventsPath": eventsURL.path,
            "metadataPath": metadataURL.path,
        ].writeJSONObject(to: metadataURL)

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: metadataURL.path,
            includeText: false,
            requireAction: true
        ))

        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 55)
        XCTAssertEqual((summary["actionSequence"] as? [[String: Any]])?.count, 50)
        XCTAssertEqual((summary["targetElements"] as? [[String: Any]])?.count, 25)

        let summaryLimits = try XCTUnwrap(summary["summaryLimits"] as? [String: Any])
        XCTAssertEqual(summaryLimits["hasTruncatedSummary"] as? Bool, true)
        let omittedCounts = try XCTUnwrap(summaryLimits["omittedCounts"] as? [String: Int])
        XCTAssertEqual(omittedCounts["actionSequence"], 5)
        XCTAssertEqual(omittedCounts["targetElements"], 30)

        let warnings = try XCTUnwrap(summary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill"))

        let skillEvidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(skillEvidence["hasTruncatedSummary"] as? Bool, true)
        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        let readinessReasons = try XCTUnwrap(skillReadiness["reasons"] as? [String])
        XCTAssertTrue(readinessReasons.contains("recording summary truncated high-volume fields; inspect events.jsonl before finalizing a skill"))
    }

    func testEventStreamRecordingSummaryCanIncludeTextForSanitizedFixtures() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.sessionDirectory.path,
            includeText: true,
            requireAction: true
        ))
        let jsonData = try JSONSerialization.data(withJSONObject: summary)
        let jsonText = String(data: jsonData, encoding: .utf8) ?? ""

        XCTAssertEqual(summary["includesRawText"] as? Bool, true)
        XCTAssertTrue(jsonText.contains("secret-value"))
        XCTAssertTrue(jsonText.contains("selected-secret"))
    }

    func testEventStreamRecordingSummaryRequireActionMarksToolError() throws {
        let root = try makeTemporaryDirectory()
        let eventsURL = root.appendingPathComponent("events.jsonl")
        let metadataURL = root.appendingPathComponent("metadata.json")
        try #"{"type":"session.started","sessionId":"summary-no-action"}"#
            .appending("\n")
            .write(to: eventsURL, atomically: true, encoding: .utf8)
        try [
            "sessionId": "summary-no-action",
            "state": "recording",
            "active": true,
            "eventCount": 1,
            "suppressedEventCount": 0,
            "eventsPath": eventsURL.path,
            "metadataPath": metadataURL.path,
        ].writeJSONObject(to: metadataURL)

        let output = try runOpenComputerUseEventStream(.summarize(
            inputPath: metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        let summary = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 0)
        let errors = try XCTUnwrap(summary["errors"] as? [String])
        XCTAssertTrue(errors.contains("required at least one high-level user action event"))
        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "insufficient")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingSummaryCancelledIsInsufficientForSkillCreation() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )

        let output = try runOpenComputerUseEventStream(.summarize(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        let summary = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 3)
        XCTAssertEqual(summary["state"] as? String, "cancelled")
        XCTAssertEqual(summary["endReason"] as? String, "recording_controls_cancelled")
        let errors = try XCTUnwrap(summary["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
        let warnings = try XCTUnwrap(summary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains("recording was cancelled; do not create or update a skill from this event stream"))

        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "insufficient")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, false)
        XCTAssertEqual(skillReadiness["requiresHumanReview"] as? Bool, true)
        let readinessReasons = try XCTUnwrap(skillReadiness["reasons"] as? [String])
        XCTAssertTrue(readinessReasons.contains("recording was cancelled; do not create or update a skill from this event stream"))
    }

    func testEventStreamRecordingSummaryDetectsCancelledEventsJSONLInput() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )

        let output = try runOpenComputerUseEventStream(.summarize(
            inputPath: fixture.eventsURL.path,
            includeText: false,
            requireAction: true
        ))
        let summary = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["endReason"] as? String, "recording_controls_cancelled")
        let errors = try XCTUnwrap(summary["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "insufficient")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingSummaryIncompleteRecordingIsInsufficientForSkillCreation() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "recording",
            endReason: "",
            includeSessionEnded: false
        )

        let output = try runOpenComputerUseEventStream(.summarize(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        let summary = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 3)
        XCTAssertEqual(summary["state"] as? String, "recording")
        let errors = try XCTUnwrap(summary["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording is not complete; stop the recording before creating a skill"))
        let warnings = try XCTUnwrap(summary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains("recording is not complete; stop the recording before creating a skill"))

        let skillEvidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(skillEvidence["recordingIncomplete"] as? Bool, true)

        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "insufficient")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, false)
        XCTAssertEqual(skillReadiness["requiresHumanReview"] as? Bool, true)
        let readinessReasons = try XCTUnwrap(skillReadiness["reasons"] as? [String])
        XCTAssertTrue(readinessReasons.contains("recording is not complete; stop the recording before creating a skill"))
    }

    func testEventStreamRecordingSummaryBlockingDiagnosticsAreInsufficientForSkillCreation() throws {
        let fixture = try makeEventStreamSummaryFixture(includeBlockingDiagnostic: true)

        let output = try runOpenComputerUseEventStream(.summarize(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        let summary = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 3)
        let errors = try XCTUnwrap(summary["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))
        let warnings = try XCTUnwrap(summary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))

        let blockingDiagnostics = try XCTUnwrap(summary["blockingDiagnostics"] as? [[String: Any]])
        XCTAssertEqual(blockingDiagnostics.count, 1)
        XCTAssertEqual(blockingDiagnostics.first?["subsystem"] as? String, "inputMonitoring")
        XCTAssertEqual(blockingDiagnostics.first?["reason"] as? String, "inputMonitorsUnavailable")

        let skillEvidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(skillEvidence["hasBlockingDiagnostics"] as? Bool, true)

        let skillReadiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(skillReadiness["status"] as? String, "insufficient")
        XCTAssertEqual(skillReadiness["canCreateSkillDraft"] as? Bool, false)
        XCTAssertEqual(skillReadiness["requiresHumanReview"] as? Bool, true)
        let readinessReasons = try XCTUnwrap(skillReadiness["reasons"] as? [String])
        XCTAssertTrue(readinessReasons.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))
    }

    func testEventStreamSkillScaffoldWritesDraftAndSanitizedSummary() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("generated-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "recorded-example-workflow",
            description: "Replay an example workflow.",
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertFalse(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["skillName"] as? String, "recorded-example-workflow")

        let skillURL = outputDirectory.appendingPathComponent("SKILL.md")
        let summaryURL = outputDirectory.appendingPathComponent("references/recording-summary.json")
        let skillText = try String(contentsOf: skillURL, encoding: .utf8)
        let summaryText = try String(contentsOf: summaryURL, encoding: .utf8)

        XCTAssertTrue(skillText.contains("name: recorded-example-workflow"))
        XCTAssertTrue(skillText.contains("Click role=\"AXButton\", title=\"Save\" in the recorded app."))
        XCTAssertTrue(skillText.contains("Enter user-provided text into role=\"AXTextField\", label=\"Token\""))
        XCTAssertTrue(skillText.contains("## Runtime Inputs"))
        XCTAssertTrue(skillText.contains("Runtime text for role=\"AXTextField\", label=\"Token\""))
        XCTAssertTrue(skillText.contains("use a fresh runtime value"))
        XCTAssertTrue(skillText.contains("Treat this as sensitive input"))
        XCTAssertTrue(skillText.contains("Runtime selection or selected-content meaning"))
        XCTAssertTrue(skillText.contains("## Summary Limits"))
        XCTAssertTrue(skillText.contains("No high-volume summary fields were truncated."))
        XCTAssertTrue(skillText.contains("### Confirmation Signals"))
        XCTAssertTrue(skillText.contains("`mouse.click` matched saveAction"))
        XCTAssertTrue(skillText.contains("ask for explicit confirmation before replaying this step"))
        XCTAssertTrue(skillText.contains("## Workflow Readiness"))
        XCTAssertTrue(skillText.contains("Status: needsReview"))
        XCTAssertTrue(skillText.contains("recording has no AX focused window context"))
        XCTAssertTrue(skillText.contains("## Agent Replay Procedure"))
        XCTAssertTrue(skillText.contains("connector, API, or dedicated tool"))
        XCTAssertTrue(skillText.contains("visually dependent verification"))
        XCTAssertTrue(skillText.contains("get_app_state"))
        XCTAssertTrue(skillText.contains("`element_index` actions"))
        XCTAssertTrue(skillText.contains("## Verification"))
        XCTAssertTrue(skillText.contains("open-computer-use event-stream validate --json --strict-ocu --require-skill-draft <metadata-or-session>"))
        XCTAssertTrue(skillText.contains("## Finalizing The Skill"))
        XCTAssertTrue(skillText.contains("skill-creator"))
        XCTAssertTrue(skillText.contains("not a standalone runbook or replay plan"))
        XCTAssertFalse(skillText.contains("secret-value"))
        XCTAssertFalse(summaryText.contains(fixture.sessionDirectory.path))
        XCTAssertFalse(summaryText.contains("secret-value"))
        XCTAssertTrue(summaryText.contains(#""sessionDir" : "<recording-sessionDir>""#))
        XCTAssertTrue(summaryText.contains(#""metadataPath" : "<recording-metadataPath>""#))
        XCTAssertTrue(summaryText.contains(#""eventsPath" : "<recording-eventsPath>""#))
        XCTAssertTrue(summaryText.contains(#""runtimeInputs""#))
        XCTAssertTrue(summaryText.contains(#""safetySignals""#))
        XCTAssertTrue(summaryText.contains(#""summaryLimits""#))
        XCTAssertTrue(summaryText.contains(#""hasSafetySignals" : true"#))
        XCTAssertTrue(summaryText.contains(#""skillReadiness""#))

        let duplicateOutput = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "recorded-example-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let duplicateResult = try XCTUnwrap(duplicateOutput.jsonObject as? [String: Any])
        XCTAssertTrue(duplicateOutput.hasToolError)
        XCTAssertEqual(duplicateResult["error"] as? String, "outputDirectoryExists")
    }

    func testEventStreamSummaryAndScaffoldSurfaceScrollRawEventsAsReplaySteps() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var events = try jsonObjects(contentsOf: fixture.eventsURL)
        let scrollEvent: [String: Any] = [
            "type": "experimentalRawEvents",
            "timestamp": "2026-06-26T00:00:04.250Z",
            "sessionId": "summary-fixture",
            "reason": "scrollWheel",
            "appName": "Fixture",
            "windowTitle": "Demo",
            "experimentalRawEvents": [
                [
                    "eventType": "scrollWheel",
                    "scrollingDeltaX": 0,
                    "scrollingDeltaY": -4,
                    "hasPreciseScrollingDeltas": false,
                ],
            ],
        ]
        events.insert(scrollEvent, at: max(0, events.count - 1))
        try writeEventStreamFixtureEvents(events, fixture: fixture)

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 4)
        let actions = try XCTUnwrap(summary["actionSequence"] as? [[String: Any]])
        let scrollAction = try XCTUnwrap(actions.first { $0["reason"] as? String == "scrollWheel" })
        XCTAssertEqual(scrollAction["type"] as? String, "experimentalRawEvents")
        XCTAssertEqual(scrollAction["rawEventTypes"] as? [String], ["scrollWheel"])
        XCTAssertEqual(scrollAction["scrollingDeltaY"] as? Int, -4)

        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("generated-scroll-skill")
        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "recorded-scroll-workflow",
            description: "Replay a scroll workflow.",
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        XCTAssertFalse(output.hasToolError)
        let skillText = try String(
            contentsOf: outputDirectory.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        XCTAssertTrue(skillText.contains("Scroll in Fixture using the recorded wheel direction"))
    }

    func testEventStreamSkillScaffoldAcceptsEventsJSONLInput() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("events-jsonl-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.eventsURL.path,
            skillName: "events-jsonl-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertFalse(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("SKILL.md").path))
        let summaryText = try String(
            contentsOf: outputDirectory.appendingPathComponent("references/recording-summary.json"),
            encoding: .utf8
        )
        XCTAssertTrue(summaryText.contains(#""eventsPath" : "<recording-eventsPath>""#))
        XCTAssertFalse(summaryText.contains(fixture.sessionDirectory.path))
    }

    func testEventStreamSkillScaffoldRejectsInvalidSkillName() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "Bad_Name",
            description: nil,
            outputDirectory: fixture.sessionDirectory.appendingPathComponent("bad-skill").path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "invalidSkillName")
    }

    func testEventStreamSkillScaffoldRejectsCancelledRecording() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("cancelled-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "cancelled-recording-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "recordingValidationFailed")
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testEventStreamSkillScaffoldRejectsCancelledEventsJSONLInput() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("cancelled-events-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.eventsURL.path,
            skillName: "cancelled-events-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "recordingValidationFailed")
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testEventStreamSkillScaffoldRejectsIncompleteRecording() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "recording",
            endReason: "",
            includeSessionEnded: false
        )
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("incomplete-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "incomplete-recording-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "recordingValidationFailed")
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording is not complete; stop the recording before creating a skill"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testEventStreamSkillScaffoldRejectsBlockingDiagnostics() throws {
        let fixture = try makeEventStreamSummaryFixture(includeBlockingDiagnostic: true)
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("diagnostic-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.metadataURL.path,
            skillName: "diagnostic-recording-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "recordingValidationFailed")
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testEventStreamSkillScaffoldRejectsInvalidRecordingStructure() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["eventCount"] = 999
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))
        let outputDirectory = fixture.sessionDirectory.appendingPathComponent("invalid-structure-skill")

        let output = try runOpenComputerUseEventStream(.scaffoldSkill(
            inputPath: fixture.sessionDirectory.path,
            skillName: "invalid-structure-workflow",
            description: nil,
            outputDirectory: outputDirectory.path,
            overwrite: false,
            includeText: false
        ))
        let result = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "recordingValidationFailed")
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertTrue(errors.contains("eventCount=999 does not match events.jsonl lines=6"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    func testEventStreamRecordingValidationAcceptsStrictOCUFixture() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.metadataURL.path,
            strictOCU: true,
            requiredEventTypes: ["session.started", "mouse.click", "session.ended"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertFalse(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, true)
        XCTAssertEqual(validation["eventCount"] as? Int, 6)
        XCTAssertEqual(validation["metadataEventCount"] as? Int, 6)
        XCTAssertEqual(validation["requireSkillDraft"] as? Bool, true)
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, true)
        XCTAssertEqual(validation["skillDraftReasons"] as? [String], [])
        let declaredPaths = try XCTUnwrap(validation["declaredPaths"] as? [String: [String: Any]])
        XCTAssertEqual(declaredPaths["metadataPath"]?["exists"] as? Bool, true)
        XCTAssertEqual(declaredPaths["sessionPath"]?["exists"] as? Bool, true)
        XCTAssertEqual(declaredPaths["eventsPath"]?["exists"] as? Bool, true)
        XCTAssertEqual(declaredPaths["suppressedEventsPath"]?["exists"] as? Bool, true)
        let eventTypes = try XCTUnwrap(validation["eventTypes"] as? [String: Int])
        XCTAssertEqual(eventTypes["mouse.click"], 1)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(validation))
    }

    func testEventStreamRecordingValidationStrictOCURequiresDeclaredHandoffPaths() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata.removeValue(forKey: "metadataPath")
        metadata.removeValue(forKey: "sessionPath")
        metadata.removeValue(forKey: "eventsPath")
        metadata.removeValue(forKey: "suppressedEventsPath")
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("strict OCU validation requires metadataPath"))
        XCTAssertTrue(errors.contains("strict OCU validation requires sessionPath"))
        XCTAssertTrue(errors.contains("strict OCU validation requires eventsPath"))
        XCTAssertTrue(errors.contains("strict OCU validation requires suppressedEventsPath"))
        let declaredPaths = try XCTUnwrap(validation["declaredPaths"] as? [String: [String: Any]])
        XCTAssertNotNil(declaredPaths["eventsPath"]?["exists"] as? NSNull)
    }

    func testEventStreamRecordingValidationReportsBadDeclaredHandoffPath() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["sessionPath"] = "missing-session.json"
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("sessionPath does not exist: missing-session.json"))
        let declaredPaths = try XCTUnwrap(validation["declaredPaths"] as? [String: [String: Any]])
        XCTAssertEqual(declaredPaths["sessionPath"]?["exists"] as? Bool, false)
    }

    func testEventStreamRecordingValidationRejectsExternalScreenshotPath() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let externalScreenshotURL = fixture.sessionDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("outside-session-screenshot.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: externalScreenshotURL)

        var events = try jsonObjects(contentsOf: fixture.eventsURL)
        events[2]["accessibilityInspectorPayload"] = [
            "screenshotPath": externalScreenshotURL.path,
        ]
        try writeEventStreamFixtureEvents(events, fixture: fixture)

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("screenshotPath from event line 3 must stay inside session directory: \(externalScreenshotURL.path)"))
        XCTAssertFalse(errors.contains("screenshotPath from event line 3 does not exist: \(externalScreenshotURL.path)"))
    }

    func testEventStreamRecordingValidationAcceptsEventsJSONLInputWithoutStrictOCU() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.eventsURL.path,
            strictOCU: false,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertFalse(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, true)
        XCTAssertEqual(validation["eventCount"] as? Int, 6)
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, true)
        XCTAssertNil(validation["metadataPath"])
        let warnings = try XCTUnwrap(validation["warnings"] as? [String])
        XCTAssertTrue(warnings.contains("metadata/session files not available; validating events.jsonl only"))
    }

    func testEventStreamRecordingValidationRejectsCancelledEventsJSONLInput() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.eventsURL.path,
            strictOCU: false,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["endReason"] as? String, "recording_controls_cancelled")
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, false)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording was cancelled; do not create or update a skill from this event stream"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
    }

    func testEventStreamRecordingValidationRejectsEventsJSONLInputWithStrictOCU() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.eventsURL.path,
            strictOCU: true,
            requiredEventTypes: [],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("strict OCU validation requires metadata.json or session.json"))
    }

    func testEventStreamRecordingValidationRequireSkillDraftRejectsCancelledRecording() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "cancelled",
            endReason: "recording_controls_cancelled"
        )

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.metadataURL.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["requireSkillDraft"] as? Bool, true)
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, false)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording was cancelled; do not create or update a skill from this event stream"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording was cancelled; do not create or update a skill from this event stream"))
    }

    func testEventStreamRecordingValidationRequireSkillDraftRejectsIncompleteRecording() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "recording",
            endReason: "",
            includeSessionEnded: false
        )

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.metadataURL.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["requireSkillDraft"] as? Bool, true)
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, false)
        XCTAssertEqual(validation["recordingIncomplete"] as? Bool, true)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording is not complete; stop the recording before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording is not complete; stop the recording before creating a skill"))
    }

    func testEventStreamRecordingValidationRequireSkillDraftRejectsBlockingDiagnostics() throws {
        let fixture = try makeEventStreamSummaryFixture(includeBlockingDiagnostic: true)

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.metadataURL.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["requireSkillDraft"] as? Bool, true)
        XCTAssertEqual(validation["skillDraftReady"] as? Bool, false)
        let blockingDiagnostics = try XCTUnwrap(validation["blockingDiagnostics"] as? [[String: Any]])
        XCTAssertEqual(blockingDiagnostics.count, 1)
        XCTAssertEqual(blockingDiagnostics.first?["reason"] as? String, "inputMonitorsUnavailable")
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has blocking diagnostics; fix recording permissions and re-record before creating a skill"))
    }

    func testEventStreamRecordingValidationReportsMissingRequiredEventType() throws {
        let fixture = try makeEventStreamSummaryFixture()

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: false,
            requiredEventTypes: ["keyboard.shortcut"],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("missing required event type: keyboard.shortcut"))
    }

    func testEventStreamRecordingValidationAcceptsOfficialStyleSessionHandoffAlias() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["startedAt"] = "2026-06-26T00:00:00.000Z"
        metadata["endedAt"] = "2026-06-26T00:00:05.000Z"
        try metadata.writeJSONObject(to: fixture.metadataURL)
        let sessionAlias: [String: Any] = [
            "id": metadata["sessionId"] as? String ?? "summary-fixture",
            "startedAt": "2026-06-26T00:00:00.000Z",
            "endedAt": "2026-06-26T00:00:05.000Z",
            "endReason": "recording_controls_stopped",
            "eventsPath": metadata["eventsPath"] as? String ?? fixture.eventsURL.path,
        ]
        try sessionAlias.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertFalse(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, true)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertFalse(errors.contains("metadata.json and session.json differ"))
    }

    func testEventStreamRecordingValidationReportsEventCountMismatch() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let metadata = try jsonObject(contentsOf: fixture.metadataURL)
        var mutated = metadata
        mutated["eventCount"] = 999
        try mutated.writeJSONObject(to: fixture.metadataURL)
        try mutated.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: [],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("eventCount=999 does not match events.jsonl lines=6"))
    }

    func testEventStreamRecordingValidationRequiresCurrentSegmentPathsWhileRecording() throws {
        let fixture = try makeEventStreamSummaryFixture(
            state: "recording",
            endReason: "",
            includeSessionEnded: false
        )
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata.removeValue(forKey: "currentSegmentEventsPath")
        metadata.removeValue(forKey: "currentSegmentMetadataPath")
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: [],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording state requires currentSegmentEventsPath"))
        XCTAssertTrue(errors.contains("recording state requires currentSegmentMetadataPath"))
    }

    func testEventStreamRecordingValidationRejectsCurrentSegmentPathsAfterFinalState() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["currentSegmentEventsPath"] = fixture.eventsURL.path
        metadata["currentSegmentMetadataPath"] = fixture.metadataURL.path
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: [],
            requireSkillDraft: false
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("final state must not include currentSegmentEventsPath"))
        XCTAssertTrue(errors.contains("final state must not include currentSegmentMetadataPath"))
    }

    func testEventStreamRecordingValidationRejectsSessionEndedBeforeFinalEvent() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let trailingEvent: [String: Any] = [
            "type": "window.changed",
            "timestamp": "2026-06-26T00:00:06.000Z",
            "sessionId": "summary-fixture",
            "appName": "Fixture",
            "windowTitle": "Late Event",
        ]
        let trailingData = try JSONSerialization.data(
            withJSONObject: trailingEvent,
            options: [.withoutEscapingSlashes]
        )
        let trailingLine = String(data: trailingData, encoding: .utf8) ?? "{}"
        let currentEvents = try String(contentsOf: fixture.eventsURL, encoding: .utf8)
        try (currentEvents + trailingLine + "\n").write(to: fixture.eventsURL, atomically: true, encoding: .utf8)

        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["eventCount"] = 7
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["finalEventType"] as? String, "window.changed")
        XCTAssertEqual(validation["sessionEndedIsFinal"] as? Bool, false)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording has events after session.ended; stop or cancel must be the final event before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("session.ended is not the final event"))
        XCTAssertTrue(errors.contains("recording has events after session.ended; stop or cancel must be the final event before creating a skill"))

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["finalEventType"] as? String, "window.changed")
        XCTAssertEqual(summary["sessionEndedIsFinal"] as? Bool, false)
        let evidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(evidence["sessionEndedNotFinal"] as? Bool, true)
        let readiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(readiness["status"] as? String, "insufficient")
        XCTAssertEqual(readiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingValidationRejectsMultipleSessionEndedEvents() throws {
        let fixture = try makeEventStreamSummaryFixture()
        let duplicateEndEvent: [String: Any] = [
            "type": "session.ended",
            "timestamp": "2026-06-26T00:00:06.000Z",
            "sessionId": "summary-fixture",
            "endReason": "recording_controls_stopped",
        ]
        let duplicateEndData = try JSONSerialization.data(
            withJSONObject: duplicateEndEvent,
            options: [.withoutEscapingSlashes]
        )
        let duplicateEndLine = String(data: duplicateEndData, encoding: .utf8) ?? "{}"
        let currentEvents = try String(contentsOf: fixture.eventsURL, encoding: .utf8)
        try (currentEvents + duplicateEndLine + "\n").write(to: fixture.eventsURL, atomically: true, encoding: .utf8)

        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["eventCount"] = 7
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["sessionEndedCount"] as? Int, 2)
        XCTAssertEqual(validation["sessionEndedCountInvalid"] as? Bool, true)
        XCTAssertEqual(validation["sessionEndedIsFinal"] as? Bool, true)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording has multiple session.ended events; stop or cancel must close the event stream exactly once"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has multiple session.ended events"))
        XCTAssertTrue(errors.contains("recording has multiple session.ended events; stop or cancel must close the event stream exactly once"))

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["sessionEndedCount"] as? Int, 2)
        let evidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(evidence["sessionEndedCountInvalid"] as? Bool, true)
        let readiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(readiness["status"] as? String, "insufficient")
        XCTAssertEqual(readiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingValidationRejectsMissingSessionStartedEvent() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var events = try jsonObjects(contentsOf: fixture.eventsURL)
        events.removeAll { $0["type"] as? String == "session.started" }
        try writeEventStreamFixtureEvents(events, fixture: fixture)

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, false)
        XCTAssertEqual(validation["sessionStartedCount"] as? Int, 0)
        XCTAssertEqual(validation["sessionStartedCountInvalid"] as? Bool, true)
        XCTAssertEqual(validation["firstEventType"] as? String, "window.changed")
        XCTAssertEqual(validation["sessionStartedIsFirst"] as? Bool, false)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording must contain exactly one session.started event before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has no session.started event"))
        XCTAssertTrue(errors.contains("recording must contain exactly one session.started event before creating a skill"))

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["sessionStartedCount"] as? Int, 0)
        let evidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(evidence["sessionStartedCountInvalid"] as? Bool, true)
        let readiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(readiness["status"] as? String, "insufficient")
        XCTAssertEqual(readiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingValidationRejectsMultipleSessionStartedEvents() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var events = try jsonObjects(contentsOf: fixture.eventsURL)
        let duplicateStartEvent: [String: Any] = [
            "type": "session.started",
            "timestamp": "2026-06-26T00:00:00.500Z",
            "sessionId": "summary-fixture",
        ]
        events.insert(duplicateStartEvent, at: 1)
        try writeEventStreamFixtureEvents(events, fixture: fixture)

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["sessionStartedCount"] as? Int, 2)
        XCTAssertEqual(validation["sessionStartedCountInvalid"] as? Bool, true)
        XCTAssertEqual(validation["sessionStartedIsFirst"] as? Bool, true)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording must contain exactly one session.started event before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("recording has multiple session.started events"))
    }

    func testEventStreamRecordingValidationRejectsSessionStartedAfterFirstEvent() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var events = try jsonObjects(contentsOf: fixture.eventsURL)
        let first = events.removeFirst()
        events.insert(first, at: 1)
        try writeEventStreamFixtureEvents(events, fixture: fixture)

        let output = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(output.jsonObject as? [String: Any])

        XCTAssertTrue(output.hasToolError)
        XCTAssertEqual(validation["firstEventType"] as? String, "window.changed")
        XCTAssertEqual(validation["sessionStartedCount"] as? Int, 1)
        XCTAssertEqual(validation["sessionStartedCountInvalid"] as? Bool, false)
        XCTAssertEqual(validation["sessionStartedIsFirst"] as? Bool, false)
        let reasons = try XCTUnwrap(validation["skillDraftReasons"] as? [String])
        XCTAssertTrue(reasons.contains("recording has events before session.started; start must be the first event before creating a skill"))
        let errors = try XCTUnwrap(validation["errors"] as? [String])
        XCTAssertTrue(errors.contains("session.started is not the first event"))
        XCTAssertTrue(errors.contains("recording has events before session.started; start must be the first event before creating a skill"))

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, false)
        XCTAssertEqual(summary["firstEventType"] as? String, "window.changed")
        XCTAssertEqual(summary["sessionStartedIsFirst"] as? Bool, false)
        let evidence = try XCTUnwrap(summary["skillEvidence"] as? [String: Any])
        XCTAssertEqual(evidence["sessionStartedNotFirst"] as? Bool, true)
        let readiness = try XCTUnwrap(summary["skillReadiness"] as? [String: Any])
        XCTAssertEqual(readiness["status"] as? String, "insufficient")
        XCTAssertEqual(readiness["canCreateSkillDraft"] as? Bool, false)
    }

    func testEventStreamRecordingToolsAcceptRelativeFixturePaths() throws {
        let fixture = try makeEventStreamSummaryFixture()
        var metadata = try jsonObject(contentsOf: fixture.metadataURL)
        metadata["metadataPath"] = "metadata.json"
        metadata["sessionPath"] = "session.json"
        metadata["eventsPath"] = "events.jsonl"
        metadata["suppressedEventsPath"] = "suppressed.jsonl"
        try metadata.writeJSONObject(to: fixture.metadataURL)
        try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))

        let validationOutput = try runOpenComputerUseEventStream(.validate(
            inputPath: fixture.sessionDirectory.path,
            strictOCU: true,
            requiredEventTypes: ["mouse.click"],
            requireSkillDraft: true
        ))
        let validation = try XCTUnwrap(validationOutput.jsonObject as? [String: Any])
        XCTAssertFalse(validationOutput.hasToolError)
        XCTAssertEqual(validation["ok"] as? Bool, true)

        let summary = try summarizeEventStreamRecording(options: EventStreamRecordingSummaryOptions(
            inputPath: fixture.metadataURL.path,
            includeText: false,
            requireAction: true
        ))
        XCTAssertEqual(summary["ok"] as? Bool, true)
        XCTAssertEqual(summary["actionEventCount"] as? Int, 3)
    }

    func testEventStreamServiceStopsAtMaximumDuration() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            maximumDuration: 0.2
        )
        let started = try service.start()
        let sessionID = try XCTUnwrap(started.sessionID)

        let stopped = service.wait(sessionID: sessionID, timeout: 2)

        XCTAssertEqual(stopped.sessionID, sessionID)
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(stopped.endReason, eventStreamMaximumDurationEndReason)

        let eventsPath = try XCTUnwrap(stopped.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"session.ended""#))
        XCTAssertTrue(events.contains(#""kind":"session.ended""#))
        XCTAssertTrue(events.contains(#""endReason":"\#(eventStreamMaximumDurationEndReason)""#))
    }

    func testEventStreamSuppressedEventsUpdateMetadata() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)

        _ = try service.start()
        try service.appendSuppressedEventForTesting([
            "type": "AX.snapshot.suppressed",
            "reason": "test",
        ])
        let status = service.status()

        XCTAssertEqual(status.suppressedEventCount, 1)
        let suppressedPath = try XCTUnwrap(status.suppressedEventsPath)
        let suppressed = try String(contentsOfFile: suppressedPath, encoding: .utf8)
        XCTAssertTrue(suppressed.contains(#""type":"AX.snapshot.suppressed""#))
        XCTAssertTrue(suppressed.contains(#""kind":"AX.snapshot.suppressed""#))
        XCTAssertTrue(suppressed.contains(#""reason":"test""#))
        _ = try service.stop()
    }

    func testEventStreamDebugErrorPayloadUsesOfficialEventNameAndSafeContext() throws {
        let payload = eventStreamDebugErrorPayload(
            subsystem: "accessibility",
            reason: "snapshotUnavailable",
            error: NSError(domain: "OpenComputerUseTests", code: 7),
            context: [
                "path": "private-tmp-recording.png",
                "app": [
                    "name": "Terminal",
                    "pid": 123,
                    "bundleIdentifier": "com.apple.Terminal",
                ],
            ],
            timestamp: "2026-06-26T00:00:00.000Z"
        )

        XCTAssertEqual(payload["type"] as? String, "debug.error")
        XCTAssertEqual(payload["timestamp"] as? String, "2026-06-26T00:00:00.000Z")
        XCTAssertEqual(payload["subsystem"] as? String, "accessibility")
        XCTAssertEqual(payload["reason"] as? String, "snapshotUnavailable")
        XCTAssertEqual(payload["errorType"] as? String, "NSError")
        XCTAssertNil(payload["path"])
        let app = try XCTUnwrap(payload["app"] as? [String: Any])
        XCTAssertEqual(app["name"] as? String, "Terminal")
        XCTAssertEqual(app["pid"] as? Int, 123)
        XCTAssertEqual(app["bundleIdentifier"] as? String, "com.apple.Terminal")
    }

    func testEventStreamDebugErrorsAppendToMainEvents() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)

        _ = try service.start()
        try service.appendDebugErrorForTesting(
            subsystem: "accessibility",
            reason: "snapshotUnavailable",
            error: NSError(domain: "OpenComputerUseTests", code: 7)
        )
        let status = service.status()

        let eventsPath = try XCTUnwrap(status.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"debug.error""#))
        XCTAssertTrue(events.contains(#""reason":"snapshotUnavailable""#))
        XCTAssertTrue(events.contains(#""errorType":"NSError""#))
        XCTAssertEqual(status.eventCount, 4)
        _ = try service.stop()
    }

    func testEventStreamRecordsDebugErrorWhenInputMonitorsAreUnavailable() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: true,
            showsRecordingControls: false,
            recordsRawEvents: false,
            installsCGEventTap: false,
            inputMonitorInstaller: { _, _ in nil }
        )

        let status = try service.start()

        let eventsPath = try XCTUnwrap(status.eventsPath)
        let events = try String(contentsOfFile: eventsPath, encoding: .utf8)
        XCTAssertTrue(events.contains(#""type":"debug.error""#))
        XCTAssertTrue(events.contains(#""subsystem":"inputMonitoring""#))
        XCTAssertTrue(events.contains(#""reason":"inputMonitorsUnavailable""#))
        XCTAssertTrue(events.contains(#""monitorsInstalled":0"#))
        _ = try service.stop()
    }

    func testEventStreamCompactAXDiffUsesOfficialStyleMarkers() throws {
        let diff = try XCTUnwrap(eventStreamCompactAXDiff(
            previous: [
                "0 window \"A\"",
                "1 button \"Save\"",
                "2 text \"Old\"",
            ],
            current: [
                "0 window \"A\"",
                "1 button \"Save\"",
                "2 text \"New\"",
                "3 button \"Done\"",
            ]
        ))

        XCTAssertEqual(diff.lines, [
            "~ 2 text \"Old\" -> 2 text \"New\"",
            "+ 3 button \"Done\"",
        ])
        XCTAssertTrue(diff.renderedText.contains("The following is a diff from the previous accessibility tree"))
        XCTAssertTrue(diff.cumulativeRenderedText.contains("The following is a cumulative diff from the initial accessibility tree"))
    }

    func testEventStreamCompactAXDiffRecordsRemovedLines() throws {
        let diff = try XCTUnwrap(eventStreamCompactAXDiff(
            previous: [
                "0 window \"A\"",
                "1 button \"Save\"",
                "2 text \"Transient\"",
                "3 button \"Done\"",
            ],
            current: [
                "0 window \"A\"",
                "1 button \"Save\"",
                "3 button \"Done\"",
            ]
        ))

        XCTAssertEqual(diff.lines, [
            "- 2 text \"Transient\"",
        ])
    }

    func testEventStreamCompactAXDiffRecordsInsertedLinesWithoutIndexShiftNoise() throws {
        let diff = try XCTUnwrap(eventStreamCompactAXDiff(
            previous: [
                "0 window \"A\"",
                "1 button \"Save\"",
                "2 button \"Done\"",
            ],
            current: [
                "0 window \"A\"",
                "1 button \"New\"",
                "2 button \"Save\"",
                "3 button \"Done\"",
            ]
        ))

        XCTAssertEqual(diff.lines, [
            "+ 1 button \"New\"",
        ])
    }

    func testEventStreamCompactAXDiffPairsChangedAXValuesByElementIdentity() throws {
        let diff = try XCTUnwrap(eventStreamCompactAXDiff(
            previous: [
                "0 standard window Notes",
                "1 search text field (settable, string) Alpha",
            ],
            current: [
                "0 standard window Notes",
                "1 search text field (settable, string) Beta",
            ]
        ))

        XCTAssertEqual(diff.lines, [
            "~ 1 search text field (settable, string) Alpha -> 1 search text field (settable, string) Beta",
        ])
    }

    func testEventStreamCompactAXDiffFallsBackWhenOverBudget() {
        let diff = eventStreamCompactAXDiff(
            previous: ["a", "b", "c"],
            current: ["x", "y", "z"],
            maxDiffLines: 1
        )

        XCTAssertNil(diff)
    }

    func testEventStreamAXContextKeyPrefersBundleIdentifierAndWindowTitle() {
        XCTAssertEqual(
            eventStreamAXContextKey(
                appName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit",
                windowTitle: "Notes"
            ),
            "com.apple.TextEdit\u{1f}Notes"
        )
        XCTAssertEqual(
            eventStreamAXContextKey(
                appName: "TextEdit",
                bundleIdentifier: nil,
                windowTitle: nil
            ),
            "TextEdit\u{1f}"
        )
    }

    func testEventStreamWindowChangedPayloadUsesOfficialEventName() throws {
        let payload = eventStreamWindowChangedPayload(
            reason: "inputContextChanged",
            contextKey: "com.apple.TextEdit\u{1f}Notes",
            context: [
                "app": [
                    "name": "TextEdit",
                    "bundleIdentifier": "com.apple.TextEdit",
                    "pid": 123,
                ],
                "window": [
                    "title": "Notes",
                    "frame": [
                        "x": 10,
                        "y": 20,
                        "width": 300,
                        "height": 200,
                    ],
                ],
            ],
            timestamp: "2026-06-26T00:00:00.000Z"
        )

        XCTAssertEqual(payload["type"] as? String, "window.changed")
        XCTAssertEqual(payload["timestamp"] as? String, "2026-06-26T00:00:00.000Z")
        XCTAssertEqual(payload["reason"] as? String, "inputContextChanged")
        XCTAssertEqual(payload["windowContextKey"] as? String, "com.apple.TextEdit\u{1f}Notes")
        let app = try XCTUnwrap(payload["app"] as? [String: Any])
        XCTAssertEqual(app["bundleIdentifier"] as? String, "com.apple.TextEdit")
        let window = try XCTUnwrap(payload["window"] as? [String: Any])
        XCTAssertEqual(window["title"] as? String, "Notes")
    }

    func testEventStreamSelectionSignatureRequiresSelectedText() {
        XCTAssertNil(eventStreamSelectionSignature(focusedElement: [
            "role": "AXTextArea",
            "title": "Editor",
        ]))

        let signature = eventStreamSelectionSignature(focusedElement: [
            "role": "AXTextArea",
            "subrole": "AXStandardTextArea",
            "title": "Editor",
            "label": "Body",
            "value": "hello world",
            "selectedText": "hello",
            "frame": [
                "x": 10,
                "y": 20,
                "width": 300,
                "height": 40,
            ],
        ])

        XCTAssertEqual(
            signature,
            [
                "AXTextArea",
                "AXStandardTextArea",
                "Editor",
                "Body",
                "hello world",
                "hello",
                "10.000,20.000,300.000,40.000",
            ].joined(separator: "\u{1f}")
        )
        XCTAssertNotEqual(
            signature,
            eventStreamSelectionSignature(focusedElement: [
                "role": "AXTextArea",
                "title": "Editor",
                "selectedText": "world",
            ])
        )
    }

    func testEventStreamSelectionClearedPayloadKeepsOfficialEventName() throws {
        let focusedElement: [String: Any] = [
            "role": "AXTextArea",
            "subrole": "AXStandardTextArea",
            "title": "Editor",
            "label": "Body",
            "value": "hello world",
            "frame": [
                "x": 10,
                "y": 20,
                "width": 300,
                "height": 40,
            ],
        ]
        let signature = try XCTUnwrap(eventStreamSelectionClearedSignature(focusedElement: focusedElement))
        XCTAssertTrue(signature.hasSuffix("<selection-cleared>"))

        let payload = eventStreamSelectionChangedPayload(
            reason: "keyboard.text_input",
            selectedText: "",
            selectionSignature: signature,
            focusedElement: focusedElement,
            selectionCleared: true,
            timestamp: "2026-06-26T00:00:00.000Z"
        )

        XCTAssertEqual(payload["type"] as? String, "selection.changed")
        XCTAssertEqual(payload["timestamp"] as? String, "2026-06-26T00:00:00.000Z")
        XCTAssertEqual(payload["reason"] as? String, "keyboard.text_input")
        XCTAssertEqual(payload["selectedText"] as? String, "")
        XCTAssertEqual(payload["selectionCleared"] as? Bool, true)
        XCTAssertEqual(payload["selectionSignature"] as? String, signature)
        let payloadFocusedElement = try XCTUnwrap(payload["focusedAccessibilityElement"] as? [String: Any])
        XCTAssertEqual(payloadFocusedElement["title"] as? String, "Editor")
    }

    func testEventStreamFocusedElementIsSecureUsesProtectedSignals() {
        XCTAssertTrue(eventStreamFocusedElementIsSecure([
            "role": "AXTextField",
            "protectedContent": true,
        ]))
        XCTAssertTrue(eventStreamFocusedElementIsSecure([
            "role": "AXTextField",
            "subrole": "AXSecureTextField",
        ]))
        XCTAssertTrue(eventStreamFocusedElementIsSecure([
            "role": "AXTextField",
            "roleDescription": "secure text field",
        ]))
        XCTAssertFalse(eventStreamFocusedElementIsSecure([
            "role": "AXTextField",
            "label": "Password hint",
        ]))
    }

    func testEventStreamFocusedElementIsTerminalUsesAppContextAndTextRole() {
        let terminalContext: [String: Any] = [
            "app": [
                "name": "Terminal",
                "bundleIdentifier": "com.apple.Terminal",
            ],
        ]
        XCTAssertTrue(eventStreamFocusedElementIsTerminal([
            "role": "AXTextArea",
            "value": "prompt",
        ], appContext: terminalContext))
        XCTAssertTrue(eventStreamFocusedElementIsTerminal([
            "role": "AXGroup",
            "roleDescription": "terminal screen",
            "value": "prompt",
        ], appContext: terminalContext))
        XCTAssertFalse(eventStreamFocusedElementIsTerminal([
            "role": "AXTextArea",
            "value": "body",
        ], appContext: [
            "app": [
                "name": "TextEdit",
                "bundleIdentifier": "com.apple.TextEdit",
            ],
        ]))
        XCTAssertFalse(eventStreamFocusedElementIsTerminal([
            "role": "AXTextArea",
            "secureInput": true,
            "value": "secret",
        ], appContext: terminalContext))
    }

    func testEventStreamTerminalValueHelpersRedactContent() {
        let focusedElement: [String: Any] = [
            "role": "AXTextArea",
            "title": "Shell",
            "value": "terminal output",
            "selectedText": "output",
            "frame": [
                "x": 1,
                "y": 2,
                "width": 3,
                "height": 4,
            ],
        ]

        XCTAssertEqual(eventStreamTerminalValue(focusedElement), "terminal output")
        XCTAssertEqual(eventStreamStableTextHash("hello"), "a430d84680aabd0b")
        XCTAssertEqual(eventStreamStableTextHash("terminal output"), "235656b19743263e")

        let signature = eventStreamTerminalValueSignature(
            focusedElement: focusedElement,
            valueHash: eventStreamStableTextHash("terminal output")
        )
        XCTAssertTrue(signature.hasSuffix("235656b19743263e"))

        let redacted = eventStreamTerminalRedactedFocusedElement(focusedElement)
        XCTAssertNil(redacted["value"])
        XCTAssertNil(redacted["selectedText"])
        XCTAssertEqual(redacted["valueHash"] as? String, "235656b19743263e")
        XCTAssertEqual(redacted["valueLength"] as? Int, 15)
        XCTAssertEqual(redacted["selectedTextLength"] as? Int, 6)
        XCTAssertEqual(redacted["terminalValueRedacted"] as? Bool, true)
    }

    func testEventStreamMouseEventTypeUsesOfficialContextMenuName() {
        XCTAssertEqual(eventStreamMouseEventType(forButton: "left"), "mouse.click")
        XCTAssertEqual(eventStreamMouseEventType(forButton: "middle"), "mouse.click")
        XCTAssertEqual(eventStreamMouseEventType(forButton: "right"), "mouse.context_menu")
    }

    func testEventStreamMouseButtonMapsDownDragAndUpEvents() {
        XCTAssertEqual(eventStreamMouseButton(forEventType: .leftMouseDown), "left")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .leftMouseDragged), "left")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .leftMouseUp), "left")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .rightMouseDown), "right")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .rightMouseDragged), "right")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .rightMouseUp), "right")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .otherMouseDown), "middle")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .otherMouseDragged), "middle")
        XCTAssertEqual(eventStreamMouseButton(forEventType: .otherMouseUp), "middle")
        XCTAssertNil(eventStreamMouseButton(forEventType: .keyDown))
    }

    func testEventStreamPointerDidDragUsesDistanceThreshold() {
        XCTAssertFalse(eventStreamPointerDidDrag(
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 12, y: 10),
            observedDrag: false
        ))
        XCTAssertTrue(eventStreamPointerDidDrag(
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 13, y: 10),
            observedDrag: false
        ))
        XCTAssertTrue(eventStreamPointerDidDrag(
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 11, y: 10),
            observedDrag: true
        ))
        XCTAssertEqual(eventStreamPointerDistance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4)), 5)
    }

    func testEventStreamKeyboardPayloadKindUsesOfficialEventNames() throws {
        XCTAssertEqual(
            eventStreamKeyboardPayloadKind(characters: "a", keyCode: 0, modifierFlags: []),
            EventStreamKeyboardPayloadKind(type: "keyboard.text_input", text: "a", key: nil)
        )
        XCTAssertEqual(
            eventStreamKeyboardPayloadKind(characters: "\r", keyCode: 36, modifierFlags: []),
            EventStreamKeyboardPayloadKind(type: "keyboard.submit", text: nil, key: "Return")
        )
        XCTAssertEqual(
            eventStreamKeyboardPayloadKind(characters: "s", keyCode: 1, modifierFlags: [.command]),
            EventStreamKeyboardPayloadKind(type: "keyboard.shortcut", text: nil, key: "S")
        )
        XCTAssertNil(eventStreamKeyboardPayloadKind(characters: nil, keyCode: 0, modifierFlags: []))
    }

    func testEventStreamModifierNamesUseStableOrder() {
        XCTAssertEqual(eventStreamModifierNames([.shift, .command, .control, .option]), [
            "command",
            "option",
            "control",
            "shift",
        ])
    }

    func testEventStreamRecordingControlsEnvFlag() {
        XCTAssertTrue(eventStreamRecordingControlsEnabled(environment: [:]))
        XCTAssertFalse(eventStreamRecordingControlsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "0"]))
        XCTAssertFalse(eventStreamRecordingControlsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "false"]))
        XCTAssertTrue(eventStreamRecordingControlsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_CONTROLS": "true"]))
    }

    func testEventStreamRecordingControlsFrameClampsToVisibleFrame() {
        let frame = eventStreamRecordingControlsFrame(
            panelSize: NSSize(width: 520, height: 54),
            visibleFrame: NSRect(x: 0, y: 40, width: 1440, height: 860)
        )

        XCTAssertEqual(frame.origin.x, 460)
        XCTAssertEqual(frame.origin.y, 828)
        XCTAssertEqual(frame.size.width, 520)
        XCTAssertEqual(frame.size.height, 54)
    }

    func testEventStreamRecordingControlsFrameSupportsNarrowAndNegativeScreens() {
        let narrow = eventStreamRecordingControlsFrame(
            panelSize: NSSize(width: 520, height: 54),
            visibleFrame: NSRect(x: -1512, y: 458, width: 480, height: 982)
        )
        XCTAssertEqual(narrow.origin.x, -1512)
        XCTAssertEqual(narrow.origin.y, 1368)

        let short = eventStreamRecordingControlsFrame(
            panelSize: NSSize(width: 520, height: 54),
            visibleFrame: NSRect(x: 0, y: 10, width: 900, height: 40)
        )
        XCTAssertEqual(short.origin.x, 190)
        XCTAssertEqual(short.origin.y, 10)
    }

    @MainActor
    func testEventStreamRecordingControlsButtonsTriggerRuntimeCallbacks() {
        var stopCount = 0
        var cancelCount = 0
        let controls = EventStreamRecordingControls(
            startedAt: Date(),
            onStop: {
                stopCount += 1
            },
            onCancel: {
                cancelCount += 1
            }
        )
        defer {
            controls.close()
        }

        XCTAssertTrue(controls.performControlButtonForTesting(title: "Done"))
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(cancelCount, 0)

        XCTAssertTrue(controls.performControlButtonForTesting(title: "Discard"))
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(cancelCount, 1)
    }

    func testEventStreamScreenshotPolicyEnvFlag() {
        XCTAssertEqual(eventStreamScreenshotPolicy(environment: [:]), .auto)
        XCTAssertEqual(eventStreamScreenshotPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "always"]), .always)
        XCTAssertEqual(eventStreamScreenshotPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "never"]), .never)
        XCTAssertEqual(eventStreamScreenshotPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_SCREENSHOTS": "unknown"]), .auto)
    }

    func testEventStreamMaximumDurationEnvFlag() {
        XCTAssertEqual(eventStreamRecordingMaximumDuration(environment: [:]), eventStreamMaximumRecordingDuration)
        XCTAssertEqual(eventStreamRecordingMaximumDuration(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS": "2.5"]), 2.5)
        XCTAssertEqual(eventStreamRecordingMaximumDuration(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS": "0"]), 0)
        XCTAssertEqual(eventStreamRecordingMaximumDuration(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS": "-1"]), eventStreamMaximumRecordingDuration)
        XCTAssertEqual(eventStreamRecordingMaximumDuration(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_MAX_DURATION_SECONDS": "bogus"]), eventStreamMaximumRecordingDuration)
    }

    func testEventStreamRecordingDurationLimitDescription() {
        XCTAssertEqual(
            eventStreamRecordingDurationLimitDescription(eventStreamMaximumRecordingDuration),
            "up to 30 minutes"
        )
        XCTAssertEqual(eventStreamRecordingDurationLimitDescription(60), "up to 1 minute")
        XCTAssertEqual(eventStreamRecordingDurationLimitDescription(2), "up to 2 seconds")
        XCTAssertEqual(eventStreamRecordingDurationLimitDescription(0), "until stopped")
    }

    func testEventStreamRawEventsEnvFlagDefaultsToEnabled() {
        XCTAssertTrue(eventStreamRawEventsEnabled(environment: [:]))
        XCTAssertFalse(eventStreamRawEventsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "0"]))
        XCTAssertFalse(eventStreamRawEventsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "false"]))
        XCTAssertTrue(eventStreamRawEventsEnabled(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_RAW_EVENTS": "true"]))
    }

    func testEventStreamStartApprovalPolicyEnvFlag() {
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: [:]), .automatic)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "auto"]), .automatic)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "true"]), .interactive)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "approve"]), .approve)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "0"]), .approve)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "deny"]), .deny)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "cancel"]), .cancel)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "mcp"]), .mcpElicitation)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "elicitation"]), .mcpElicitation)
        XCTAssertEqual(eventStreamStartApprovalPolicy(environment: ["OPEN_COMPUTER_USE_EVENT_STREAM_START_APPROVAL": "unknown"]), .automatic)
    }

    func testEventStreamRawEventSummaryCapturesScrollWithoutInventingScrollEventType() throws {
        let summary = eventStreamRawEventSummary(
            eventType: .scrollWheel,
            appKitLocation: CGPoint(x: 10, y: 20),
            screenLocation: CGPoint(x: 10, y: 980),
            modifierFlags: [.shift],
            scrollingDeltaX: 0,
            scrollingDeltaY: -32,
            hasPreciseScrollingDeltas: true,
            phase: [.began, .changed]
        )

        XCTAssertEqual(summary["eventType"] as? String, "scrollWheel")
        XCTAssertEqual(summary["scrollingDeltaY"] as? CGFloat, -32)
        XCTAssertEqual(summary["hasPreciseScrollingDeltas"] as? Bool, true)
        XCTAssertEqual(summary["modifiers"] as? [String], ["shift"])
        XCTAssertEqual(summary["phase"] as? String, "began,changed")
        let location = try XCTUnwrap(summary["location"] as? [String: CGFloat])
        XCTAssertEqual(location["y"], 980)
    }

    func testEventStreamRawEventSummaryRedactsSecureCharacters() {
        let summary = eventStreamRawEventSummary(
            eventType: .keyDown,
            keyCode: 0,
            characters: "secret",
            redactCharacters: true
        )

        XCTAssertNil(summary["characters"])
        XCTAssertEqual(summary["charactersRedacted"] as? Bool, true)
        XCTAssertEqual(summary["characterCount"] as? Int, 6)
    }

    func testEventStreamScreenshotNeededForContextPolicy() {
        XCTAssertTrue(eventStreamScreenshotNeededForContext(
            policy: .always,
            payloadKind: "full",
            treeLineCount: 100,
            hasFocusedSummary: true
        ))
        XCTAssertFalse(eventStreamScreenshotNeededForContext(
            policy: .never,
            payloadKind: "full",
            treeLineCount: 1,
            hasFocusedSummary: false
        ))
        XCTAssertTrue(eventStreamScreenshotNeededForContext(
            policy: .auto,
            payloadKind: "full",
            treeLineCount: 4,
            hasFocusedSummary: true
        ))
        XCTAssertTrue(eventStreamScreenshotNeededForContext(
            policy: .auto,
            payloadKind: "full",
            treeLineCount: 40,
            hasFocusedSummary: false
        ))
        XCTAssertFalse(eventStreamScreenshotNeededForContext(
            policy: .auto,
            payloadKind: "full",
            treeLineCount: 40,
            hasFocusedSummary: true
        ))
    }

    func testEventStreamMCPServerListsRecordAndReplayTools() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let server = EventStreamMCPServer(service: service)

        let initialize = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        XCTAssertTrue(initialize.contains(#""name":"Record & Replay""#))
        let initializeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(initialize.utf8)) as? [String: Any])
        let initializeResult = try XCTUnwrap(initializeObject["result"] as? [String: Any])
        XCTAssertEqual(initializeResult["protocolVersion"] as? String, "2025-11-25")
        XCTAssertNil(initializeResult["instructions"])

        let listTools = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        XCTAssertTrue(listTools.contains(#""event_stream_start""#))
        XCTAssertTrue(listTools.contains(#""event_stream_status""#))
        XCTAssertTrue(listTools.contains(#""event_stream_stop""#))

        let start = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}"#))
        let statusText = try mcpPrimaryText(start)
        XCTAssertTrue(statusText.contains(#""state" : "recording""#) || statusText.contains(#""state":"recording""#))
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(statusText.utf8)) as? [String: Any])
        let eventsPath = try XCTUnwrap(statusObject["eventsPath"] as? String)
        let metadataPath = try XCTUnwrap(statusObject["metadataPath"] as? String)
        let sessionPath = try XCTUnwrap(statusObject["sessionPath"] as? String)
        let sessionDirectoryPath = try XCTUnwrap(statusObject["sessionDirectoryPath"] as? String)
        let sessionID = try XCTUnwrap(statusObject["sessionID"] as? String)
        XCTAssertEqual(statusObject["isRecording"] as? Bool, true)
        XCTAssertEqual(statusObject["maxDurationSeconds"] as? Int, 1800)
        XCTAssertEqual(statusObject["sessionId"] as? String, sessionID)
        XCTAssertEqual(metadataPath, sessionPath)
        XCTAssertTrue(metadataPath.hasSuffix("/session.json"))
        XCTAssertTrue(eventsPath.hasPrefix(sessionDirectoryPath))
        XCTAssertTrue(metadataPath.hasPrefix(sessionDirectoryPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionPath))
        XCTAssertEqual(
            try String(contentsOfFile: metadataPath, encoding: .utf8),
            try String(contentsOfFile: sessionPath, encoding: .utf8)
        )

        let stop = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"event_stream_stop","arguments":{}}}"#))
        let stopText = try mcpPrimaryText(stop)
        let stopObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stopText.utf8)) as? [String: Any])
        XCTAssertEqual(stopObject["isRecording"] as? Bool, false)
        XCTAssertEqual(stopObject["endReason"] as? String, "recording_controls_stopped")
        XCTAssertEqual(stopObject["sessionID"] as? String, sessionID)
        XCTAssertEqual(stopObject["sessionDirectoryPath"] as? String, sessionDirectoryPath)
        XCTAssertEqual(stopObject["metadataPath"] as? String, sessionPath)
        XCTAssertEqual(stopObject["sessionPath"] as? String, sessionPath)
        XCTAssertNotNil(stopObject["endedAt"])
    }

    func testEventStreamMCPSurfaceMatchesOfficialFixture() throws {
        let fixtureURL = repositoryRootURL()
            .appendingPathComponent("docs/references/codex-computer-use-reverse-engineering/fixtures/record-and-replay-event-stream-surface-1.0.857.json")
        let fixture = try jsonObject(contentsOf: fixtureURL)
        let fixtureInitialize = try XCTUnwrap(fixture["initialize"] as? [String: Any])
        let fixtureServerInfo = try XCTUnwrap(fixtureInitialize["serverInfo"] as? [String: Any])
        let fixtureTools = try XCTUnwrap(fixture["tools"] as? [[String: Any]])

        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let server = EventStreamMCPServer(service: service)

        let initialize = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let initializeObject = try jsonObject(text: initialize)
        let initializeResult = try XCTUnwrap(initializeObject["result"] as? [String: Any])
        let localServerInfo = try XCTUnwrap(initializeResult["serverInfo"] as? [String: Any])

        XCTAssertEqual(initializeResult["protocolVersion"] as? String, fixtureInitialize["protocolVersion"] as? String)
        XCTAssertEqual(localServerInfo["name"] as? String, fixtureServerInfo["name"] as? String)
        XCTAssertNil(initializeResult["instructions"])
        XCTAssertEqual(
            try canonicalJSON(initializeResult["capabilities"] as Any),
            try canonicalJSON(fixtureInitialize["capabilities"] as Any)
        )

        let listTools = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#))
        let listToolsObject = try jsonObject(text: listTools)
        let listToolsResult = try XCTUnwrap(listToolsObject["result"] as? [String: Any])
        let localTools = try XCTUnwrap(listToolsResult["tools"] as? [[String: Any]])

        XCTAssertEqual(try canonicalJSON(localTools), try canonicalJSON(fixtureTools))
    }

    func testEventStreamMCPStartApprovalDeniedReturnsToolError() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .deny
        )
        let server = EventStreamMCPServer(service: service)

        let start = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}"#))

        XCTAssertTrue(start.contains(#""isError":true"#))
        XCTAssertTrue(start.contains(eventStreamStartApprovalDeniedMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
    }

    func testEventStreamMCPStartApprovalUsesElicitationAccept() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .mcpElicitation
        )
        let server = EventStreamMCPServer(service: service)

        let initialize = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{"elicitation":{}}}}"#))
        let initializeObject = try jsonObject(text: initialize)
        let initializeResult = try XCTUnwrap(initializeObject["result"] as? [String: Any])
        XCTAssertNil(initializeResult["instructions"])

        var requestedApproval = false
        let start = try XCTUnwrap(server.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}"#,
            startApprovalRequester: {
                requestedApproval = true
                return .approved
            }
        ))

        XCTAssertTrue(requestedApproval)
        let statusText = try mcpPrimaryText(start)
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(statusText.utf8)) as? [String: Any])
        XCTAssertEqual(statusObject["state"] as? String, "recording")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
    }

    func testEventStreamMCPStartApprovalElicitationRequestShape() throws {
        let request = EventStreamMCPServer.startApprovalElicitationRequest(id: "approval-1")
        XCTAssertEqual(request["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(request["id"] as? String, "approval-1")
        XCTAssertEqual(request["method"] as? String, "elicitation/create")

        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["mode"] as? String, "form")
        XCTAssertEqual(
            params["message"] as? String,
            "Open Computer Use wants to start Record & Replay and record your actions."
        )

        let requestedSchema = try XCTUnwrap(params["requestedSchema"] as? [String: Any])
        XCTAssertEqual(requestedSchema["type"] as? String, "object")
        XCTAssertNotNil(requestedSchema["properties"] as? [String: Any])
        XCTAssertEqual((requestedSchema["required"] as? [Any])?.count, 0)
        XCTAssertNil(requestedSchema["additionalProperties"])
    }

    func testEventStreamMCPStartApprovalUsesElicitationDecline() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .mcpElicitation
        )
        let server = EventStreamMCPServer(service: service)

        _ = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{"elicitation":{}}}}"#))
        let start = try XCTUnwrap(server.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}"#,
            startApprovalRequester: { .denied }
        ))

        XCTAssertTrue(start.contains(#""isError":true"#))
        XCTAssertTrue(start.contains(eventStreamStartApprovalDeniedMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
    }

    func testEventStreamMCPStartApprovalCancelsWhenElicitationUnsupported() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(
            rootDirectory: root,
            installsInputMonitors: false,
            showsRecordingControls: false,
            startApprovalPolicy: .mcpElicitation
        )
        let server = EventStreamMCPServer(service: service)

        _ = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}"#))
        var requestedApproval = false
        let start = try XCTUnwrap(server.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"event_stream_start","arguments":{}}}"#,
            startApprovalRequester: {
                requestedApproval = true
                return .approved
            }
        ))

        XCTAssertFalse(requestedApproval)
        XCTAssertTrue(start.contains(#""isError":true"#))
        XCTAssertTrue(start.contains(eventStreamStartApprovalCancelledMessage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
    }

    func testEventStreamMCPStatusAndStopRemainIdleBeforeStart() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let server = EventStreamMCPServer(service: service)

        let status = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"event_stream_status","arguments":{}}}"#))
        let statusText = try mcpPrimaryText(status)
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(statusText.utf8)) as? [String: Any])
        XCTAssertEqual(statusObject["isRecording"] as? Bool, false)
        XCTAssertEqual(statusObject["maxDurationSeconds"] as? Int, 1800)
        XCTAssertNil(statusObject["state"])
        XCTAssertNil(statusObject["active"])
        XCTAssertNil(statusObject["sessionId"])
        XCTAssertNil(statusObject["eventsPath"])
        XCTAssertNil(statusObject["metadataPath"])

        let stop = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"event_stream_stop","arguments":{}}}"#))
        let stopText = try mcpPrimaryText(stop)
        let stopObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stopText.utf8)) as? [String: Any])
        XCTAssertEqual(stopObject["isRecording"] as? Bool, false)
        XCTAssertEqual(stopObject["maxDurationSeconds"] as? Int, 1800)
        XCTAssertNil(stopObject["state"])
        XCTAssertNil(stopObject["active"])
        XCTAssertNil(stopObject["sessionId"])
        XCTAssertNil(stopObject["eventsPath"])
        XCTAssertNil(stopObject["metadataPath"])

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
    }

    func testEventStreamMCPToolsRejectArguments() throws {
        let root = try makeTemporaryDirectory()
        let service = EventStreamService(rootDirectory: root, installsInputMonitors: false, showsRecordingControls: false)
        let server = EventStreamMCPServer(service: service)

        let status = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"event_stream_status","arguments":{"unexpected":true}}}"#))

        XCTAssertTrue(status.contains(#""isError":true"#))
        XCTAssertTrue(status.contains("event_stream_status does not accept arguments"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let startWithNonObjectArguments = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"event_stream_start","arguments":[]}}"#))
        XCTAssertTrue(startWithNonObjectArguments.contains(#""isError":true"#))
        XCTAssertTrue(startWithNonObjectArguments.contains("tools/call arguments must be an object"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let startWithMissingName = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"arguments":{}}}"#))
        XCTAssertTrue(startWithMissingName.contains(#""isError":true"#))
        XCTAssertTrue(startWithMissingName.contains("tools/call params.name must be a non-empty string"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let startWithNonStringName = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":["event_stream_start"],"arguments":{}}}"#))
        XCTAssertTrue(startWithNonStringName.contains(#""isError":true"#))
        XCTAssertTrue(startWithNonStringName.contains("tools/call params.name must be a non-empty string"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let startWithMissingParams = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call"}"#))
        XCTAssertTrue(startWithMissingParams.contains(#""isError":true"#))
        XCTAssertTrue(startWithMissingParams.contains("tools/call params must be an object"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))

        let startWithNonObjectParams = try XCTUnwrap(server.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":[]}"#))
        XCTAssertTrue(startWithNonObjectParams.contains(#""isError":true"#))
        XCTAssertTrue(startWithNonObjectParams.contains("tools/call params must be an object"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("latest-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("active-session.json").path))
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
            )
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
            .eventStream(.mcp),
            .eventStream(.start(json: true)),
            .eventStream(.status(json: true)),
            .eventStream(.stop(json: true)),
            .eventStream(.cancel(json: true)),
            .eventStream(.wait(json: true, sessionID: nil, timeout: 0, notifyCommand: nil)),
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
            .eventStream(.summarize(inputPath: "/tmp/session", includeText: false, requireAction: false)),
            .eventStream(.validate(inputPath: "/tmp/session", strictOCU: false, requiredEventTypes: [], requireSkillDraft: false)),
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
        let response = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.54"},"capabilities":{}}}"#)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains(#""name":"open-computer-use""#))
        XCTAssertTrue(response!.contains(#""tools":{"listChanged":false}"#))
    }

    func testInitializeResponseContainsComputerUseInstructions() throws {
        let server = StdioMCPServer(service: ComputerUseService())
        let response = try XCTUnwrap(
            server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"test","version":"0.1.54"},"capabilities":{}}}"#)
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
        XCTAssertEqual(getAppStateProperties?["show_full_text"]?["type"] as? String, "boolean")
        XCTAssertEqual(getAppStateSchema?["required"] as? [String], ["app"])
        let scrollPages = (tools["scroll"]?.inputSchema["properties"] as? [String: [String: Any]])?["pages"]
        XCTAssertEqual(scrollPages?["type"] as? String, "number")
        XCTAssertEqual(
            scrollPages?["description"] as? String,
            "Number of pages to scroll. Fractional values are supported. Defaults to 1"
        )
    }

    func testDispatcherMissingArgumentsMatchOfficialToolText() {
        let dispatcher = ComputerUseToolDispatcher()
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
        let dispatcher = ComputerUseToolDispatcher()
        let result = dispatcher.callToolAsResult(
            name: "scroll",
            arguments: ["app": "Sublime Text", "element_index": "14", "direction": "sideways", "pages": 1]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.primaryText, "Invalid scroll direction: sideways")
    }

    func testScrollRejectsNonPositivePagesWithOfficialMessage() {
        let dispatcher = ComputerUseToolDispatcher()
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

    func testSnapshotTextLimitDefaultsTo500AndSupportsFullText() {
        let longText = String(repeating: "候", count: snapshotTextDefaultCharacterLimit + 20)

        XCTAssertEqual(
            sanitizeText(longText),
            String(longText.prefix(snapshotTextDefaultCharacterLimit)) + "..."
        )
        XCTAssertEqual(sanitizeText(longText, characterLimit: nil), longText)
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
        let truncatedURL = String(longURL.prefix(snapshotTextDefaultCharacterLimit)) + "..."
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

    func testEventStreamScreenStatePointConvertsFromAppKitGlobalPoint() {
        let point = eventStreamScreenStatePoint(
            fromAppKitGlobalPoint: CGPoint(x: -1311, y: 281),
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

        XCTAssertEqual(point, CGPoint(x: -1311, y: 1159))
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
            frontToBackIndex: 1
        )
        let openPanel = WindowCaptureCandidate(
            windowID: 2,
            layer: 0,
            bounds: CGRect(x: 120, y: 180, width: 880, height: 448),
            title: "Open",
            area: 394_240,
            frontToBackIndex: 0
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
            frontToBackIndex: 1
        )
        let other = WindowCaptureCandidate(
            windowID: 2,
            layer: 0,
            bounds: CGRect(x: 1_200, y: 100, width: 400, height: 300),
            title: "Utility",
            area: 120_000,
            frontToBackIndex: 0
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

    private func makeSnapshot(
        treeLines: [String],
        focusedSummary: String?,
        selectedText: String? = nil,
        screenshotPNGData: Data? = nil
    ) -> AppSnapshot {
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
            screenshotPNGData: screenshotPNGData,
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
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("open-computer-use-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct EventStreamSummaryFixture {
    let sessionDirectory: URL
    let metadataURL: URL
    let eventsURL: URL
}

private func makeEventStreamSummaryFixture(
    state: String = "stopped",
    endReason: String = "recording_controls_stopped",
    includeBlockingDiagnostic: Bool = false,
    includeSessionEnded: Bool = true
) throws -> EventStreamSummaryFixture {
    let root = try makeTemporaryDirectory()
    let eventsURL = root.appendingPathComponent("events.jsonl")
    let metadataURL = root.appendingPathComponent("metadata.json")
    let suppressedURL = root.appendingPathComponent("suppressed.jsonl")
    let sessionURL = root.appendingPathComponent("session.json")

    var events: [[String: Any]] = [
        [
            "type": "session.started",
            "timestamp": "2026-06-26T00:00:00.000Z",
            "sessionId": "summary-fixture",
        ],
        [
            "type": "window.changed",
            "timestamp": "2026-06-26T00:00:01.000Z",
            "sessionId": "summary-fixture",
            "appName": "Fixture",
            "bundleIdentifier": "dev.opencomputeruse.fixture",
            "windowTitle": "Demo",
        ],
        [
            "type": "mouse.click",
            "timestamp": "2026-06-26T00:00:02.000Z",
            "sessionId": "summary-fixture",
            "location": ["x": 10, "y": 20],
            "targetAccessibilityElement": [
                "role": "AXButton",
                "title": "Save",
                "value": "secret-value",
                "selectedText": "selected-secret",
                "actions": ["AXPress"],
            ],
        ],
        [
            "type": "keyboard.text_input",
            "timestamp": "2026-06-26T00:00:03.000Z",
            "sessionId": "summary-fixture",
            "textLength": 6,
            "secureInput": true,
            "focusedAccessibilityElement": [
                "role": "AXTextField",
                "label": "Token",
                "secureInput": true,
                "value": "token-secret",
            ],
        ],
        [
            "type": "selection.changed",
            "timestamp": "2026-06-26T00:00:04.000Z",
            "sessionId": "summary-fixture",
            "selectedText": "selection-event-secret",
            "focusedAccessibilityElement": [
                "role": "AXTextArea",
                "selectedText": "selected-secret",
            ],
        ],
    ]
    if includeBlockingDiagnostic {
        events.append([
            "type": "debug.error",
            "timestamp": "2026-06-26T00:00:04.750Z",
            "sessionId": "summary-fixture",
            "subsystem": "inputMonitoring",
            "reason": "inputMonitorsUnavailable",
            "errorType": "permission",
        ])
    }
    if includeSessionEnded {
        events.append([
            "type": "session.ended",
            "timestamp": "2026-06-26T00:00:05.000Z",
            "sessionId": "summary-fixture",
            "endReason": endReason,
        ])
    }

    let lines = try events.map { event -> String in
        let data = try JSONSerialization.data(withJSONObject: event, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }.joined(separator: "\n")
    try (lines + "\n").write(to: eventsURL, atomically: true, encoding: .utf8)
    try "".write(to: suppressedURL, atomically: true, encoding: .utf8)

    var metadata: [String: Any] = [
        "sessionId": "summary-fixture",
        "state": state,
        "active": state == "recording",
        "endReason": endReason,
        "eventCount": events.count,
        "suppressedEventCount": 0,
        "eventsPath": eventsURL.path,
        "metadataPath": metadataURL.path,
        "sessionPath": sessionURL.path,
        "suppressedEventsPath": suppressedURL.path,
    ]
    if state == "recording" {
        metadata["currentSegmentEventsPath"] = eventsURL.path
        metadata["currentSegmentMetadataPath"] = metadataURL.path
    }
    try metadata.writeJSONObject(to: metadataURL)
    try metadata.writeJSONObject(to: sessionURL)
    return EventStreamSummaryFixture(sessionDirectory: root, metadataURL: metadataURL, eventsURL: eventsURL)
}

private extension Dictionary where Key == String, Value == Any {
    func writeJSONObject(to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: self,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: [.atomic])
    }
}

private func repositoryRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func jsonObject(contentsOf url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func jsonObjects(contentsOf url: URL) throws -> [[String: Any]] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return try text
        .split(separator: "\n")
        .map { line in
            let data = Data(line.utf8)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
}

private func writeEventStreamFixtureEvents(
    _ events: [[String: Any]],
    fixture: EventStreamSummaryFixture
) throws {
    let lines = try events.map { event -> String in
        let data = try JSONSerialization.data(withJSONObject: event, options: [.withoutEscapingSlashes])
        return String(data: data, encoding: .utf8) ?? "{}"
    }.joined(separator: "\n")
    try (lines + "\n").write(to: fixture.eventsURL, atomically: true, encoding: .utf8)

    var metadata = try jsonObject(contentsOf: fixture.metadataURL)
    metadata["eventCount"] = events.count
    try metadata.writeJSONObject(to: fixture.metadataURL)
    try metadata.writeJSONObject(to: fixture.sessionDirectory.appendingPathComponent("session.json"))
}

private func jsonObject(text: String) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func canonicalJSON(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return try XCTUnwrap(String(data: data, encoding: .utf8))
}

private func mcpPrimaryText(_ response: String) throws -> String {
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    let result = try XCTUnwrap(object["result"] as? [String: Any])
    let content = try XCTUnwrap(result["content"] as? [[String: Any]])
    return try XCTUnwrap(content.first?["text"] as? String)
}
