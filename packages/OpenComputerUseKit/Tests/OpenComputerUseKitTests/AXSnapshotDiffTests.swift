import AppKit
import ApplicationServices
import XCTest
@testable import OpenComputerUseKit

final class AXSnapshotDiffTests: XCTestCase {
    private func snapshot(_ nodes: [AXCleanNode], ids: [Int: String] = [:], objects: [Int: AXUIElement] = [:],
                          roles: [Int: String] = [:], synthetic: Set<Int> = [], truncated: Bool = false,
                          focused: Int? = nil, selected: String? = nil) -> AppSnapshot {
        let records = Dictionary(uniqueKeysWithValues: nodes.map { node in
            (node.index, ElementRecord(index: node.index, identifier: ids[node.index], element: objects[node.index],
                localFrame: nil, role: roles[node.index] ?? "AXButton", rawActions: [], prettyActions: [],
                isSyntheticText: synthetic.contains(node.index)))
        })
        return AppSnapshot(app: .init(name: "Test", bundleIdentifier: "test.ax", pid: getpid(), runningApplication: .current),
            windowTitle: "Test Window", windowBounds: nil, targetWindowID: 42, targetWindowLayer: 0,
            screenshotPNGData: nil, mode: .fixture, treeLines: nodes.flatMap(\.renderedLines),
            focusedSummary: focused.map { "\($0) button" }, focusedElement: nil, selectedText: selected,
            elements: records, cleanNodes: nodes, treeTruncated: truncated, focusedNodeIndex: focused)
    }

    private func tree(_ count: Int = 80) -> [AXCleanNode] {
        [AXCleanNode(index: 0, parent: nil, text: "window Test")] + (1...count).map {
            AXCleanNode(index: $0, parent: 0, text: "button Control \($0) ID: control-\($0)", indentation: "\t")
        }
    }
    private func id(_ text: String) -> String { String(text.split(separator: " ")[2]) }

    func testDeltaReconstructsAddsDeletesUpdatesReparentingAndOrders() {
        let before = [AXCleanNode(index: 0, parent: nil, text: "window"),
                      .init(index: 1, parent: 0, text: "group", indentation: "\t"),
                      .init(index: 2, parent: 1, text: "text old", indentation: "\t\t", annotations: ["detail"]),
                      .init(index: 3, parent: 0, text: "button")]
        let after = [AXCleanNode(index: 0, parent: nil, text: "window"),
                     .init(index: 2, parent: 0, text: "text new", indentation: "\t", annotations: ["new detail"]),
                     .init(index: 4, parent: 2, text: "new button", indentation: "\t\t")]
        let delta = AXTreeDelta.between(before, after)
        XCTAssertEqual(delta.applying(to: before), after)
        XCTAssertEqual(Set(delta.removed), [1, 3])
        XCTAssertEqual(delta.added.map(\.index), [4])
        XCTAssertEqual(delta.updated.map(\.index), [2])
    }

    func testReconstructionAcrossDeterministicListTransitions() {
        var before = tree(60)
        for step in 0..<200 {
            var after = before
            if step % 3 == 0 { after.remove(at: 1 + step % (after.count - 1)) }
            if step % 3 == 1 { after.insert(.init(index: 1000 + step, parent: 0, text: "new \(step)", indentation: "\t"), at: 1) }
            if step % 3 == 2 {
                let first = after.remove(at: 1); after.append(first)
                after[1].text = "updated \(step)"; after[1].annotations = ["status \(step)"]
            }
            XCTAssertEqual(AXTreeDelta.between(before, after).applying(to: before), after, "step \(step)")
            before = after
        }
    }

    func testExactObjectsSurviveLocalIndexShiftsAndMoves() {
        let engine = AXSnapshotOutput()
        let a = AXUIElementCreateApplication(100), b = AXUIElementCreateApplication(101)
        let first = engine.reconcile(snapshot([.init(index: 0, parent: nil, text: "a"), .init(index: 1, parent: nil, text: "b")],
            objects: [0: a, 1: b]), scope: "window")
        let next = engine.reconcile(snapshot([.init(index: 5, parent: nil, text: "b"), .init(index: 8, parent: nil, text: "a changed")],
            objects: [5: b, 8: a]), scope: "window")
        XCTAssertEqual(next.cleanNodes.map(\.index), first.cleanNodes.map(\.index).reversed())
        XCTAssertEqual(next.elements.count, 2)
    }

