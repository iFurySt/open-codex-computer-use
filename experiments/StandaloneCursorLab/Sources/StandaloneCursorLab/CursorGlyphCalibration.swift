import CoreGraphics

enum CursorGlyphCalibration {
    static let neutralHeading = -CGFloat.pi / 2
    static let restingRotation = -26.5 * CGFloat.pi / 180
}

enum SynthesizedCursorOverlayMetrics {
    static let windowSize = CGSize(width: 126, height: 126)
}

enum SynthesizedCursorIdleStyle {
    static let wobbleAmplitude = CGFloat.pi / 12
}
