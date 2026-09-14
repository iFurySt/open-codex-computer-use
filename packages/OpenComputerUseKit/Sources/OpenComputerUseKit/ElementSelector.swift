import Foundation

/// A stable, snapshot-independent way to name an element target.
///
/// `element_index` only identifies an element inside the snapshot it was rendered
/// from: every action re-renders the tree and the indices move, which forces the
/// read -> act -> read loop this type removes. A selector is resolved against the
/// tree that exists at action time instead, so an agent can drive a form field by
/// name without a fresh `get_app_state` in between.
///
/// Accepted forms (case-insensitive):
///
/// ```text
/// button[name=检查变更]
/// combobox[name=类型]
/// [name=返回]
/// [role=textbox][name=用途]
/// [role=textbox, name=用途]
/// 用途                       (name only)
/// ```
struct ElementSelector: Equatable {
    /// `nil` matches every role.
    let role: String?
    let name: String
    /// The selector as the caller wrote it, used in diagnostics.
    let raw: String

    static func parse(_ raw: String) throws -> ElementSelector {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ElementSelectorParseError.malformed("selector must not be empty")
        }

        var role: String?
        var name: String?

        if !trimmed.contains("[") {
            if let value = attributeValue(trimmed, key: "name") {
                name = value
            } else if attributeValue(trimmed, key: "role") != nil {
                throw ElementSelectorParseError.malformed(
                    "selector \(quoted(raw)) sets a role but no name; use role[name=...] instead"
                )
            } else {
                name = unquoted(trimmed)
            }
        } else {
            var remaining = Substring(trimmed)

            while let open = remaining.firstIndex(of: "[") {
                let prefix = remaining[remaining.startIndex..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    role = role ?? prefix
                }

                guard let close = remaining[open...].firstIndex(of: "]") else {
                    throw ElementSelectorParseError.malformed("selector \(quoted(raw)) has an unterminated [ ... ] group")
                }

                let inner = remaining[remaining.index(after: open)..<close]
                try consumeAttributes(String(inner), raw: raw, role: &role, name: &name)
                remaining = remaining[remaining.index(after: close)...]
            }

            let trailing = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trailing.isEmpty else {
                throw ElementSelectorParseError.malformed(
                    "selector \(quoted(raw)) has trailing text \(quoted(trailing)) outside a [ ... ] group"
                )
            }
        }

        guard let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !resolvedName.isEmpty else {
            throw ElementSelectorParseError.malformed(
                "selector \(quoted(raw)) needs a name; write role[name=...], [name=...] or the name itself"
            )
        }

        let resolvedRole = role?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ElementSelector(
            role: (resolvedRole?.isEmpty ?? true) ? nil : resolvedRole,
            name: resolvedName,
            raw: trimmed
        )
    }

    private static func consumeAttributes(
        _ inner: String,
        raw: String,
        role: inout String?,
        name: inout String?
    ) throws {
        // `[role=textbox name=用途]` is accepted as well as the comma form.
        let normalized = inner
            .replacingOccurrences(of: " name=", with: ",name=", options: .caseInsensitive)
            .replacingOccurrences(of: " role=", with: ",role=", options: .caseInsensitive)

        for chunk in normalized.split(separator: ",", omittingEmptySubsequences: true) {
            let piece = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else {
                continue
            }

            if let value = attributeValue(piece, key: "role") {
                role = role ?? value
                continue
            }

            if let value = attributeValue(piece, key: "name") {
                name = value
                continue
            }

            if piece.contains("=") {
                throw ElementSelectorParseError.malformed(
                    "selector \(quoted(raw)) has an unsupported attribute \(quoted(piece)); only role= and name= are supported"
                )
            }

            if name == nil {
                name = unquoted(piece)
            } else {
                throw ElementSelectorParseError.malformed(
                    "selector \(quoted(raw)) sets more than one name: \(quoted(name ?? "")) and \(quoted(piece))"
                )
            }
        }
    }

    private static func attributeValue(_ chunk: String, key: String) -> String? {
        let lowercased = chunk.lowercased()
        guard lowercased.hasPrefix(key + "=") else {
            return nil
        }

        return unquoted(String(chunk.dropFirst(key.count + 1)))
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return trimmed
        }

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func quoted(_ value: String) -> String {
        "\"\(value)\""
    }
}

