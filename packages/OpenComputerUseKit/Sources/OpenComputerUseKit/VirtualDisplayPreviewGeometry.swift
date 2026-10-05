import CoreGraphics
import Foundation

/// View-local geometry. Screenshot/tool coordinates never depend on this transform.
struct VirtualDisplayViewport {
    private(set) var zoom: CGFloat = 1
    private(set) var pan = CGPoint.zero
    mutating func reset() { zoom = 1; pan = .zero }
    func imageRect(image: CGSize, view: CGSize, originalSize: Bool, backingScale: CGFloat) -> CGRect {
        guard image.width > 0, image.height > 0, view.width > 0, view.height > 0 else { return .zero }
        let base = originalSize ? 1 / max(backingScale, 1) : min(view.width / image.width, view.height / image.height)
        let size = CGSize(width: image.width * base * zoom, height: image.height * base * zoom)
        return CGRect(x: (view.width - size.width) / 2 + pan.x,
                      y: (view.height - size.height) / 2 + pan.y, width: size.width, height: size.height)
    }
    mutating func magnify(by factor: CGFloat, at anchor: CGPoint, image: CGSize, view: CGSize, originalSize: Bool, backingScale: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        let before = imageRect(image: image, view: view, originalSize: originalSize, backingScale: backingScale)
        guard before.width > 0, before.height > 0 else { return }
        let x = (anchor.x - before.minX) / before.width
        let y = (anchor.y - before.minY) / before.height
        zoom = min(max(zoom * factor, 0.25), 8)
        let after = imageRect(image: image, view: view, originalSize: originalSize, backingScale: backingScale)
        pan.x += anchor.x - after.minX - x * after.width
        pan.y += anchor.y - after.minY - y * after.height
        constrain(image: image, view: view, originalSize: originalSize, backingScale: backingScale)
    }
    mutating func drag(by delta: CGPoint, image: CGSize, view: CGSize, originalSize: Bool, backingScale: CGFloat) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        pan.x += delta.x; pan.y += delta.y
        constrain(image: image, view: view, originalSize: originalSize, backingScale: backingScale)
    }
    mutating func constrain(image: CGSize, view: CGSize, originalSize: Bool, backingScale: CGFloat) {
        let rect = imageRect(image: image, view: view, originalSize: originalSize, backingScale: backingScale)
        let x = max((rect.width - view.width) / 2, 0)
        let y = max((rect.height - view.height) / 2, 0)
        pan.x = min(max(pan.x, -x), x); pan.y = min(max(pan.y, -y), y)
    }
}

