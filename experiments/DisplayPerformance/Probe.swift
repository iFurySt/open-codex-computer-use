import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import CoreImage
import Metal
import ScreenCaptureKit

func emit(_ value: [String: Any]) {
    print(String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
    fflush(stdout)
}
func displays(includeUUID: Bool = true) -> [[String: Any]] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 64); var count: UInt32 = 0
    guard CGGetOnlineDisplayList(64, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { id in
        let b = CGDisplayBounds(id)
        let uuid = includeUUID ? CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue() : nil
        return ["id": id, "serial": CGDisplaySerialNumber(id), "vendor": CGDisplayVendorNumber(id),
                "uuid": uuid.map { CFUUIDCreateString(nil, $0) as String } as Any? ?? NSNull(), "main": id == CGMainDisplayID(),
                "frame": ["x": b.minX, "y": b.minY, "width": b.width, "height": b.height]]
    }
}
final class Frames: NSObject, SCStreamOutput, SCStreamDelegate {
    let lock = NSLock()
    var frame: CVPixelBuffer?
    var count = 0, rendered = 0, error: String?
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let frame = CMSampleBufferGetImageBuffer(sampleBuffer), sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              attachments.first?[.status] as? Int == SCFrameStatus.complete.rawValue else { return }
        lock.lock(); self.frame = frame; count += 1; lock.unlock()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.lock(); self.error = error.localizedDescription; lock.unlock() }
    func render(context: CIContext, queue: MTLCommandQueue, texture: MTLTexture, slots: DispatchSemaphore) {
        guard slots.wait(timeout: .now()) == .success else { return }
        lock.lock(); let frame = self.frame; lock.unlock()
        guard let frame, let command = queue.makeCommandBuffer() else { slots.signal(); return }
        let image = CIImage(cvPixelBuffer: frame)
        context.render(image, to: texture, commandBuffer: command, bounds: image.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        command.addCompletedHandler { _ in slots.signal() }; command.commit()
        lock.lock(); rendered += 1; lock.unlock()
    }
    func result() -> [String: Any] { lock.lock(); defer { lock.unlock() }; return ["complete_frames": count, "rendered_frames": rendered, "error": error as Any? ?? NSNull()] }
}
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "list"
if mode == "list" { emit(["displays": displays(), "screen_recording": CGPreflightScreenCaptureAccess()]); exit(0) }
let seconds = args.count > 2 ? Double(args[2]) ?? 20 : 20
let hz = args.count > 3 ? Double(args[3]) ?? 2 : 2
Task {
    do {
        let end = Date(timeIntervalSinceNow: seconds)
        if mode == "cg-query" || mode == "shareable-query" {
            if mode == "shareable-query", !CGPreflightScreenCaptureAccess() { emit(["skipped": "screen_recording_permission_missing"]); exit(0) }
            var count = 0
            while Date() < end {
                if mode == "cg-query" { _ = displays(includeUUID: false) } else { _ = try await SCShareableContent.current }
                count += 1; try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / max(hz, 1)))
            }
            emit(["queries": count]); exit(0)
        }
        guard mode == "capture" || mode == "capture-render" else { throw NSError(domain: "Probe", code: 1) }
        guard CGPreflightScreenCaptureAccess() else { emit(["skipped": "screen_recording_permission_missing"]); exit(0) }
        let id = UInt32(args.count > 4 ? args[4] : "0") ?? 0
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw NSError(domain: "Probe", code: 2) }
        let sink = Frames(); let config = SCStreamConfiguration()
        config.width = display.width; config.height = display.height; config.queueDepth = 3
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false; config.capturesAudio = false; config.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "demo.capture"))
        var timer: DispatchSourceTimer?
        if mode == "capture-render" {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw NSError(domain: "Probe", code: 3) }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: display.width, height: display.height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw NSError(domain: "Probe", code: 4) }
            let context = CIContext(mtlDevice: device); let slots = DispatchSemaphore(value: 2)
            let renderTimer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "demo.render"))
            renderTimer.schedule(deadline: .now(), repeating: .milliseconds(33))
            renderTimer.setEventHandler { sink.render(context: context, queue: queue, texture: texture, slots: slots) }
            renderTimer.resume(); timer = renderTimer
        }
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        timer?.cancel(); try await stream.stopCapture()
        emit(sink.result()); exit(0)
    } catch { emit(["error": error.localizedDescription]); exit(1) }
}
RunLoop.main.run()
