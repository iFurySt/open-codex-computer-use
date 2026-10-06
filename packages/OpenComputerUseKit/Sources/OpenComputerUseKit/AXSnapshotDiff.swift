import AppKit
import ApplicationServices
import Foundation

/// The semantic projection produced by cleaning, before any text serialization.
/// References are initially local to acquisition and reconciled before publication.
struct AXCleanNode: Equatable {
    var index: Int
    var parent: Int?
    var text: String
    var indentation: String = ""
    var identityContent: String? = nil
    var annotations: [String] = []

    var renderedLine: String { "\(indentation)\(index)" + (text.isEmpty ? "" : " \(text)") }
    var renderedLines: [String] { [renderedLine] + annotations }
}

public enum AXSnapshotMode: String {
    case auto, full, none
}

struct AXOutputOptions {
    var mode: AXSnapshotMode?
    var baseSnapshotID: String?
}

/// Exact operations on the cleaned projection. Order replacements are only for
/// affected sibling lists; no quadratic minimum tree edit distance is needed.
struct AXTreeDelta {
    var added: [AXCleanNode]
    var updated: [AXCleanNode]
    var removed: [Int]
    var orders: [Int: [Int]] // -1 is the forest root, never an element reference.

    static func childOrders(_ nodes: [AXCleanNode]) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        for node in nodes { result[node.parent ?? -1, default: []].append(node.index) }
        return result
    }

    static func between(_ before: [AXCleanNode], _ after: [AXCleanNode]) -> AXTreeDelta {
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.index, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.map { ($0.index, $0) })
        let oldOrders = childOrders(before), newOrders = childOrders(after)
        let keys = Set(oldOrders.keys).union(newOrders.keys)
        return AXTreeDelta(
            added: after.filter { old[$0.index] == nil },
            updated: after.filter { old[$0.index] != nil && old[$0.index] != $0 },
            removed: before.filter { new[$0.index] == nil }.map(\.index),
            orders: Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                oldOrders[key, default: []] == newOrders[key, default: []] ? nil : (key, newOrders[key, default: []])
            })
        )
    }

    func applying(to before: [AXCleanNode]) -> [AXCleanNode] {
        var nodes = Dictionary(uniqueKeysWithValues: before.map { ($0.index, $0) })
        var childOrders = Self.childOrders(before)
        for index in removed { nodes.removeValue(forKey: index) }
        for node in added + updated { nodes[node.index] = node }
        childOrders.merge(orders) { _, new in new }
        var result: [AXCleanNode] = []
        func walk(_ parent: Int) {
            for index in childOrders[parent, default: []] {
                guard let node = nodes[index] else { continue }
                result.append(node)
                walk(index)
            }
        }
        walk(-1)
        return result
    }

    func rendered(before: [AXCleanNode], after: [AXCleanNode]) -> [String] {
        let old = Dictionary(uniqueKeysWithValues: before.map { ($0.index, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.map { ($0.index, $0) })
        var lines: [String] = []
        let changed = Set((added + updated).map(\.index))
        var contexts = Set<Int>()
        for node in added + updated {
            if let parent = node.parent, !changed.contains(parent) { contexts.insert(parent) }
        }
        for index in removed {
            if let parent = old[index]?.parent, new[parent] != nil, !changed.contains(parent) { contexts.insert(parent) }
        }
        for parent in orders.keys where parent >= 0 && !changed.contains(parent) { contexts.insert(parent) }
        for parent in contexts.sorted() {
            if let node = new[parent] { lines.append("Context: \(node.index) \(node.text)") }
        }
        for (marker, nodes) in [("+", added), ("~", updated)] {
            for node in nodes {
                lines.append("\(marker) \(node.index) \(node.text) [parent=\(node.parent.map(String.init) ?? "root")]")
                lines.append(contentsOf: node.annotations.map { "\(marker) \($0)" })
            }
        }
        if !removed.isEmpty { lines.append("- Observed refs: \(removed.map(String.init).joined(separator: ",")) (no longer in this observation)") }
        for parent in orders.keys.sorted() {
            lines.append("Order \(parent == -1 ? "root" : String(parent)): \(orders[parent]!.map(String.init).joined(separator: ","))")
        }
        return lines
    }
}

private struct AXIdentityState {
    let cleanNodes: [AXCleanNode]
    let elements: [Int: ElementRecord]
}

private struct AXPublishedState {
    let id: String
    let scope: String
    let nodes: [AXCleanNode]
    let header: [String]
    let focus: String
    let truncated: Bool
}

/// One instance per native client/dispatcher. Internal captures never publish a
/// baseline. History stores only the projection, without PNGs or live AX objects.
final class AXSnapshotOutput {
    static let historyLimit = 16
    static let fullFallbackRatio = 0.8
    private var nextReference = 0
    private var nextSnapshot = 0
    private let namespace: String

    init(namespace: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))) {
        self.namespace = namespace
    }
    private var identities: [String: AXIdentityState] = [:]
    private var identityOrder: [String] = []
    private var history: [AXPublishedState] = []
    private var latestByScope: [String: String] = [:]

    func clear() {
        identities.removeAll(); identityOrder.removeAll()
        history.removeAll(); latestByScope.removeAll()
        // Never recycle references or snapshot IDs when a client clears state.
    }

    func reconcile(_ snapshot: AppSnapshot, scope: String, identityScope: String? = nil) -> AppSnapshot {
        let identityScope = identityScope ?? scope
        let previous = identities[identityScope]
        let oldNodes = previous?.cleanNodes ?? []
        var used = Set<Int>(), mapping: [Int: Int] = [:]
        var nodes: [AXCleanNode] = [], records: [Int: ElementRecord] = [:]
        for original in snapshot.cleanNodes {
            let record = snapshot.elements[original.index]
            let parent = original.parent.flatMap { mapping[$0] }
            let candidates = oldNodes.filter { node in
                guard !used.contains(node.index), node.identityContent == original.identityContent,
                      let old = previous?.elements[node.index], let record,
                      old.role == record.role, old.isSyntheticText == record.isSyntheticText else { return false }
                if record.isSyntheticText { return node.parent == parent && old.element != nil && record.element != nil && CFEqual(old.element!, record.element!) }
                if let a = old.element, let b = record.element, CFEqual(a, b) { return true }
                guard let identifier = record.identifier, !identifier.isEmpty,
                      old.identifier == identifier, node.parent == parent else { return false }
                // Identifier fallback must be unique on BOTH sides in this parent.
                guard oldNodes.filter({ candidate in
                    candidate.parent == parent && previous?.elements[candidate.index]?.identifier == identifier
                        && previous?.elements[candidate.index]?.role == record.role
                }).count == 1 else { return false }
                return snapshot.cleanNodes.filter { candidate in
                    candidate.parent == original.parent && snapshot.elements[candidate.index]?.identifier == identifier
                        && snapshot.elements[candidate.index]?.role == record.role
                }.count == 1
            }
            let exact = candidates.filter { candidate in
                guard let old = previous?.elements[candidate.index]?.element, let current = record?.element else { return false }
                return CFEqual(old, current)
            }
            let match = exact.count == 1 ? exact.first : (candidates.count == 1 ? candidates.first : nil)
            let index: Int
            if let match { index = match.index; used.insert(index) }
            else { index = nextReference; nextReference += 1 }
            mapping[original.index] = index
            var node = original; node.index = index; node.parent = parent
            nodes.append(node)
            if let record {
                records[index] = ElementRecord(index: index, identifier: record.identifier, element: record.element,
                    localFrame: record.localFrame, role: record.role, rawActions: record.rawActions,
                    prettyActions: record.prettyActions, isSyntheticText: record.isSyntheticText)
            }
        }
        let focusedIndex = snapshot.focusedNodeIndex.flatMap { mapping[$0] }
        let focusedSummary = focusedIndex.flatMap { id in nodes.first { $0.index == id }.map { "\(id) \($0.text)" } }
        let result = AppSnapshot(app: snapshot.app, windowTitle: snapshot.windowTitle, windowBounds: snapshot.windowBounds,
            targetWindowID: snapshot.targetWindowID, targetWindowLayer: snapshot.targetWindowLayer,
            screenshotPNGData: snapshot.screenshotPNGData, mode: snapshot.mode,
            treeLines: nodes.isEmpty ? snapshot.treeLines : nodes.flatMap(\.renderedLines),
            focusedSummary: focusedSummary ?? snapshot.focusedSummary, focusedElement: snapshot.focusedElement,
            selectedText: snapshot.selectedText, elements: records, axScope: scope, cleanNodes: nodes,
            treeTruncated: snapshot.treeTruncated, focusedNodeIndex: focusedIndex)
        // Bound retained live objects independently of published history.
        identities[identityScope] = .init(cleanNodes: result.cleanNodes, elements: result.elements)
        identityOrder.removeAll { $0 == identityScope }; identityOrder.append(identityScope)
        if identityOrder.count > Self.historyLimit { identities.removeValue(forKey: identityOrder.removeFirst()) }
        return result
    }

    func render(_ snapshot: AppSnapshot, scope: String, options: AXOutputOptions) -> String? {
        let mode = options.mode ?? AXSnapshotMode(rawValue: ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_AX_SNAPSHOT_MODE"] ?? "auto") ?? .auto
        guard mode != .none else { return nil }
        nextSnapshot += 1
        let id = "\(namespace):s\(nextSnapshot)"
        let header = ["App=\(snapshot.app.bundleIdentifier ?? snapshot.app.name) (pid \(snapshot.app.pid))",
                      "Window: \(quoted(displayWindowTitle(snapshot.windowTitle, appName: snapshot.app.name))), App: \(snapshot.app.name)."]
        let focused = snapshot.focusedSummary.map { "The focused UI element is \($0)." } ?? "Focus: none observed."
        let selection = snapshot.selectedText.flatMap { $0.isEmpty ? nil : "Selected text: [\($0)]" } ?? "Selected text: none observed."
        let focus = focused + "\n" + selection
        let current = AXPublishedState(id: id, scope: scope, nodes: snapshot.cleanNodes, header: header, focus: focus, truncated: snapshot.treeTruncated)
        let baseID = options.baseSnapshotID ?? latestByScope[scope]
        let base = history.first { $0.id == baseID && $0.scope == scope }
        var reason = mode == .full ? "requested" : (base == nil ? "baseline unavailable" : "")
        if base?.truncated == true { reason = "baseline observation truncated" }
        if snapshot.treeTruncated { reason = "observation truncated" }
        if snapshot.cleanNodes.isEmpty { reason = "structured tree unavailable" }
        let fullState = snapshot.renderedText + (snapshot.selectedText?.isEmpty == false && snapshot.focusedSummary != nil ? "\n" + focused : "")
        var full = "AX snapshot \(id) mode=full" + (reason.isEmpty ? "" : " (\(reason))") + "\n" + fullState
        if snapshot.treeTruncated { full += "\nAX observation truncated by node/depth budget; missing refs are not evidence of deletion." }
        var text = full
        if mode == .auto, reason.isEmpty, let base {
            let delta = AXTreeDelta.between(base.nodes, current.nodes)
            var lines = delta.rendered(before: base.nodes, after: current.nodes)
            if base.header != current.header { lines.insert(contentsOf: current.header, at: 0) }
            if lines.isEmpty && base.focus == focus { lines.append("AX unchanged") }
            lines.append(focus)
            let incremental = "AX snapshot \(id) mode=diff base_snapshot_id=\(base.id)\n" + lines.joined(separator: "\n")
            text = Double(incremental.utf8.count) < Double(full.utf8.count) * Self.fullFallbackRatio
                ? incremental : "AX snapshot \(id) mode=full (delta >= 80% of full)\n" + fullState
        }
        history.append(current); latestByScope[scope] = id
        if history.count > Self.historyLimit {
            let evicted = history.removeFirst()
            if latestByScope[evicted.scope] == evicted.id { latestByScope.removeValue(forKey: evicted.scope) }
        }
        return text
    }
}
