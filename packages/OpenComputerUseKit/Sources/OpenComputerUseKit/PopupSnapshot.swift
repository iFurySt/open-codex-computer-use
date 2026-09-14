import ApplicationServices
import Foundation

/// Snapshot support for apps that open a transient overlay (popup / sheet /
/// menu / floating window) while the snapshot is being read.
///
/// Two different mechanisms exist in the wild and both are handled here:
///
/// 1. The overlay lives in its own top-level subtree (native `AXPopover`,
///    `AXSheet`, `AXMenu`, floating/dialog `AXWindow`). The primary window
///    render never touches it, so the subtree is appended after a marker and the
///    snapshot carries both the page and the popup.
/// 2. The overlay hides the content behind it inside the app itself. Chromium
///    web components (for example a Radix Select) mark the rest of the document
///    `aria-hidden` while the listbox is open, so the `AXWebArea` really does
///    contain nothing but the popup and there is no background subtree left to
///    read. The snapshot cannot invent those nodes, so it states the situation
///    instead of silently returning a tree that looks like the page vanished.
enum SnapshotPopupSection {
    /// Separates appended overlay subtrees from the primary window tree. The
    /// line carries no element index, so existing line parsing is unaffected.
    static let marker = "--- popup ---"
    /// Introduces the note that explains an app-hidden background.
    static let noteMarker = "--- popup note ---"
}

/// One top-level subtree owned by the app, described by values only so the
/// selection policy stays testable without a live accessibility server.
struct PopupSubtreeDescriptor: Equatable {
    let role: String?
    let subrole: String?
    let title: String?
    /// The window the snapshot was rendered from.
    let isPrimaryWindow: Bool
}

/// Roles that mean "an overlay is open" when they show up in a rendered tree.
func isOpenPopupRole(_ role: String?) -> Bool {
    guard let role else {
        return false
    }

    return [
        "AXListBox",
        "AXListBoxOption",
        "AXMenu",
        "AXDialog",
        "AXPopover",
        "AXSheet",
        "AXGrid",
    ].contains(role)
}

/// Whether a top-level subtree is a transient overlay rather than a normal app
/// window. Window subroles cover the popup/panel windows AppKit and Chromium
/// create for native menus, open/save panels and detached popovers.
func isTransientPopupSubtree(role: String?, subrole: String?) -> Bool {
    if isOpenPopupRole(role) {
        return true
    }

    guard role == kAXWindowRole as String, let subrole else {
        return false
    }

    return [
        kAXFloatingWindowSubrole as String,
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
    ].contains(subrole)
}

/// Which extra app-owned subtrees a snapshot appends after the primary window.
///
/// The result stays empty while no overlay is open, so an app without a popup
/// renders exactly as before. Two cases select subtrees:
///
/// - the primary window is normal and some other subtree is transient: append
///   the transient overlays (the page stays readable next to the popup);
/// - the primary window *is* the overlay (Chromium focuses its popup window):
///   append every other window, so the content it opened over stays readable.
func transientPopupSubtreeSelection(_ descriptors: [PopupSubtreeDescriptor]) -> [Int] {
    let primaryIsOverlay = descriptors.contains { descriptor in
        descriptor.isPrimaryWindow && isTransientPopupSubtree(role: descriptor.role, subrole: descriptor.subrole)
    }

    return descriptors.indices.filter { index in
        let descriptor = descriptors[index]
        guard !descriptor.isPrimaryWindow else {
            return false
        }

        return primaryIsOverlay || isTransientPopupSubtree(role: descriptor.role, subrole: descriptor.subrole)
    }
}

/// Assembles the snapshot transcript: the primary window tree, then the marker
/// section with the appended overlay subtrees, then the explanatory note.
///
/// With no popup subtree and no note this returns the primary lines unchanged,
/// which is what keeps a popup-free snapshot byte-identical to the old output.
func appendingTransientPopupSection(primary: [String], popup: [String], note: String?) -> [String] {
    var lines = primary

    if !popup.isEmpty {
        lines.append(SnapshotPopupSection.marker)
        lines.append(contentsOf: popup)
    }

    if let note, !note.isEmpty {
        lines.append(contentsOf: note.split(whereSeparator: { $0.isNewline }).map(String.init))
    }

    return lines
}

/// The note for mechanism 2 above: a web area whose entire exposed content is a
/// single open popup, with keyboard focus inside that popup.
///
/// This is the shape Chromium reports when a page component hides the document
/// behind its overlay (observed with a Radix Select: `HTML 内容` containing only
/// `列表框` plus its option texts). Requiring focus inside the popup keeps a
/// page that legitimately consists of one listbox from being reported as a
/// collapse.
func collapsedWebAreaPopupNote(records: [Int: ElementRecord], focusedIndex: Int?) -> String? {
    guard !records.isEmpty else {
        return nil
    }

    var childrenByParent: [Int: [ElementRecord]] = [:]
    for record in records.values {
        guard let parentIndex = record.parentIndex else {
            continue
        }

        childrenByParent[parentIndex, default: []].append(record)
    }

    for record in records.values.sorted(by: { $0.index < $1.index }) where record.role == "AXWebArea" {
        guard let children = childrenByParent[record.index], children.count == 1, let popup = children.first, isOpenPopupRole(popup.role) else {
            continue
        }

        guard let focusedIndex, isDescendantIndex(focusedIndex, of: popup.index, in: records) else {
            continue
        }

        return [
            SnapshotPopupSection.noteMarker,
            "The app is exposing the open popup only: the content behind it is hidden from the accessibility tree while the popup is open, so its element_index values are temporarily unavailable.",
            "Choose an option in the popup (click and set_value accept a selector, for example selector: \"text[name=草稿]\"), or press Escape; the hidden content comes back once the popup closes. Prefer selector over re-running get_app_state.",
        ].joined(separator: "\n")
    }

    return nil
}

/// Walks the rendered parent chain. Used to recognize that two matches are the
/// same UI target and to check whether focus is inside a popup.
func isDescendantIndex(_ index: Int, of ancestor: Int, in records: [Int: ElementRecord], maxDepth: Int = 64) -> Bool {
    var current = records[index]?.parentIndex
    var depth = 0

    while let parentIndex = current, depth < maxDepth {
        if parentIndex == ancestor {
            return true
        }

        current = records[parentIndex]?.parentIndex
        depth += 1
    }

    return false
}
