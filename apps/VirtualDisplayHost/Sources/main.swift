import Foundation
import CoreGraphics
import VirtualDisplayBridge

func reply(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object), let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
}

do {
    guard let line = readLine(), let data = line.data(using: .utf8),
          let config = try JSONSerialization.jsonObject(with: data) as? [String: Int],
          let width = config["width"], let height = config["height"], let scale = config["scale"],
          (640...7680).contains(width), (480...4320).contains(height), [1, 2].contains(scale),
          width * scale <= 7680, height * scale <= 4320,
          let serial = UInt32(exactly: config["serial"] ?? 1), serial != 0 else {
        throw NSError(domain: "OCUVirtualDisplay", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid display configuration"])
    }
    // Capture physical arrangement BEFORE display creation: macOS may normalize
    // origins as soon as the virtual display is registered.
    var originalIDs = [CGDirectDisplayID](repeating: 0, count: 64)
    var originalCount: UInt32 = 0
    CGGetActiveDisplayList(64, &originalIDs, &originalCount)
    let originals = originalIDs.prefix(Int(originalCount)).map { ($0, CGDisplayBounds($0)) }
    var creationError: NSError?
    guard let display = OCUCreateVirtualDisplay(UInt32(width), UInt32(height), UInt32(scale), serial, &creationError) else {
        throw creationError ?? NSError(domain: "OCUVirtualDisplay", code: 6, userInfo: [NSLocalizedDescriptionKey: "Display creation failed"])
    }
    let displayID = OCUVirtualDisplayID(display)
    var configuration: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&configuration) == .success else {
        throw NSError(domain: "OCUVirtualDisplay", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot begin display configuration"])
    }
    var count: UInt32 = 0
    var ids = [CGDirectDisplayID](repeating: 0, count: 64)
    CGGetActiveDisplayList(64, &ids, &count)
    let right = originals.map { $0.1.maxX }.max() ?? 0
    for (id, frame) in originals {
        guard CGConfigureDisplayOrigin(configuration, id, Int32(frame.minX), Int32(frame.minY)) == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw NSError(domain: "OCUVirtualDisplay", code: 7, userInfo: [NSLocalizedDescriptionKey: "Cannot preserve physical display arrangement"])
        }
    }
    guard CGConfigureDisplayMirrorOfDisplay(configuration, displayID, kCGNullDirectDisplay) == .success,
          CGConfigureDisplayOrigin(configuration, displayID, Int32(right), 0) == .success,
          CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
        CGCancelDisplayConfiguration(configuration)
        throw NSError(domain: "OCUVirtualDisplay", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot arrange extended display"])
    }
    reply(["display_id": displayID])
    // The pipe is the lease: stop or parent EOF ends this disposable process.
    withExtendedLifetime(display) {
        while let command = readLine(), command != "stop" {}
    }
} catch {
    reply(["error": error.localizedDescription])
    exit(1)
}
