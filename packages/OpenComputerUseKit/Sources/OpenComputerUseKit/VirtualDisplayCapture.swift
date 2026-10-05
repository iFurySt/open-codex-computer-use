import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import MetalKit
@preconcurrency import ScreenCaptureKit
import SwiftUI

/// Only the latest complete frame is retained. The consumer renders synchronously
/// before releasing its reference; the stream's buffers must not be queued forever.
public final class VirtualDisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stream: SCStream?
    private var pixelBuffer: CVPixelBuffer?
    private var captureError: String?
    private var generation = 0
    private var frameDate: Date?
    private var cursor: CGPoint?
    private var subscribers: [UUID: @Sendable (CVPixelBuffer, Date) -> Void] = [:]
    private let queue = DispatchQueue(label: "com.ifuryst.ocu.virtual-display.frames")
    public var error: String? { lock.lock(); defer { lock.unlock() }; return captureError }
    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return stream != nil }
    public var latestFrameDate: Date? { lock.lock(); defer { lock.unlock() }; return frameDate }
    public func latestFrame() -> CVPixelBuffer? { lock.lock(); defer { lock.unlock() }; return pixelBuffer }
    /// Invoked on the capture queue; consumers must return promptly and keep at most one frame.
    @discardableResult
    public func subscribeFrames(_ receive: @escaping @Sendable (CVPixelBuffer, Date) -> Void) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = UUID(); subscribers[id] = receive; return id
    }
    public func unsubscribeFrames(_ id: UUID) { lock.lock(); subscribers.removeValue(forKey: id); lock.unlock() }
    public func cursorPoint() -> CGPoint? { lock.lock(); defer { lock.unlock() }; return cursor }
    func setCursor(_ point: CGPoint?) { lock.lock(); cursor = point; lock.unlock() }
    private func install(_ stream: SCStream, token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return false }
        self.stream = stream; return true
    }
    @discardableResult
    func start(displayID: UInt32, configuration: VirtualDisplayConfiguration) throws -> Bool {
        if isRunning { return true }
        lock.lock(); captureError = nil; generation += 1; let token = generation; lock.unlock()
        let result: SCStream?
        do { result = try BlockingAsyncBridge.run(timeout: 8) { [self] in
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = configuration.width * configuration.scale
            config.height = configuration.height * configuration.scale
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
            config.pixelFormat = kCVPixelFormatType_32BGRA; config.scalesToFit = true
            try Task.checkCancellation()
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            guard install(stream, token: token) else { throw CancellationError() }
            try await stream.startCapture()
            if Task.isCancelled { try? await stream.stopCapture(); throw CancellationError() }
            return stream
        }
        } catch { stop(); throw error }
        lock.lock()
        if token == generation { stream = result }
        lock.unlock()
        return result != nil
    }
    public func stop() {
        lock.lock(); let old = stream; stream = nil; pixelBuffer = nil; cursor = nil; frameDate = nil; generation += 1; lock.unlock()
        if let old {
            _ = try? BlockingAsyncBridge.run(timeout: 5) { try await old.stopCapture() }
        }
    }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        guard self.stream === stream else { lock.unlock(); return }
        let timestamp = Date(); pixelBuffer = buffer; frameDate = timestamp
        let receivers = Array(subscribers.values)
        lock.unlock()
        for receive in receivers { receive(buffer, timestamp) }
    }
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); defer { lock.unlock() }
        if self.stream === stream { self.stream = nil; pixelBuffer = nil; captureError = "Display capture stopped: \(error.localizedDescription)" }
    }
}

public struct VirtualDisplayPreview: NSViewRepresentable {
    public var capture: VirtualDisplayCapture
    public var originalSize: Bool
    public init(capture: VirtualDisplayCapture, originalSize: Bool = false) { self.capture = capture; self.originalSize = originalSize }
    public func makeNSView(context: Context) -> VirtualDisplayMetalView { VirtualDisplayMetalView(capture: capture) }
    public func updateNSView(_ view: VirtualDisplayMetalView, context: Context) { view.originalSize = originalSize }
}

public final class VirtualDisplayMetalView: MTKView, MTKViewDelegate {
    private let capture: VirtualDisplayCapture
    private let commandQueue: MTLCommandQueue?
    private let imageContext: CIContext?
    public var originalSize = false
    private let cursorLayer = CAShapeLayer()
    init(capture: VirtualDisplayCapture) {
        self.capture = capture
        let gpu = MTLCreateSystemDefaultDevice()
        commandQueue = gpu?.makeCommandQueue()
        imageContext = gpu.map { CIContext(mtlDevice: $0) }
        super.init(frame: .zero, device: gpu)
        framebufferOnly = false; colorPixelFormat = .bgra8Unorm
        preferredFramesPerSecond = 30; clearColor = MTLClearColorMake(0.04, 0.04, 0.04, 1)
        delegate = self
        wantsLayer = true
        cursorLayer.fillColor = NSColor.white.cgColor; cursorLayer.strokeColor = NSColor.black.cgColor; cursorLayer.lineWidth = 1
        layer?.addSublayer(cursorLayer)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let command = commandQueue?.makeCommandBuffer() else { return }
        guard let buffer = capture.latestFrame(), let imageContext else {
            cursorLayer.isHidden = true
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = clearColor
            command.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            command.present(drawable); command.commit(); return
        }
        let image = CIImage(cvPixelBuffer: buffer)
        let output = CGRect(origin: .zero, size: drawableSize)
        let fit = min(output.width / image.extent.width, output.height / image.extent.height)
        let scale = originalSize ? 1 : fit
        let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: (output.width / scale - image.extent.width) / 2, y: (output.height / scale - image.extent.height) / 2)
        let background = CIImage(color: .black).cropped(to: output)
        imageContext.render(image.transformed(by: transform).composited(over: background), to: drawable.texture, commandBuffer: command, bounds: output, colorSpace: CGColorSpaceCreateDeviceRGB())
        command.present(drawable); command.commit()
        if let point = capture.cursorPoint() {
            let scale = self.originalSize ? 1 : fit
            let factor = drawableSize.width / max(bounds.width, 1)
            let x = (output.width - image.extent.width * scale) / 2 + point.x * image.extent.width * scale
            let y = (output.height - image.extent.height * scale) / 2 + (1 - point.y) * image.extent.height * scale
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0)); path.addLines(between: [CGPoint(x: 0, y: -20), CGPoint(x: 5, y: -15), CGPoint(x: 10, y: -24), CGPoint(x: 14, y: -22), CGPoint(x: 9, y: -13), CGPoint(x: 16, y: -13)]); path.closeSubpath()
            cursorLayer.path = path; cursorLayer.position = CGPoint(x: x / factor, y: y / factor); cursorLayer.isHidden = false
        } else { cursorLayer.isHidden = true }
    }
}
