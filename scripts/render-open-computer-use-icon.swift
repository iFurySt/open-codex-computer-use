#!/usr/bin/env swift

import AppKit
import Foundation

enum IconRenderError: Error {
    case invalidArguments
    case contextUnavailable(Int)
    case pngEncodingFailed(String)
}

let outputDirectoryURL = try {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count == 1 else {
        throw IconRenderError.invalidArguments
    }

    return URL(fileURLWithPath: String(arguments[arguments.startIndex]), isDirectory: true)
}()

try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true, attributes: nil)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (fileName, pixelSize) in iconFiles {
    try writeIconPNG(named: fileName, pixelSize: pixelSize, to: outputDirectoryURL)
}

func writeIconPNG(named fileName: String, pixelSize: Int, to directoryURL: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconRenderError.contextUnavailable(pixelSize)
    }

    bitmap.size = NSSize(width: CGFloat(pixelSize), height: CGFloat(pixelSize))

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconRenderError.contextUnavailable(pixelSize)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
    drawAppIcon(size: CGFloat(pixelSize))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconRenderError.pngEncodingFailed(fileName)
    }

    try pngData.write(to: directoryURL.appendingPathComponent(fileName))
}

func drawAppIcon(size: CGFloat) {
    // Keep this geometry aligned with Branding.makeAppIconImage in the app target.
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
    let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.67, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.94, green: 0.74, blue: 0.93, alpha: 1),
    ])!
    gradient.draw(in: tile, angle: 20)

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: size * x / 256, y: size * (1 - y / 256))
    }

    func scale(_ value: CGFloat) -> CGFloat {
        size * value / 256
    }

    let arc = NSBezierPath()
    arc.move(to: point(74, 156))
    arc.curve(
        to: point(182, 88),
        controlPoint1: point(78, 112),
        controlPoint2: point(136, 72)
    )
    arc.lineWidth = scale(12)
    arc.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.72).setStroke()
    arc.stroke()

    let pointerShadow = NSBezierPath()
    pointerShadow.move(to: point(129, 102))
    pointerShadow.line(to: point(129, 181))
    pointerShadow.line(to: point(149, 162))
    pointerShadow.line(to: point(161, 193))
    pointerShadow.line(to: point(176, 186))
    pointerShadow.line(to: point(164, 157))
    pointerShadow.line(to: point(192, 152))
    pointerShadow.close()
    NSColor.white.withAlphaComponent(0.14).setFill()
    pointerShadow.fill()

    let pointer = NSBezierPath()
    pointer.move(to: point(126, 98))
    pointer.line(to: point(126, 177))
    pointer.line(to: point(146, 158))
    pointer.line(to: point(158, 189))
    pointer.line(to: point(173, 182))
    pointer.line(to: point(161, 153))
    pointer.line(to: point(189, 148))
    pointer.close()
    pointer.lineWidth = scale(6)
    pointer.lineJoinStyle = .round
    pointer.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.94).setFill()
    pointer.fill()
    NSColor.white.setStroke()
    pointer.stroke()
}
