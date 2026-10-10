import CoreGraphics
import Foundation
import libwebp

/// Encode screenshots losslessly so text and small controls keep their original pixels.
func losslessWebPData(for image: CGImage) -> Data? {
    let stride = image.width * 4
    guard image.width <= 16383, image.height <= 16383 else { return nil }
    var pixels = [UInt8](repeating: 0, count: stride * image.height)
    return pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = buffer.bindMemory(to: UInt8.self)
        // CoreGraphics renders premultiplied RGBA; libwebp expects straight RGBA.
        for offset in Swift.stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[offset + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 { bytes[offset + channel] = UInt8(min(255, (Int(bytes[offset + channel]) * 255 + alpha / 2) / alpha)) }
            }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let size = WebPEncodeLosslessRGBA(bytes.baseAddress, Int32(image.width), Int32(image.height), Int32(stride), &output)
        guard size > 0, let output else { return nil }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }
}
