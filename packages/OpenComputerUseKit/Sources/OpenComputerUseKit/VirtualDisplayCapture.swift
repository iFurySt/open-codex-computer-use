import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
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
    private var cursorOverlay: VirtualDisplayCursorOverlay?
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
    /// Last action target in normalized display coordinates; the captured window animates it.
    public func cursorPoint() -> CGPoint? { lock.lock(); defer { lock.unlock() }; return cursor }
    func setCursor(_ point: CGPoint?) {
        lock.lock(); cursor = point; let overlay = cursorOverlay; lock.unlock()
        // Never synchronously wait for AppKit while holding the registry operation lock.
        DispatchQueue.main.async { overlay?.setTarget(point) }
    }
    private func installOverlay(_ overlay: VirtualDisplayCursorOverlay, token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return false }
        cursorOverlay = overlay; return true
    }
    private func install(_ stream: SCStream, token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return false }
        self.stream = stream; return true
    }
    @discardableResult
    func start(displayID: UInt32, configuration: VirtualDisplayConfiguration) throws -> Bool {
        if isRunning { return true }
        lock.lock(); captureError = nil; cursor = nil; generation += 1; let token = generation; lock.unlock()
        let result: SCStream?
        do { result = try BlockingAsyncBridge.run(timeout: 8) { [self] in
            let overlay = try await MainActor.run { try VirtualDisplayCursorOverlay(displayID: displayID) }
            guard installOverlay(overlay, token: token) else {
                await MainActor.run { overlay.close() }; throw CancellationError()
            }
            let windowID = await MainActor.run { overlay.windowID }
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
            let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard let cursorWindow = content.windows.first(where: { $0.windowID == windowID && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else {
                throw ComputerUseError.message("Virtual display cursor window was not available to ScreenCaptureKit")
            }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [cursorWindow])
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
        if result == nil { stop() }
        return result != nil
    }
    public func stop() {
        lock.lock(); let old = stream; let overlay = cursorOverlay; cursorOverlay = nil; stream = nil; pixelBuffer = nil; cursor = nil; frameDate = nil; generation += 1; lock.unlock()
        // Close before the holder can unplug the display and migrate this window
        // onto a physical screen. Never hold the capture lock across AppKit work.
        VisualCursorSupport.performOnMain { overlay?.close() }
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
        lock.lock()
        guard self.stream === stream else { lock.unlock(); return }
        self.stream = nil; pixelBuffer = nil; cursor = nil; frameDate = nil
        let overlay = cursorOverlay; cursorOverlay = nil
        captureError = "Display capture stopped: \(error.localizedDescription)"
        lock.unlock()
        DispatchQueue.main.async { overlay?.close() }
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
    public var originalSize = false {
        didSet { if oldValue != originalSize { viewport.reset(); dragPoint = nil } }
    }
    private var viewport = VirtualDisplayViewport()
    private var dragPoint: CGPoint?
    private var backingScale: CGFloat { drawableSize.width / max(bounds.width, 1) }
    private var frameSize: CGSize? {
        capture.latestFrame().map { CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) }
    }
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
        layer?.masksToBounds = true
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    public override func magnify(with event: NSEvent) {
        zoom(by: max(1 + event.magnification, 0.05), at: convert(event.locationInWindow, from: nil))
    }
    public override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas || !event.phase.isEmpty || !event.momentumPhase.isEmpty {
            // Gesture deltas already respect the user's natural-scrolling setting.
            // Convert the vertical scroll axis to this unflipped AppKit view.
            pan(by: CGPoint(x: event.scrollingDeltaX, y: -event.scrollingDeltaY))
            return
        }
        let delta = min(max(event.scrollingDeltaY, -50), 50)
        zoom(by: exp(delta * 0.10), at: convert(event.locationInWindow, from: nil))
    }
    private func zoom(by factor: CGFloat, at point: CGPoint) {
        guard let size = frameSize else { return }
        viewport.magnify(by: factor, at: point, image: size, view: bounds.size, originalSize: originalSize, backingScale: backingScale)
        needsDisplay = true
    }
    private func pan(by delta: CGPoint) {
        guard let size = frameSize else { return }
        viewport.drag(by: delta, image: size, view: bounds.size, originalSize: originalSize, backingScale: backingScale)
        needsDisplay = true
    }
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { viewport.reset(); dragPoint = nil }
        else { dragPoint = convert(event.locationInWindow, from: nil) }
        needsDisplay = true
    }
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let old = dragPoint {
            pan(by: CGPoint(x: point.x - old.x, y: point.y - old.y))
        }
        dragPoint = point; needsDisplay = true
    }
    public override func mouseUp(with event: NSEvent) { dragPoint = nil }
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let command = commandQueue?.makeCommandBuffer() else { return }
        guard let buffer = capture.latestFrame(), let imageContext else {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = clearColor
            command.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            command.present(drawable); command.commit(); return
        }
        let image = CIImage(cvPixelBuffer: buffer)
        let output = CGRect(origin: .zero, size: drawableSize)
        viewport.constrain(image: image.extent.size, view: bounds.size, originalSize: originalSize, backingScale: backingScale)
        let rect = viewport.imageRect(image: image.extent.size, view: bounds.size, originalSize: originalSize, backingScale: backingScale)
        let scale = rect.width * backingScale / image.extent.width
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: rect.minX * backingScale, ty: rect.minY * backingScale)
        let background = CIImage(color: .black).cropped(to: output)
        imageContext.render(image.transformed(by: transform).composited(over: background), to: drawable.texture, commandBuffer: command, bounds: output, colorSpace: CGColorSpaceCreateDeviceRGB())
        command.present(drawable); command.commit()

    }
}

/// Reuses OBU's cursor-chat.png without altering its artwork.
/// Source and license: Resources/README.md and Resources/OBU-LICENSE.txt.
enum BrowserUseCursorArtwork {
    static let size = CGSize(width: 23, height: 24)
    // OBU uses a 24px container centered at the action point, an image offset
    // of (12, -2.5), image rotation +44°, and neutral container rotation -44°.
    // The rotations cancel; convert that CSS hotspot to AppKit layer space.
    static let anchorPoint = CGPoint(
        x: 14.5 * sin(44 * .pi / 180) / size.width,
        y: 1 - 14.5 * cos(44 * .pi / 180) / size.height
    )
    static let image: CGImage? = {
        guard let url = Bundle.module.url(forResource: "cursor-chat", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
}
