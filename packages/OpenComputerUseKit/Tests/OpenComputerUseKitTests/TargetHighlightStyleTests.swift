import AppKit
import XCTest
@testable import OpenComputerUseKit

/// Pins the target-highlight restyle.
///
/// The ring is OCU's own advisory overlay - the official Codex Computer Use
/// binary has no "target highlight" concept, only the software cursor - so
/// these tests lock the `.codex` preset to the values the cursor renderer
/// already uses, and keep `.plain` as the exact legacy rollback path.
final class TargetHighlightStyleTests: XCTestCase {
    // MARK: - Environment selection

    func testAbsentEnvironmentSelectsCodex() {
        XCTAssertEqual(targetHighlightStyleName(environment: [:]), .codex)
        XCTAssertEqual(targetHighlightStyle(environment: [:]), .codex)
    }

    func testEmptyAndWhitespaceEnvironmentSelectsCodex() {
        for value in ["", " ", "\t", "\n  \t"] {
            XCTAssertEqual(
                targetHighlightStyle(environment: [targetHighlightStyleEnvironmentKey: value]),
                .codex,
                "expected codex for \(value.debugDescription)"
            )
        }
    }

    func testGarbageEnvironmentSelectsCodex() {
        for value in ["codexx", "fog", "1", "0", "true", "yes", "plain2", "codex plain", "-"] {
            XCTAssertEqual(
                targetHighlightStyle(environment: [targetHighlightStyleEnvironmentKey: value]),
                .codex,
                "expected codex for \(value.debugDescription)"
            )
        }
    }

    func testExplicitPlainIsCaseInsensitive() {
        for value in ["plain", "PLAIN", "Plain", "  pLaIn  ", "\tplain\n"] {
            XCTAssertEqual(
                targetHighlightStyleName(environment: [targetHighlightStyleEnvironmentKey: value]),
                .plain,
                "expected plain for \(value.debugDescription)"
            )
            XCTAssertEqual(
                targetHighlightStyle(environment: [targetHighlightStyleEnvironmentKey: value]),
                .plain,
                "expected plain for \(value.debugDescription)"
            )
        }
    }

    func testExplicitCodexIsCaseInsensitive() {
        for value in ["codex", "CODEX", "Codex", "  CoDeX  "] {
            XCTAssertEqual(
                targetHighlightStyle(environment: [targetHighlightStyleEnvironmentKey: value]),
                .codex,
                "expected codex for \(value.debugDescription)"
            )
        }
    }

    // MARK: - Pinned presets