enum ElementSelectorParseError: Error, Equatable, LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let message):
            return message
        }
    }
}

/// The element facts a selector is resolved against.
struct ElementSelectorCandidate: Equatable {
    let index: Int
    let role: String?
    /// The role text exactly as the snapshot rendered it, so an agent can copy a
    /// localized label such as `列表框` and still match.
    let roleText: String?
    /// Every stable name the element exposes: title, description, value,
    /// identifier and placeholder.
    let names: [String]
    let parentIndex: Int?
}

extension ElementSelectorCandidate {
    init(record: ElementRecord) {
        self.init(
            index: record.index,
            role: record.role,
            roleText: record.roleText,
            names: [record.title, record.label, record.value, record.identifier, record.placeholder]
                .compactMap { $0 }
                .filter { !$0.isEmpty },
            parentIndex: record.parentIndex
        )
    }
}

enum ElementSelectorResolution: Equatable {
    case matched(Int)
    /// A message for the caller; it lists the closest elements instead of
    /// guessing.
    case notFound(String)
    /// A message for the caller; it lists every match instead of picking one.
    case ambiguous(String)
}

/// Role families so an agent can write `textbox` / `combobox` / `button`
/// instead of the exact AX role the platform reports.
private let selectorRoleFamilies: [String: Set<String>] = [
    "button": ["AXButton"],
    "popupbutton": ["AXPopUpButton"],
    "menubutton": ["AXMenuButton"],
    "combobox": ["AXComboBox"],
    "textfield": ["AXTextField"],
    "textbox": ["AXTextField", "AXTextArea"],
    "edit": ["AXTextField", "AXTextArea"],
    "input": ["AXTextField", "AXTextArea"],
    "textarea": ["AXTextArea"],
    "searchfield": ["AXSearchField"],
    "checkbox": ["AXCheckBox"],
    "radio": ["AXRadioButton"],
    "radiobutton": ["AXRadioButton"],
    "switch": ["AXCheckBox", "AXRadioButton"],
    "link": ["AXLink"],
    "listbox": ["AXListBox"],
    "list": ["AXList", "AXListBox"],
    "menu": ["AXMenu"],
    "menuitem": ["AXMenuItem"],
    "text": ["AXStaticText"],
    "statictext": ["AXStaticText"],
    "label": ["AXStaticText"],
    "slider": ["AXSlider"],
    "table": ["AXTable"],
    "outline": ["AXOutline"],
    "row": ["AXRow", "AXOutlineRow"],
    "cell": ["AXCell"],
    "image": ["AXImage"],
    "icon": ["AXImage"],
    "tab": ["AXRadioButton", "AXTabGroup"],
    "radiogroup": ["AXRadioGroup"],
    "group": ["AXGroup"],
    "container": ["AXGroup", "AXUnknown"],
    "webarea": ["AXWebArea"],
    "webcontent": ["AXWebArea"],
    "html": ["AXWebArea"],
    "scrollarea": ["AXScrollArea"],
    "window": ["AXWindow"],
    "sheet": ["AXSheet"],
    "popover": ["AXPopover"],
    "dialog": ["AXDialog", "AXSheet"],
    "toolbar": ["AXToolbar"],
]

