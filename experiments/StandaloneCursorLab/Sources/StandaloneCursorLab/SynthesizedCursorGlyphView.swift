import AppKit
import CoreGraphics
import Foundation

private enum SynthesizedCursorColors {
    static let pointerFill = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: 0.98)
    static let pointerStroke = NSColor(calibratedWhite: 0.90, alpha: 0.92)
}

@MainActor
final class SynthesizedCursorGlyphView: NSView {
    var rotation: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var cursorBodyOffset: CGVector = .zero {
        didSet { needsDisplay = true }
    }

    var fogOffset: CGVector = .zero {
        didSet { needsDisplay = true }
    }

    var fogOpacity: CGFloat = 0.12 {
        didSet { needsDisplay = true }
    }

    var fogScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var clickProgress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    private let referenceImage = loadReferenceCursorWindowImage()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        if let referenceImage {
            drawReferenceImage(referenceImage, in: context)
            return
        }

        drawProceduralGlyph(in: context)
    }

    private func drawReferenceImage(_ image: NSImage, in context: CGContext) {
        let drawingBodyOffset = drawingVector(from: cursorBodyOffset)
        let motionCompression = min(hypot(cursorBodyOffset.dx, cursorBodyOffset.dy) * 0.008, 0.018)
        let pulseCompression = clickProgress * 0.03

        context.saveGState()
        context.translateBy(
            x: bounds.midX + drawingBodyOffset.dx,
            y: bounds.midY + drawingBodyOffset.dy
        )
        context.rotate(by: drawingAngle(from: rotation - CursorGlyphCalibration.restingRotation))
        context.scaleBy(
            x: 1 - motionCompression - pulseCompression,
            y: 1 + (pulseCompression * 0.4)
        )
        context.translateBy(x: -bounds.midX, y: -bounds.midY)
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }

    private func drawProceduralGlyph(in context: CGContext) {
        let pulse = clickProgress
        let drawingFogOffset = drawingVector(from: fogOffset)
        let drawingBodyOffset = drawingVector(from: cursorBodyOffset)
        let fogCenter = CGPoint(
            x: bounds.midX + drawingFogOffset.dx,
            y: bounds.midY + drawingFogOffset.dy
        )
        let pointerCenter = CGPoint(
            x: bounds.midX + 2.6 + drawingBodyOffset.dx,
            y: bounds.midY - 3.2 + drawingBodyOffset.dy + (pulse * 0.35)
        )

        drawFog(in: context, center: fogCenter, pulse: pulse)
        drawPointer(in: context, center: pointerCenter, pulse: pulse)
    }

    private func drawFog(in context: CGContext, center: CGPoint, pulse: CGFloat) {
        let radius = ((66 * fogScale) / 2) + (pulse * 1.2)
        let glowRadius = radius * (0.30 + (pulse * 0.025))
        let opacityMultiplier = max(0.28, min(fogOpacity / 0.12, 2.2))
        let colors = [
            NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.35, alpha: (0.40 + (pulse * 0.02)) * opacityMultiplier).cgColor,
            NSColor(calibratedRed: 0.43, green: 0.41, blue: 0.40, alpha: (0.28 + (pulse * 0.015)) * opacityMultiplier).cgColor,
            NSColor(calibratedRed: 0.46, green: 0.44, blue: 0.43, alpha: 0.11 * opacityMultiplier).cgColor,
            NSColor(calibratedWhite: 0.60, alpha: 0.0).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.50, 0.82, 1]
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return
        }

        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        let coreColors = [
            NSColor(calibratedRed: 0.41, green: 0.39, blue: 0.38, alpha: (0.020 + (pulse * 0.006)) * opacityMultiplier).cgColor,
            NSColor(calibratedRed: 0.44, green: 0.41, blue: 0.40, alpha: 0.008 * opacityMultiplier).cgColor,
            NSColor(calibratedWhite: 0.80, alpha: 0.0).cgColor,
        ] as CFArray
        let coreLocations: [CGFloat] = [0, 0.62, 1]
        guard let coreGradient = CGGradient(colorsSpace: colorSpace, colors: coreColors, locations: coreLocations) else {
            return
        }

        context.saveGState()
        context.drawRadialGradient(
            coreGradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: glowRadius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private func drawPointer(in context: CGContext, center: CGPoint, pulse: CGFloat) {
        let pointerRect = CGRect(
            x: center.x - 10.5,
            y: center.y - 10.5,
            width: 21,
            height: 21
        )
        let outerPath = pointerPath(in: pointerRect)

        context.saveGState()
        let drawingBodyOffset = drawingVector(from: cursorBodyOffset)
        context.translateBy(x: bounds.midX + drawingBodyOffset.dx, y: bounds.midY + drawingBodyOffset.dy)
        context.rotate(by: drawingAngle(from: rotation - CursorGlyphCalibration.restingRotation))
        context.scaleBy(x: 1 - (pulse * 0.04), y: 1 + (pulse * 0.02))
        context.translateBy(x: -(bounds.midX + drawingBodyOffset.dx), y: -(bounds.midY + drawingBodyOffset.dy))

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3.2 + (pulse * 1.4)
        shadow.shadowOffset = CGSize(width: 0, height: -0.35)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.11)
        shadow.set()
        NSColor.black.withAlphaComponent(0.05).setFill()
        outerPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        SynthesizedCursorColors.pointerFill.setFill()
        outerPath.fill()

        SynthesizedCursorColors.pointerStroke.setStroke()
        outerPath.lineWidth = 1.55
        outerPath.lineJoinStyle = .round
        outerPath.lineCapStyle = .round
        outerPath.stroke()

        context.restoreGState()
    }

    private func pointerPath(in rect: CGRect) -> NSBezierPath {
        let contourRows: [(y: CGFloat, minX: CGFloat, maxX: CGFloat)] = [
            (39, 17, 21), (38, 16, 22), (37, 15, 22), (36, 15, 23), (35, 15, 24),
            (34, 15, 24), (33, 14, 25), (32, 14, 25), (31, 14, 26), (30, 14, 27),
            (29, 13, 29), (28, 13, 31), (27, 13, 34), (26, 13, 36), (25, 13, 37),
            (24, 12, 37), (23, 12, 37), (22, 12, 37), (21, 12, 37), (20, 12, 36),
            (19, 11, 36), (18, 11, 34), (17, 11, 32), (16, 11, 30), (15, 10, 27),
            (14, 10, 25), (13, 10, 23), (12, 11, 21), (11, 11, 19), (10, 13, 16),
        ]
        let sourceMinX: CGFloat = 10
        let sourceMaxX: CGFloat = 38
        let sourceMinY: CGFloat = 10
        let sourceMaxY: CGFloat = 39

        func mappedPoint(x: CGFloat, y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + ((x - sourceMinX) / (sourceMaxX - sourceMinX) * rect.width),
                y: rect.minY + ((y - sourceMinY) / (sourceMaxY - sourceMinY) * rect.height)
            )
        }

        let leftBoundary = contourRows.map { mappedPoint(x: $0.minX, y: $0.y) }
        let rightBoundary = contourRows.reversed().map { mappedPoint(x: $0.maxX, y: $0.y) }

        let path = NSBezierPath()
        path.move(to: leftBoundary[0])
        leftBoundary.dropFirst().forEach { path.line(to: $0) }
        rightBoundary.forEach { path.line(to: $0) }
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private func drawingVector(from screenVector: CGVector) -> CGVector {
        CGVector(dx: screenVector.dx, dy: -screenVector.dy)
    }

    private func drawingAngle(from screenAngle: CGFloat) -> CGFloat {
        -screenAngle
    }
}

private func loadReferenceCursorWindowImage() -> NSImage? {
    let fileURL = URL(fileURLWithPath: #filePath).standardizedFileURL
    let repoRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let referenceURL = repoRoot
        .appendingPathComponent("docs/references/codex-computer-use-reverse-engineering/assets/extracted-2026-04-19/official-software-cursor-window-252.png")

    return NSImage(contentsOf: referenceURL)
}