    func testUniqueIdentifierAndMatchedParentCanRebind() {
        let engine = AXSnapshotOutput()
        let nodes = [AXCleanNode(index: 0, parent: nil, text: "window"), .init(index: 1, parent: 0, text: "button")]
        let first = engine.reconcile(snapshot(nodes, ids: [0: "root", 1: "save"]), scope: "window")
        let second = engine.reconcile(snapshot(nodes, ids: [0: "root", 1: "save"]), scope: "window")
        XCTAssertEqual(first.cleanNodes.map(\.index), second.cleanNodes.map(\.index))
    }

    func testDuplicateIdentifiersAndNamesCannotRebind() {
        let engine = AXSnapshotOutput()
        let nodes = [AXCleanNode(index: 0, parent: nil, text: "window"),
                     .init(index: 1, parent: 0, text: "button Save"), .init(index: 2, parent: 0, text: "button Save")]
        let first = engine.reconcile(snapshot(nodes, ids: [0: "root", 1: "duplicate", 2: "duplicate"]), scope: "window")
        let second = engine.reconcile(snapshot(nodes, ids: [0: "root", 1: "duplicate", 2: "duplicate"]), scope: "window")
        XCTAssertEqual(first.cleanNodes[0].index, second.cleanNodes[0].index)
        XCTAssertTrue(Set(first.cleanNodes.dropFirst().map(\.index)).isDisjoint(with: second.cleanNodes.dropFirst().map(\.index)))
        let unnamed = engine.reconcile(snapshot(nodes), scope: "window")
        XCTAssertTrue(Set(second.cleanNodes.map(\.index)).isDisjoint(with: unnamed.cleanNodes.map(\.index)))
    }

    func testRowReuseAndSyntheticContentChangesRetireReferences() {
        let engine = AXSnapshotOutput(), object = AXUIElementCreateApplication(100)
        let first = engine.reconcile(snapshot([.init(index: 0, parent: nil, text: "row A", identityContent: "A")],
            objects: [0: object], roles: [0: "AXRow"]), scope: "window")
        let next = engine.reconcile(snapshot([.init(index: 0, parent: nil, text: "row B", identityContent: "B")],
            objects: [0: object], roles: [0: "AXRow"]), scope: "window")
        XCTAssertNotEqual(first.cleanNodes[0].index, next.cleanNodes[0].index)
        let nodes = [AXCleanNode(index: 0, parent: nil, text: "group"),
                     .init(index: 1, parent: 0, text: "text A", identityContent: "A")]
        let one = engine.reconcile(snapshot(nodes, objects: [0: object, 1: object], synthetic: [1]), scope: "synthetic")
        let same = engine.reconcile(snapshot(nodes, objects: [0: object, 1: object], synthetic: [1]), scope: "synthetic")
        XCTAssertEqual(one.cleanNodes, same.cleanNodes)
        var changed = nodes; changed[1].text = "text B"; changed[1].identityContent = "B"
        let two = engine.reconcile(snapshot(changed, objects: [0: object, 1: object], synthetic: [1]), scope: "synthetic")
        XCTAssertNotEqual(one.cleanNodes[1].index, two.cleanNodes[1].index)
    }

    func testRemovedReferencesNeverReturnAndClearDoesNotRecycle() {
        let engine = AXSnapshotOutput()
        let first = engine.reconcile(snapshot(tree(2), ids: [0: "root", 1: "a", 2: "b"]), scope: "window")
        _ = engine.reconcile(snapshot([tree(2)[0]], ids: [0: "root"]), scope: "window")
        let returning = engine.reconcile(snapshot(tree(2), ids: [0: "root", 1: "a", 2: "b"]), scope: "window")
        XCTAssertNil(returning.elements[first.cleanNodes[1].index])
        engine.clear()
        let reset = engine.reconcile(snapshot(tree(2), ids: [0: "root", 1: "a", 2: "b"]), scope: "window")
        XCTAssertTrue(Set(returning.elements.keys).isDisjoint(with: reset.elements.keys))
    }