/// Reduces a rendered name to the text an agent would copy: the snapshot shows a
/// link as `[返回](https://…)`, and `link[name=返回]` must still match.
func normalizedSelectorName(_ value: String) -> String {
    var text = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
        let afterClose = text.index(after: close)
        if afterClose < text.endIndex, text[afterClose] == "(" {
            text = String(text[text.index(after: text.startIndex)..<close])
        }
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func normalizedSelectorRole(_ value: String) -> String {
    value.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
}

func selectorRoleMatches(requested: String, role: String?, roleText: String?) -> Bool {
    let wanted = normalizedSelectorRole(requested)
    guard !wanted.isEmpty else {
        return true
    }

    if let role {
        let normalizedRole = normalizedSelectorRole(role)
        let bareRole = normalizedRole.hasPrefix("ax") ? String(normalizedRole.dropFirst(2)) : normalizedRole
        if wanted == normalizedRole || wanted == bareRole {
            return true
        }

        if selectorRoleFamilies[wanted]?.contains(role) == true {
            return true
        }
    }

    if let roleText, !roleText.isEmpty, normalizedSelectorRole(roleText) == wanted {
        return true
    }

    return false
}

/// Resolves a selector against the candidates of one tree render.
///
/// Exact name matches win over prefix matches, nested Chromium duplicates count
/// as one target, and anything else (no match, several matches) is reported
/// instead of guessed.
func resolveElementSelector(
    _ selector: ElementSelector,
    candidates: [ElementSelectorCandidate]
) -> ElementSelectorResolution {
    let ordered = candidates.sorted { $0.index < $1.index }

    let roleScoped: [ElementSelectorCandidate]
    if let role = selector.role {
        roleScoped = ordered.filter { selectorRoleMatches(requested: role, role: $0.role, roleText: $0.roleText) }
    } else {
        roleScoped = ordered
    }

    let query = normalizedSelectorName(selector.name)
    guard !query.isEmpty else {
        return .notFound(notFoundMessage(selector, roleScoped: roleScoped))
    }

    let exactMatches = roleScoped.filter { $0.matchesName(query, mode: .exact) }
    let usedPrefix = exactMatches.isEmpty
    let matches = usedPrefix ? roleScoped.filter { $0.matchesName(query, mode: .prefix) } : exactMatches
    let resolved = deduplicatingAncestors(matches, in: ordered)

    switch resolved.count {
    case 0:
        return .notFound(notFoundMessage(selector, roleScoped: roleScoped))
    case 1:
        return .matched(resolved[0].index)
    default:
        return .ambiguous(ambiguousMessage(selector, matches: resolved, usedPrefix: usedPrefix))
    }
}

private enum ElementSelectorNameMatch {
    case exact
    case prefix
}

private extension ElementSelectorCandidate {
    func matchesName(_ query: String, mode: ElementSelectorNameMatch) -> Bool {
        names.contains { name in
            let normalized = normalizedSelectorName(name)
            guard !normalized.isEmpty else {
                return false
            }

            switch mode {
            case .exact:
                return normalized == query
            case .prefix:
                return normalized.hasPrefix(query)
            }
        }
    }

    var describedTarget: String {
        let name = names.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let roleName: String
        if let role {
            let normalized = normalizedSelectorRole(role)
            roleName = normalized.hasPrefix("ax") ? String(normalized.dropFirst(2)) : normalized
        } else {
            roleName = roleText.map(normalizedSelectorRole) ?? "element"
        }

        return "\(index) \(roleName.isEmpty ? "element" : roleName) \"\(name)\""
    }
}

/// Chromium reports the same text as a wrapper node and a text leaf; they are one
/// UI target. Keeping the outermost match preserves the frame the click needs.
private func deduplicatingAncestors(
    _ matches: [ElementSelectorCandidate],
    in pool: [ElementSelectorCandidate]
) -> [ElementSelectorCandidate] {
    guard matches.count > 1 else {
        return matches
    }

    var parentsByIndex: [Int: Int?] = [:]
    for candidate in pool {
        parentsByIndex[candidate.index] = candidate.parentIndex
    }

    let matchedIndices = Set(matches.map(\.index))
    return matches.filter { candidate in
        var current = candidate.parentIndex
        var depth = 0

        while let parentIndex = current, depth < 64 {
            if matchedIndices.contains(parentIndex) {
                return false
            }

            current = parentsByIndex[parentIndex] ?? nil
            depth += 1
        }

        return true
    }
}

private func notFoundMessage(_ selector: ElementSelector, roleScoped: [ElementSelectorCandidate]) -> String {
    var message = "selector \"\(selector.raw)\" matched no element."

    if roleScoped.isEmpty {
        if let role = selector.role {
            message += " The current tree exposes no \(role) element."
        }
    } else {
        let listed = roleScoped.prefix(6).map(\.describedTarget).joined(separator: ", ")
        message += " Closest elements: \(listed)."
    }

    return message + " Use a name from the snapshot, or pass element_index."
}

private func ambiguousMessage(
    _ selector: ElementSelector,
    matches: [ElementSelectorCandidate],
    usedPrefix: Bool
) -> String {
    let listed = matches.prefix(8).map(\.describedTarget).joined(separator: ", ")
    let how = usedPrefix ? "by name prefix" : ""
    return "selector \"\(selector.raw)\" matched \(matches.count) elements\(how.isEmpty ? "" : " " + how): \(listed). Make the name more specific, or pass element_index."
}
