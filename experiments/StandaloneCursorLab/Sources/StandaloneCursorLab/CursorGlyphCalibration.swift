import CoreGraphics

enum CursorGlyphCalibration {
    // The captured official baseline cursor artwork rests facing upper-left.
    // In the lab's y-down canvas coordinates, that is -3π/4.
    static let neutralHeading = -(3 * CGFloat.pi / 4)
    static let restingRotation: CGFloat = 0
}

enum SynthesizedCursorOverlayMetrics {
    static let windowSize = CGSize(width: 126, height: 126)
}

enum SynthesizedCursorIdleStyle {
    static let wobbleAmplitude = CGFloat.pi / 12
}