    func testScopeIsolationAndConfigChangePreserveObjectButResetOutput() {
        let engine = AXSnapshotOutput(), object = AXUIElementCreateApplication(100)
        let raw = snapshot([.init(index: 0, parent: nil, text: "button")], objects: [0: object])
        let first = engine.reconcile(raw, scope: "window:500", identityScope: "window")
        let next = engine.reconcile(raw, scope: "window:max", identityScope: "window")
        XCTAssertEqual(first.cleanNodes[0].index, next.cleanNodes[0].index)
        let other = engine.reconcile(raw, scope: "other")
        XCTAssertNotEqual(first.cleanNodes[0].index, other.cleanNodes[0].index)
        let client = AXSnapshotOutput()
        let text = engine.render(snapshot(tree()), scope: "window", options: .init())!
        let foreign = client.render(snapshot(tree()), scope: "window", options: .init(baseSnapshotID: id(text)))!
        XCTAssertTrue(foreign.contains("mode=full")); XCTAssertTrue(foreign.contains("baseline unavailable"))
    }

    func testHiddenCapturesAndNoneDoNotAdvancePublishedBaseline() {
        let engine = AXSnapshotOutput(); var nodes = tree()
        let first = engine.render(snapshot(nodes), scope: "window", options: .init())!
        nodes[3].text += " Value: intermediate"
        XCTAssertNil(engine.render(snapshot(nodes), scope: "window", options: .init(mode: AXSnapshotMode.none)))
        nodes[5].text += " Value: final"
        let next = engine.render(snapshot(nodes), scope: "window", options: .init())!
        XCTAssertTrue(next.contains("base_snapshot_id=\(id(first))"))
        XCTAssertTrue(next.contains("intermediate")); XCTAssertTrue(next.contains("final"))
        XCTAssertTrue(next.contains("Context: 0 window Test"))
    }

    func testExplicitBaselineCanSkipUnemittedResults() {
        let engine = AXSnapshotOutput(); var nodes = tree()
        let first = engine.render(snapshot(nodes), scope: "window", options: .init(mode: .full))!
        nodes[1].text += " Value: one"
        _ = engine.render(snapshot(nodes), scope: "window", options: .init())
        nodes[2].text += " Value: two"
        let text = engine.render(snapshot(nodes), scope: "window", options: .init(baseSnapshotID: id(first)))!
        XCTAssertTrue(text.contains("Value: one")); XCTAssertTrue(text.contains("Value: two"))
    }

    func testNoChangeFocusSelectionAndObservationTruncation() {
        let engine = AXSnapshotOutput(); let nodes = tree()
        _ = engine.render(snapshot(nodes), scope: "window", options: .init())
        let unchanged = engine.render(snapshot(nodes), scope: "window", options: .init())!
        XCTAssertTrue(unchanged.contains("AX unchanged"))
        let focus = engine.render(snapshot(nodes, focused: 3), scope: "window", options: .init())!
        XCTAssertTrue(focus.contains("focused UI element is 3")); XCTAssertFalse(focus.contains("AX unchanged"))
        let selected = engine.render(snapshot(nodes, selected: "hello"), scope: "window", options: .init())!
        XCTAssertTrue(selected.contains("Selected text: [hello]"))
        let refocusedSelection = engine.render(snapshot(nodes, focused: 4, selected: "hello"), scope: "window", options: .init())!
        XCTAssertTrue(refocusedSelection.contains("focused UI element is 4")); XCTAssertFalse(refocusedSelection.contains("AX unchanged"))
        let lost = engine.render(snapshot(nodes), scope: "window", options: .init())!
        XCTAssertTrue(lost.contains("Selected text: none observed"))
        let truncated = engine.render(snapshot(nodes, truncated: true), scope: "window", options: .init())!
        XCTAssertTrue(truncated.contains("mode=full")); XCTAssertTrue(truncated.contains("observation truncated"))
        let completeAgain = engine.render(snapshot(nodes), scope: "window", options: .init())!
        XCTAssertTrue(completeAgain.contains("mode=full")); XCTAssertTrue(completeAgain.contains("baseline observation truncated"))
    }