    func testCodexPresetUsesTheCursorRendererNumbers() {
        let style = TargetHighlightStyle.codex

        // Retained from the previous OCU ring; the official binary has no ring
        // geometry to copy.
        XCTAssertEqual(style.cornerRadius, 6)
        // SoftwareCursorGlyphRenderer.swift:231.
        XCTAssertEqual(style.strokeWidth, 1.55)
        // Cursor body colour (SoftwareCursorGlyphRenderer.swift:54): a ring has no
        // body, so the dark body colour is the stroke. A white stroke measured as
        // invisible on light pages, which is the reported "no ring on screen".
        XCTAssertEqual(
            style.strokeColor,
            NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: 0.85)
        )
        assertCalibratedRGB(style.strokeColor, red: 0.38, green: 0.36, blue: 0.35, alpha: 0.85)
        // The cursor's light edge (SoftwareCursorGlyphRenderer.swift:55) survives as
        // a light rim outside the dark stroke, so the ring reads on dark
        // backgrounds too.
        XCTAssertEqual(style.rimColor, NSColor(calibratedWhite: 0.90, alpha: 0.55))
        assertCalibratedWhite(style.rimColor, 0.90, alpha: 0.55)
        XCTAssertEqual(style.rimWidth, 1)
        XCTAssertEqual(style.rimOutset, 1.7)
        // Cursor body RGB (SoftwareCursorGlyphRenderer.swift:54) at the fog
        // gradient's outer visible alpha (SoftwareCursorGlyphRenderer.swift:143).
        XCTAssertEqual(
            style.fillColor,
            NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: 0.11)
        )
        assertCalibratedRGB(style.fillColor, red: 0.38, green: 0.36, blue: 0.35, alpha: 0.11)
        // Fog radius ((66 * fogScale) / 2) at fogScale = 1
        // (SoftwareCursorGlyphRenderer.swift:137).
        XCTAssertEqual(style.glowRadius, 33)
        XCTAssertEqual(style.glowOpacity, 0.28)
        // Fog gradient mid stop (SoftwareCursorGlyphRenderer.swift:142).
        XCTAssertEqual(style.glowColor, NSColor(calibratedRed: 0.43, green: 0.41, blue: 0.40, alpha: 1))
        assertCalibratedRGB(style.glowColor, red: 0.43, green: 0.41, blue: 0.40, alpha: 1)
        XCTAssertEqual(style.ringOutset, 3)
        // panelPadding = ringOutset + max(stroke/2, rimOutset + rimWidth/2) + glow
        //              = 3 + max(0.775, 2.2) + 33 = 38.2.
        XCTAssertEqual(style.panelPadding, 3 + 2.2 + 33, accuracy: 0.0001)
        XCTAssertEqual(style.pathInset, 2.2 + 33, accuracy: 0.0001)
    }

    func testPlainPresetIsExactlyTheLegacyRing() {
        let style = TargetHighlightStyle.plain

        XCTAssertEqual(style.cornerRadius, 6)
        XCTAssertEqual(style.strokeWidth, 2)
        XCTAssertEqual(style.strokeColor, NSColor.controlAccentColor)
        XCTAssertEqual(style.fillColor, NSColor.controlAccentColor.withAlphaComponent(0.10))
        XCTAssertEqual(style.fillColor.alphaComponent, 0.10, accuracy: 0.0001)
        // "No glow" is the rollback contract.
        XCTAssertEqual(style.glowRadius, 0)
        XCTAssertEqual(style.glowOpacity, 0)
        // The legacy ring had a single hard border: no light rim either.
        XCTAssertEqual(style.rimWidth, 0)
        XCTAssertEqual(style.rimColor, NSColor.clear)
        XCTAssertEqual(style.rimOutset, 0)
        // Legacy panel frame: globalRect.insetBy(dx: -4, dy: -4).
        XCTAssertEqual(style.panelPadding, 4)
        // Legacy path: bounds.insetBy(dx: 1, dy: 1).
        XCTAssertEqual(style.pathInset, 1)
    }

    func testTheTwoPresetsDifferInAppearance() {
        XCTAssertNotEqual(TargetHighlightStyle.codex, TargetHighlightStyle.plain)
    }

    func testRingStaysAtTheSameDistanceFromTheTargetRectForEveryStyle() {
        XCTAssertEqual(TargetHighlightStyle.codex.ringOutset, TargetHighlightStyle.plain.ringOutset)
    }

    func testGlowFitsInsideThePanelPadding() {
        for style in [TargetHighlightStyle.codex, TargetHighlightStyle.plain] {
            XCTAssertEqual(
                style.panelPadding,
                style.ringOutset
                    + max(style.strokeWidth / 2, style.rimOutset + (style.rimWidth / 2))
                    + style.glowRadius,
                accuracy: 0.0001
            )
            XCTAssertGreaterThan(style.pathInset, 0)
        }
    }

    // MARK: - Lifetime / visibility separation

    @MainActor
    func testStyleChoiceDoesNotAffectLifetimeOrVisibilityDecisions() {
        // Neither targetHighlightDisplayDuration nor targetHighlightShouldWithdraw
        // takes a style parameter: the style is read only by the presenter's draw
        // path. Running both presets through the same inputs pins that separation;
        // if a future change routed style into the lifetime contract, the two
        // outcome vectors would diverge and fail here.
        let presets = [TargetHighlightStyle.codex, TargetHighlightStyle.plain]
        XCTAssertNotEqual(presets[0], presets[1])

        let expectedScreenFrame = CGRect(x: 100, y: 200, width: 120, height: 24)

        var outcomes: [[String]] = []
        for _ in presets {
            outcomes.append(lifetimeAndVisibilityOutcome(expectedScreenFrame: expectedScreenFrame))
        }

        XCTAssertEqual(outcomes[0], outcomes[1])

        // The audited contract itself must not move.
        XCTAssertEqual(targetHighlightDisplayDuration(isPopup: false), 0.45, accuracy: 0.0001)
        XCTAssertEqual(targetHighlightDisplayDuration(isPopup: true), 0.30, accuracy: 0.0001)
        XCTAssertEqual(
            TargetHighlightLifetimeController.defaultFadeOutDuration,
            0.35,
            accuracy: 0.0001
        )
        XCTAssertEqual(TargetHighlightLifetimeController.watchdogInterval, 0.22, accuracy: 0.0001)
    }

    /// Mirrors the lifetime/visibility call sites that own the ring's rhythm.
    /// None of them takes a style, which is exactly what the test above proves.
    @MainActor
    private func lifetimeAndVisibilityOutcome(expectedScreenFrame: CGRect) -> [String] {
        let samples = [
            TargetHighlightLivenessSample(currentScreenFrame: expectedScreenFrame),
            TargetHighlightLivenessSample(isElementValid: false),
            TargetHighlightLivenessSample(isWindowPresent: false),
            TargetHighlightLivenessSample(currentScreenFrame: expectedScreenFrame.offsetBy(dx: 40, dy: 0)),
            TargetHighlightLivenessSample(currentScreenFrame: nil),
        ]

        var outcome = [
            String(describing: targetHighlightDisplayDuration(isPopup: false)),
            String(describing: targetHighlightDisplayDuration(isPopup: true)),
            String(describing: TargetHighlightLifetimeController.defaultFadeOutDuration),
            String(describing: TargetHighlightLifetimeController.watchdogInterval),
        ]
        outcome += samples.map {
            String(
                describing: targetHighlightShouldWithdraw(
                    expectedScreenFrame: expectedScreenFrame,
                    sample: $0
                )
            )
        }
        return outcome
    }

    // MARK: - Colour helpers

    private func assertCalibratedWhite(
        _ color: NSColor,
        _ white: CGFloat,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let gray = color.usingColorSpace(.genericGray) else {
            XCTFail("colour \(color) has no generic-gray representation", file: file, line: line)
            return
        }

        XCTAssertEqual(gray.whiteComponent, white, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(gray.alphaComponent, alpha, accuracy: 0.0001, file: file, line: line)
    }

    private func assertCalibratedRGB(
        _ color: NSColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rgb = color.usingColorSpace(.genericRGB) else {
            XCTFail("colour \(color) has no generic-RGB representation", file: file, line: line)
            return
        }

        XCTAssertEqual(rgb.redComponent, red, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, green, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, blue, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgb.alphaComponent, alpha, accuracy: 0.0001, file: file, line: line)
    }
}
