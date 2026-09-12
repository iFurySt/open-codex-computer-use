import AppKit
import CoreGraphics
import Foundation

/// Name of the environment variable that selects the target-highlight style.
let targetHighlightStyleEnvironmentKey = "OPEN_COMPUTER_USE_TARGET_HIGHLIGHT_STYLE"

/// The shipped ring looks. `codex` is the default, `plain` is the rollback.
enum TargetHighlightStyleName: String {
    case codex
    case plain
}

/// Resolves the ring style from the environment.
///
/// Accepts `codex` and `plain` only, case-insensitively and after trimming
/// whitespace. Everything else - absent, empty, whitespace-only or an unknown
/// value - falls back to `codex`. Parsing mirrors the other environment knobs
/// (`visualCursorIdleSwayWindowMilliseconds`, `windowRecoveryEnabled`).
func targetHighlightStyleName(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> TargetHighlightStyleName {
    guard
        let rawValue = environment[targetHighlightStyleEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
        let name = TargetHighlightStyleName(rawValue: rawValue)
    else {
        return .codex
    }

    return name
}

func targetHighlightStyle(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> TargetHighlightStyle {
    switch targetHighlightStyleName(environment: environment) {
    case .codex:
        return .codex
    case .plain:
        return .plain
    }
}

/// Geometry and paint for the advisory target-highlight ring.
///
/// The official Codex Computer Use binary has no "target highlight" concept:
/// the only runtime overlay it ships is the software cursor (`Software Cursor`,
/// see `docs/references/codex-computer-use-reverse-engineering/software-cursor-overlay.md`).
/// The ring is therefore OCU's own advisory overlay, and the `.codex` preset
/// deliberately speaks the cursor's visual language instead of introducing a
/// second one.
///
/// `SoftwareCursorGlyphRenderer` stays the single source of truth for those
/// numbers. Its colours and fog gradient are file-private, so the preset below
/// repeats them with a citation - keep both sides in sync.
struct TargetHighlightStyle: Equatable {
    /// Corner radius of the ring path, in points.
    let cornerRadius: CGFloat
    /// Width of the ring stroke, in points.
    let strokeWidth: CGFloat
    let strokeColor: NSColor
    let fillColor: NSColor
    /// Blur radius of the fog halo, in points. `0` draws no glow.
    let glowRadius: CGFloat
    /// Alpha the fog halo is painted with.
    let glowOpacity: CGFloat
    /// Base colour of the fog halo, before `glowOpacity` is applied.
    let glowColor: NSColor
    /// Light rim drawn just outside the stroke; the cursor's light edge
    /// translated to a ring. `rimWidth == 0` draws no rim.
    let rimColor: NSColor
    /// Width of the light rim, in points.
    let rimWidth: CGFloat
    /// Distance from the ring's stroke centreline to the rim's centreline.
    let rimOutset: CGFloat
    /// Distance from the target rect to the ring's stroke centreline, in points.
    let ringOutset: CGFloat
    /// Distance from the target rect to the panel edge, in points. Always covers
    /// `ringOutset + strokeWidth / 2 + glowRadius`, so the halo fades out inside
    /// the panel instead of being clipped at its edge.
    let panelPadding: CGFloat

    init(
        cornerRadius: CGFloat,
        strokeWidth: CGFloat,
        strokeColor: NSColor,
        fillColor: NSColor,
        glowRadius: CGFloat,
        glowOpacity: CGFloat,
        glowColor: NSColor,
        rimColor: NSColor = .clear,
        rimWidth: CGFloat = 0,
        rimOutset: CGFloat = 0,
        ringOutset: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.strokeWidth = strokeWidth
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.glowRadius = glowRadius
        self.glowOpacity = glowOpacity
        self.glowColor = glowColor
        self.rimColor = rimColor
        self.rimWidth = rimWidth
        self.rimOutset = rimOutset
        self.ringOutset = ringOutset
        self.panelPadding = ringOutset + max(strokeWidth / 2, rimOutset + (rimWidth / 2)) + glowRadius
    }

    /// Panel-local inset of the drawn ring path. It keeps the visible ring at
    /// `ringOutset` from the target rect for every style, so switching style
    /// never moves the ring itself.
    var pathInset: CGFloat {
        panelPadding - ringOutset
    }
}

extension TargetHighlightStyle {
    /// Default look, borrowed from the software cursor.
    ///
    /// - `cornerRadius: 6` - retained from the previous OCU ring (which drew
    ///   `cornerWidth: 6`); the official binary has no ring geometry to copy.
    /// - `strokeWidth: 1.55` - `SoftwareCursorGlyphRenderer.swift:231`.
    /// - `strokeColor` - the cursor *body* colour `0.38/0.36/0.35`
    ///   (`SoftwareCursorGlyphRenderer.swift:54`). The cursor paints a dark body
    ///   with a light edge; a ring has no body, so the dark body colour becomes
    ///   the stroke. A white stroke (the cursor's edge colour) was measured to be
    ///   invisible on light pages, which is exactly the "no ring on screen"
    ///   report.
    /// - `rimColor` / `rimWidth` / `rimOutset` - the cursor's light edge
    ///   (`pointerStroke`, `SoftwareCursorGlyphRenderer.swift:55`) as a 1pt rim
    ///   just outside the dark stroke, so the ring keeps contrast on dark
    ///   backgrounds too.
    /// - `fillColor` - the cursor body colour `0.38/0.36/0.35`
    ///   (`SoftwareCursorGlyphRenderer.swift:54`) at the fog gradient's outer
    ///   visible alpha `0.11` (`SoftwareCursorGlyphRenderer.swift:143`), so the
    ///   target stays readable under the ring.
    /// - `glowRadius: 33` - the cursor's fog radius `((66 * fogScale) / 2)` at
    ///   `fogScale = 1` (`SoftwareCursorGlyphRenderer.swift:137`).
    /// - `glowColor`/`glowOpacity` - the fog gradient's mid stop, RGB
    ///   `0.43/0.41/0.40` at alpha `0.28` (`SoftwareCursorGlyphRenderer.swift:142`).
    /// - `ringOutset: 3` - unchanged from the legacy ring: the panel expanded the
    ///   target rect by 4 and the path was inset by 1.
    static let codex = TargetHighlightStyle(
        cornerRadius: 6,
        strokeWidth: 1.55,
        strokeColor: NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: 0.85),
        fillColor: NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: 0.11),
        glowRadius: 33,
        glowOpacity: 0.28,
        glowColor: NSColor(calibratedRed: 0.43, green: 0.41, blue: 0.40, alpha: 1),
        rimColor: NSColor(calibratedWhite: 0.90, alpha: 0.55),
        rimWidth: 1,
        rimOutset: 1.7,
        ringOutset: 3
    )

    /// Exact pre-`codex` ring: a hard 2px accent border plus a 10% accent fill
    /// and no glow. This is the rollback path; `panelPadding` resolves to the
    /// historical 4 points and `pathInset` to 1 point.
    static let plain = TargetHighlightStyle(
        cornerRadius: 6,
        strokeWidth: 2,
        strokeColor: .controlAccentColor,
        fillColor: NSColor.controlAccentColor.withAlphaComponent(0.10),
        glowRadius: 0,
        glowOpacity: 0,
        glowColor: .clear,
        ringOutset: 3
    )
}
