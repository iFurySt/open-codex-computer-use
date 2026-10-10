import AppKit
import ImageIO
import Darwin
import XCTest
@testable import OpenComputerUseKit

final class ImageCaptureConfigTests: XCTestCase {
    func testPrecedenceAndInvalidOverrides() {
        let file: [String: Any] = ["format": "jpeg", "maxDimension": 640]
        let env = ["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "800"]
        let config = ImageCaptureConfig.resolve(image: file, environment: env)
        XCTAssertEqual(config.format, "jpg")
        XCTAssertEqual(config.maxDimension, 800)
        XCTAssertEqual(config.captureTimeout, 5)
        XCTAssertEqual(ImageCaptureConfig.resolve(image: ["maxDimension": true, "format": "gif"], environment: [:]), .defaults)
    }
    func testPathResolution() throws {
        XCTAssertEqual(try OCUConfiguration.fileURL(environment: ["HOME": "/users/test"]).path, "/users/test/.config/ocu/config.json")
        XCTAssertEqual(try OCUConfiguration.fileURL(environment: ["XDG_CONFIG_HOME": "/settings"]).path, "/settings/ocu/config.json")
        XCTAssertEqual(try OCUConfiguration.fileURL(environment: ["OPEN_COMPUTER_USE_CONFIG_FILE": "/settings/custom.json"]).path, "/settings/custom.json")
        XCTAssertThrowsError(try OCUConfiguration.fileURL(environment: ["XDG_CONFIG_HOME": "relative"]))
    }
    func testNativeReloadsPersistedConfigurationAndFallsBackOnMalformedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.json")
        let keys = OCUConfiguration.environmentKeys
        let previous = Dictionary(uniqueKeysWithValues: keys.map { ($0, getenv($0).map { String(cString: $0) }) })
        for key in keys { unsetenv(key) }
        defer {
            for (key, value) in previous {
                if let value { setenv(key, value, 1) } else { unsetenv(key) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
        setenv("OPEN_COMPUTER_USE_CONFIG_FILE", file.path, 1)
        try Data(#"{"image":{"format":"jpeg","maxDimension":640}}"#.utf8).write(to: file, options: .atomic)
        XCTAssertEqual(ImageCaptureConfig.current.format, "jpg")
        XCTAssertEqual(ImageCaptureConfig.current.maxDimension, 640)
        try Data(#"{"image":{"format":"png","maxDimension":800}}"#.utf8).write(to: file, options: .atomic)
        XCTAssertEqual(ImageCaptureConfig.current.maxDimension, 800)
        setenv("OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION", "1024", 1)
        XCTAssertEqual(ImageCaptureConfig.current.maxDimension, 1024)
        try Data("broken".utf8).write(to: file, options: .atomic)
        XCTAssertEqual(ImageCaptureConfig.current.maxDimension, 1024)
        XCTAssertEqual(ImageCaptureConfig.current.format, "png")
    }
    func testExplicitPoliciesAndNullableLimits() {
        let config = ImageCaptureConfig.resolve(image: ["maxLongEdgePixels": NSNull(), "scaleDownAfterMaxSize": false, "discardBelowPixelCount": 4096], environment: [:])
        XCTAssertNil(config.maxDimension)
        XCTAssertFalse(config.scaleDownAfterMaxSize)
        XCTAssertEqual(config.discardBelowPixelCount, 4096)
        let overridden = ImageCaptureConfig.resolve(image: ["maxLongEdgePixels": NSNull()], environment: ["OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION": "1000"])
        XCTAssertEqual(overridden.maxDimension, 1000)
    }
    func testPixelAreaDiscardBoundaryAndOversizePolicy() throws {
        func image(_ width: Int, _ height: Int) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let below = encodeScreenshot(for: try image(7, 9), config: .defaults)
        XCTAssertNil(below.data)
        XCTAssertTrue(below.note?.contains("64 pixels") == true)
        XCTAssertNotNil(encodeScreenshot(for: try image(8, 8), config: .defaults).data)
        XCTAssertNotNil(encodeScreenshot(for: try image(1, 64), config: .defaults).data)
        let oversized = try image(800, 600)
        let omitted = encodeScreenshot(for: oversized, config: ImageCaptureConfig(scaleDownAfterMaxSize: false, maxDimension: 80))
        XCTAssertNil(omitted.data)
        XCTAssertTrue(omitted.note?.contains("scaleDownAfterMaxSize is false") == true)
        let resizedTooSmall = encodeScreenshot(for: oversized, config: ImageCaptureConfig(discardBelowPixelCount: 10000, maxDimension: 80))
        XCTAssertNil(resizedTooSmall.data)
        XCTAssertTrue(resizedTooSmall.note?.contains("resizing would fall below") == true)
        let unbounded = encodeScreenshot(for: oversized, config: ImageCaptureConfig(maxDimension: nil))
        XCTAssertNotNil(unbounded.data)
        XCTAssertNil(unbounded.note)
    }
    func testEncodingBoundsAndCoordinateMapping() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let image = try XCTUnwrap(context.makeImage())
        for format in ["png", "jpg", "webp"] {
            let config = ImageCaptureConfig.resolve(image: ["format": format, "maxLongEdgePixels": 80, "maxBytes": 1, "byteBudgetMinScale": 0.01, "minScale": 0.01], environment: ["OPEN_COMPUTER_USE_IMAGE_MAX_BYTES": "1", "OPEN_COMPUTER_USE_IMAGE_MIN_SCALE": "0.01"])
            let data = try XCTUnwrap(boundedScreenshotData(for: image, config: config))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 80)
            XCTAssertEqual(decoded.height, 60)
            XCTAssertEqual(ToolResultContentItem.screenshotImage(data).dictionary["mimeType"] as? String, format == "jpg" ? "image/jpeg" : "image/\(format)")
            let mapped = screenshotPixelToWindowPoint(CGPoint(x: 40, y: 30), screenshotPixelSize: CGSize(width: 80, height: 60), windowBounds: CGRect(x: 0, y: 0, width: 800, height: 600))
            XCTAssertEqual(mapped, CGPoint(x: 400, y: 300))

        }
    }
}
