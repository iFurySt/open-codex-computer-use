import Foundation

/// How `select_text` maps a matched text range onto the accessibility selection range.
public enum TextSelectionMode: String, CaseIterable, Sendable {
    case text
    case cursorBefore = "cursor_before"
    case cursorAfter = "cursor_after"
}

/// A resolved accessibility selection target.
///
/// Offsets are UTF-16 code units because `kAXSelectedTextRangeAttribute` carries a `CFRange`
/// whose units follow the backing `CFString`, not Swift `Character` counts.
public struct TextSelectionTarget: Equatable, Sendable {
    public let location: Int
    public let length: Int
    public let matchedLocation: Int
    public let matchedLength: Int
    public let selectionMode: TextSelectionMode
}

public enum TextSelectionResolverError: Error, Equatable {
    case emptyText
    case notFound
    case ambiguous(occurrenceCount: Int)
}

public enum TextSelectionResolver {
    /// Resolves `text` inside `value`, optionally disambiguated by the text immediately before
    /// (`prefix`) and after (`suffix`) it, into the range `select_text` should select.
    ///
    /// Every possible placement counts as an occurrence, including overlapping ones, so an
    /// ambiguous target fails closed instead of silently selecting the first match.
    public static func resolve(
        value: String,
        text: String,
        prefix: String?,
        suffix: String?,
        selection mode: TextSelectionMode
    ) throws -> TextSelectionTarget {
        guard !text.isEmpty else {
            throw TextSelectionResolverError.emptyText
        }

        let leading = normalized(prefix)
        let trailing = normalized(suffix)
        let needle = leading + text + trailing
        let haystack = value as NSString
        let occurrences = occurrenceRanges(of: needle, in: haystack)

        guard let first = occurrences.first else {
            throw TextSelectionResolverError.notFound
        }

        guard occurrences.count == 1 else {
            throw TextSelectionResolverError.ambiguous(occurrenceCount: occurrences.count)
        }

        let matchedLocation = first.location + (leading as NSString).length
        let matchedLength = (text as NSString).length

        switch mode {
        case .text:
            return TextSelectionTarget(
                location: matchedLocation,
                length: matchedLength,
                matchedLocation: matchedLocation,
                matchedLength: matchedLength,
                selectionMode: mode
            )
        case .cursorBefore:
            return TextSelectionTarget(
                location: matchedLocation,
                length: 0,
                matchedLocation: matchedLocation,
                matchedLength: matchedLength,
                selectionMode: mode
            )
        case .cursorAfter:
            return TextSelectionTarget(
                location: matchedLocation + matchedLength,
                length: 0,
                matchedLocation: matchedLocation,
                matchedLength: matchedLength,
                selectionMode: mode
            )
        }
    }

    private static func normalized(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return ""
        }

        return value
    }

    private static func occurrenceRanges(of needle: String, in haystack: NSString) -> [NSRange] {
        guard haystack.length > 0, !needle.isEmpty else {
            return []
        }

        var ranges: [NSRange] = []
        var searchLocation = 0

        while searchLocation < haystack.length {
            let searchRange = NSRange(location: searchLocation, length: haystack.length - searchLocation)
            let found = haystack.range(of: needle, options: [], range: searchRange)
            guard found.location != NSNotFound else {
                break
            }

            ranges.append(found)
            searchLocation = found.location + 1
        }

        return ranges
    }
}
