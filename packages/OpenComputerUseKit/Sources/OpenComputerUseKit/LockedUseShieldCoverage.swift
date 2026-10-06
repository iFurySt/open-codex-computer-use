import Foundation

/// Compare only Quartz global bounds from WindowServer and CGDisplayBounds.
/// Larger opaque surfaces are valid; an uncovered edge is never tolerated.
public enum LockedUseShieldCoverage {
    /// Extra opaque area survives the loginwindow zoom transition. Health
    /// still requires actual WindowServer bounds to contain the full display.
    public static func surfaceFrame(for display: CGRect) -> CGRect {
        display.insetBy(dx: -display.width / 4, dy: -display.height / 4)
    }

    public static func covers(_ surface: CGRect, display: CGRect) -> Bool {
        func valid(_ rect: CGRect) -> Bool {
            !rect.isNull && !rect.isInfinite && [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
             rect.maxX, rect.maxY].allSatisfy(\.isFinite)
                && rect.size.width > 0 && rect.size.height > 0
        }
        guard valid(surface), valid(display) else { return false }
        return surface.minX <= display.minX && surface.minY <= display.minY
            && surface.maxX >= display.maxX && surface.maxY >= display.maxY
    }
}
