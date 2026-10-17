import CoreGraphics

/// Encode the already verified target window's local point. This private SPI
/// describes a mouse event; it neither initiates nor grants authentication.
public func encodeLockedUseWindowLocation(_ event: CGEvent, point: CGPoint) throws {
    guard point.x.isFinite, point.y.isFinite else {
        throw ComputerUseError.message("Invalid Locked Use window location")
    }
    try SkyLightSPI.shared.setWindowLocation(event, point: point)
}