    func testHistoryEvictionAndBroadChangesRecoverWithFull() {
        let engine = AXSnapshotOutput(); let nodes = tree()
        let first = engine.render(snapshot(nodes), scope: "window", options: .init())!
        for _ in 0..<AXSnapshotOutput.historyLimit { _ = engine.render(snapshot(nodes), scope: "window", options: .init()) }
        let expired = engine.render(snapshot(nodes), scope: "window", options: .init(baseSnapshotID: id(first)))!
        XCTAssertTrue(expired.contains("baseline unavailable"))
        var changed = nodes
        for index in changed.indices { changed[index].text += " a broad change" }
        let full = engine.render(snapshot(changed), scope: "window", options: .init())!
        XCTAssertTrue(full.contains("mode=full (delta >= 80%"))
    }

    func testInvalidOptionsFailBeforeAnyActionOrDiscovery() {
        let dispatcher = ComputerUseToolDispatcher()
        for value: Any in ["patch", 1, false] {
            XCTAssertThrowsError(try dispatcher.callTool(name: "click", arguments: ["snapshot_mode": value]))
        }
        XCTAssertThrowsError(try dispatcher.callTool(name: "get_app_state", arguments: ["base_snapshot_id": 4]))
        let definition = ToolDefinitions.all.first { $0.name == "get_app_state" }!
        let properties = definition.inputSchema["properties"] as! [String: Any]
        XCTAssertNotNil(properties["snapshot_mode"]); XCTAssertNotNil(properties["base_snapshot_id"])
    }
    func testLocalChangeTokenReplay() throws {
        var scenarios: [[String: Any]] = []
        for name in ["form-values", "list-structure", "unchanged"] {
            let fullOutput = AXSnapshotOutput(namespace: "replay"), autoOutput = AXSnapshotOutput(namespace: "replay")
            var nodes = tree(80), observations: [[String: String]] = []
            for step in 0..<21 {
                if step > 0 && name == "form-values" { nodes[1 + step % 80].text = "text field Control \(step) Value: value-\(step)" }
                if step > 0 && name == "list-structure" {
                    nodes.remove(at: 1); nodes.append(.init(index: 100 + step, parent: 0, text: "row New item \(step)", indentation: "\t"))
                }
                let raw = snapshot(nodes)
                let full = fullOutput.render(raw, scope: name, options: .init(mode: .full))!
                let auto = autoOutput.render(raw, scope: name, options: .init(mode: .auto))!
                observations.append(["full": full, "auto": auto])
            }
            let fullBytes = observations.reduce(0) { $0 + $1["full"]!.utf8.count }
            let autoBytes = observations.reduce(0) { $0 + $1["auto"]!.utf8.count }
            XCTAssertLessThan(autoBytes, fullBytes / 2, "\(name): local change replay should halve bytes")
            scenarios.append(["name": name, "observations": observations])
        }
        if let path = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_AX_REPLAY_OUTPUT"] {
            let data = try JSONSerialization.data(withJSONObject: ["source": "deterministic cleaned projection, not real-app or model evaluation", "scenarios": scenarios], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    func testNotebookRecognizesSnapshotEnvelopeAndKeepsFullOutput() throws {
        let command = try VirtualDisplayNotebookKernel.boundCommand(source: "{\"tool\":\"get_app_state\",\"args\":{\"snapshot_mode\":\"none\"}}", sessionID: "session", app: "Test")
        XCTAssertEqual(command.arguments["snapshot_mode"] as? String, "full")
        let text = "AX snapshot notebook:s1 mode=full\nApp=test\n0 window"
        let presentation = VirtualDisplayNotebookOutput(.text(text))
        XCTAssertEqual(presentation.uiTree, text)
        XCTAssertTrue(presentation.json.contains("ui_tree_available"))
    }

}
