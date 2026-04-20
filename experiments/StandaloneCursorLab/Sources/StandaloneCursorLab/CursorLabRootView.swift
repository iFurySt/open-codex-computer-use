import AppKit
import QuartzCore
import SwiftUI

private enum CursorLabPalette {
    static let ink = Color(red: 0.18, green: 0.19, blue: 0.24)
    static let main = Color(red: 0.89, green: 0.89, blue: 0.90)
    static let mainSoft = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let mainMuted = Color(red: 0.82, green: 0.81, blue: 0.85)
    static let mainStrong = Color(red: 0.63, green: 0.62, blue: 0.68)
}

struct CursorLabRootView: View {
    @State private var start = CGPoint(x: 220, y: 440)
    @State private var end = CGPoint(x: 860, y: 260)
    @State private var debugEnabled = true
    @State private var mailEnabled = false
    @State private var clickEnabled = true
    @StateObject private var model = CursorLabViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CursorLabBackground()

                CursorLabCanvas(
                    start: $start,
                    end: $end,
                    debugEnabled: debugEnabled,
                    showClickPulse: clickEnabled,
                    model: model
                )
                .onAppear {
                    model.configure(start: start, end: end, canvasSize: proxy.size)
                    model.replay(from: start, to: end)
                }
                .onChange(of: proxy.size) { _, newSize in
                    clampPoints(to: newSize)
                    model.configure(start: start, end: end, canvasSize: newSize)
                }
                .onChange(of: start) { _, newValue in
                    model.updateStart(newValue)
                }
                .onChange(of: end) { _, newValue in
                    model.queueMove(to: newValue)
                }
            }
            .overlay(alignment: .topLeading) {
                controlPanel
                    .padding(24)
            }
            .overlay(alignment: .topTrailing) {
                togglePanel
                    .padding(24)
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HEADING-DRIVEN MOTION")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(CursorLabPalette.ink.opacity(0.82))
                .tracking(0.8)

            Text(model.selectionLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(CursorLabPalette.ink.opacity(0.68))
                .tracking(0.6)

            Text(model.selectionMetricsLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(CursorLabPalette.ink.opacity(0.52))

            Button("REPLAY") {
                model.replay(from: start, to: end)
            }
            .buttonStyle(CursorActionButtonStyle())
            .padding(.top, 6)
        }
    }

    private var togglePanel: some View {
        VStack(alignment: .trailing, spacing: 12) {
            CursorToggleRow(title: "DEBUG", isOn: $debugEnabled)
            CursorToggleRow(title: "MAIL", isOn: $mailEnabled)
            CursorToggleRow(title: "CLICK", isOn: $clickEnabled)
        }
    }

    private func clampPoints(to size: CGSize) {
        let inset: CGFloat = 80
        start.x = min(max(start.x, inset), size.width - inset)
        start.y = min(max(start.y, inset), size.height - inset)
        end.x = min(max(end.x, inset), size.width - inset)
        end.y = min(max(end.y, inset), size.height - inset)
    }
}

@MainActor
final class CursorLabViewModel: ObservableObject {
    @Published private(set) var path = CursorMotionPath(
        start: CGPoint(x: 220, y: 440),
        end: CGPoint(x: 860, y: 260)
    )
    @Published private(set) var candidates: [CursorMotionCandidate] = []
    @Published private(set) var selectedCandidateID: String?
    @Published private(set) var currentState = CursorMotionState(
        point: CGPoint(x: 220, y: 440),
        rotation: CursorGlyphCalibration.restingRotation,
        displayRotation: CursorGlyphCalibration.restingRotation,
        cursorBodyOffset: .zero,
        fogOffset: .zero,
        fogOpacity: CursorVisualDynamicsConfiguration.officialInspired.fogOpacityBase,
        fogScale: 1,
        trailProgress: 0,
        isSettled: true
    )
    @Published private(set) var clickPulse: CGFloat = 0

    private var simulator = CursorMotionSimulator(
        start: CGPoint(x: 220, y: 440),
        end: CGPoint(x: 860, y: 260),
        parameters: .default
    )
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var previewRemaining: CGFloat = 0
    private var queuedTarget = CGPoint(x: 860, y: 260)
    private var canvasBounds = CGRect(x: 0, y: 0, width: 1080, height: 720)

    var selectionLabel: String {
        guard let selectedCandidate else {
            return "\(candidates.count) HEADING-DRIVEN CANDIDATES"
        }

        let family = selectedCandidate.kind.rawValue.uppercased()
        return "\(candidates.count) CANDIDATES • \(family) • \(selectedCandidate.id.uppercased())"
    }

    var selectionMetricsLabel: String {
        guard let selectedCandidate else {
            return "heading-aware turn / brake / orbit / direct families"
        }

        let measurement = selectedCandidate.measurement
        return String(
            format: "score %.2f • len %.1f • turn %.2f",
            Double(selectedCandidate.score),
            Double(measurement.length),
            Double(measurement.totalTurn)
        )
    }

    private var selectedCandidate: CursorMotionCandidate? {
        candidates.first(where: { $0.id == selectedCandidateID }) ?? candidates.first
    }

    func configure(start: CGPoint, end: CGPoint, canvasSize: CGSize) {
        queuedTarget = end
        canvasBounds = CGRect(origin: .zero, size: canvasSize)
        let selection = bestSelection(
            from: start,
            to: end,
            startRotation: CursorGlyphCalibration.restingRotation
        )
        candidates = selection.candidates
        selectedCandidateID = selection.selected.id
        path = selection.selected.path
        currentState = simulator.snap(to: start, path: selection.selected.path)
        clickPulse = 0
        previewRemaining = 0
        lastTimestamp = nil
        ensureDisplayLink()
    }

    func updateStart(_ value: CGPoint) {
        let selection = bestSelection(
            from: value,
            to: queuedTarget,
            startRotation: currentState.rotation
        )
        candidates = selection.candidates
        selectedCandidateID = selection.selected.id
        path = selection.selected.path
        currentState = simulator.snap(to: value, path: selection.selected.path)
        clickPulse = 0
    }

    func queueMove(to value: CGPoint) {
        scheduleMove(from: currentState.point, to: value, snapOrigin: false)
    }

    func replay(from origin: CGPoint, to target: CGPoint) {
        scheduleMove(from: origin, to: target, snapOrigin: true)
    }

    private func scheduleMove(from origin: CGPoint, to target: CGPoint, snapOrigin: Bool) {
        queuedTarget = target
        let startRotation = snapOrigin ? CursorGlyphCalibration.restingRotation : currentState.rotation

        let selection = bestSelection(from: origin, to: target, startRotation: startRotation)
        candidates = selection.candidates
        selectedCandidateID = selection.selected.id
        path = selection.selected.path

        if snapOrigin {
            currentState = simulator.snap(to: origin, path: selection.selected.path)
        }

        clickPulse = 0
        previewRemaining = 0.24
        lastTimestamp = nil
        ensureDisplayLink()
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else {
            return
        }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            return
        }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            guard let userInfo else {
                return kCVReturnSuccess
            }

            let viewModel = Unmanaged<CursorLabViewModel>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in
                viewModel.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        displayLink = link
        CVDisplayLinkStart(link)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(lastTimestamp.map { now - $0 } ?? (1.0 / 60.0))
        lastTimestamp = now

        if previewRemaining > 0 {
            previewRemaining -= dt
            if previewRemaining <= 0 {
                startSelectedCandidateAnimation()
            }
            return
        }

        currentState = simulator.step(deltaTime: dt)
        path = simulator.path

        if currentState.trailProgress > 0.94, currentState.isSettled == false {
            let pulseProgress = min(max((currentState.trailProgress - 0.94) / 0.06, 0), 1)
            clickPulse = sin(pulseProgress * .pi)
        } else {
            clickPulse = 0
        }
    }

    private func startSelectedCandidateAnimation() {
        guard let selectedCandidate else {
            return
        }

        path = selectedCandidate.path
        simulator.begin(path: selectedCandidate.path, measurement: selectedCandidate.measurement)
    }

    private func bestSelection(
        from start: CGPoint,
        to end: CGPoint,
        startRotation: CGFloat
    ) -> (candidates: [CursorMotionCandidate], selected: CursorMotionCandidate) {
        let selectionBounds = syntheticMotionBounds(from: start, to: end)
        let candidates = HeadingDrivenCursorMotionModel.makeCandidates(
            start: start,
            end: end,
            bounds: selectionBounds,
            startForward: headingVector(rotation: startRotation),
            endForward: headingVector(rotation: CursorGlyphCalibration.restingRotation)
        )
        let defaultCandidate = HeadingDrivenCursorMotionModel.chooseBestCandidate(from: candidates)
            ?? CursorMotionCandidate(
                id: "fallback-direct",
                kind: .base,
                side: 0,
                tableAScale: nil,
                tableBScale: nil,
                path: CursorMotionPath(start: start, end: end, curveScale: 0),
                measurement: CursorMotionPath(start: start, end: end, curveScale: 0).measure(bounds: selectionBounds),
                score: 0
            )

        return (candidates, defaultCandidate)
    }

    private func syntheticMotionBounds(from start: CGPoint, to end: CGPoint) -> CGRect? {
        guard canvasBounds.isNull == false else {
            return nil
        }

        let distance = hypot(end.x - start.x, end.y - start.y)
        let margin = min(max(distance * 0.14, 90), 180)
        let corridorBounds = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -margin, dy: -margin)

        let resolved = canvasBounds.intersection(corridorBounds)
        if resolved.isNull || resolved.isEmpty {
            return canvasBounds
        }

        return resolved
    }

    private func headingVector(rotation: CGFloat) -> CGVector {
        let angle = CursorGlyphCalibration.neutralHeading + rotation
        return CGVector(dx: cos(angle), dy: sin(angle))
    }
}

private struct CursorLabCanvas: View {
    @Binding var start: CGPoint
    @Binding var end: CGPoint
    let debugEnabled: Bool
    let showClickPulse: Bool
    @ObservedObject var model: CursorLabViewModel

    var body: some View {
        ZStack {
            if debugEnabled {
                persistentPathLayer
                debugCandidateLayer
                Circle()
                    .fill(CursorLabPalette.mainStrong)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.52), lineWidth: 8))
                    .position(end)
                    .allowsHitTesting(false)
            }

            CursorGlyph(
                rotation: model.currentState.displayRotation,
                cursorBodyOffset: model.currentState.cursorBodyOffset,
                fogOffset: model.currentState.fogOffset,
                fogOpacity: model.currentState.fogOpacity,
                fogScale: model.currentState.fogScale,
                clickPulse: showClickPulse ? model.clickPulse : 0
            )
            .position(model.currentState.point)
            .allowsHitTesting(false)

            CanvasClickCapture { location in
                end = location
            }
        }
    }

    private var persistentPathLayer: some View {
        Canvas { context, _ in
            let selectedPath = Path(model.path.cgPath)
            context.stroke(
                selectedPath,
                with: .linearGradient(
                    Gradient(colors: [
                        CursorLabPalette.ink.opacity(0.18),
                        CursorLabPalette.mainStrong.opacity(0.24),
                    ]),
                    startPoint: model.path.start,
                    endPoint: model.path.end
                ),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )

            let livePath = trimmedPath(progress: model.currentState.trailProgress)
            context.stroke(
                livePath,
                with: .linearGradient(
                    Gradient(colors: [
                        CursorLabPalette.ink.opacity(0.72),
                        CursorLabPalette.mainStrong.opacity(0.92),
                    ]),
                    startPoint: model.path.start,
                    endPoint: model.path.end
                ),
                style: StrokeStyle(lineWidth: 5.2, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    private var debugCandidateLayer: some View {
        Canvas { context, _ in
            for (index, candidate) in model.candidates.enumerated() where candidate.id != model.selectedCandidateID {
                let path = Path(candidate.path.cgPath)
                let strokeColor = CursorLabPalette.ink.opacity(max(0.08, 0.20 - CGFloat(index) * 0.016))
                context.stroke(
                    path,
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: 1.25, dash: [6, 8], dashPhase: CGFloat(index) * 2)
                )
            }

            let handleStroke = StrokeStyle(lineWidth: 1.0, dash: [4, 6])
            let handleColor = CursorLabPalette.ink.opacity(0.18)
            context.stroke(handlePath, with: .color(handleColor), style: handleStroke)

            for point in debugPoints {
                let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(CursorLabPalette.ink.opacity(0.40)))
            }

            if let arc = model.path.arc {
                let rect = CGRect(x: arc.x - 5, y: arc.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(CursorLabPalette.mainStrong.opacity(0.78)))
            }

            if let selectedCandidate = model.candidates.first(where: { $0.id == model.selectedCandidateID }) {
                let labelPoint = CGPoint(
                    x: selectedCandidate.path.point(at: 0.54).x + 18,
                    y: selectedCandidate.path.point(at: 0.54).y - 16
                )
                let text = Text("SELECTED")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(CursorLabPalette.ink.opacity(0.78))
                context.draw(text, at: labelPoint, anchor: .leading)
            }
        }
        .allowsHitTesting(false)
    }

    private var handlePath: Path {
        Path { path in
            if let startControl = model.path.startControl {
                path.move(to: model.path.start)
                path.addLine(to: startControl)
            }

            if let arc = model.path.arc {
                if let arcIn = model.path.arcIn {
                    path.move(to: arc)
                    path.addLine(to: arcIn)
                }
                if let arcOut = model.path.arcOut {
                    path.move(to: arc)
                    path.addLine(to: arcOut)
                }
            }

            if let endControl = model.path.endControl {
                path.move(to: model.path.end)
                path.addLine(to: endControl)
            }
        }
    }

    private var debugPoints: [CGPoint] {
        [
            model.path.startControl,
            model.path.arcIn,
            model.path.arcOut,
            model.path.endControl,
        ].compactMap { $0 }
    }

    private func trimmedPath(progress: CGFloat) -> Path {
        Path(model.path.cgPath).trimmedPath(from: 0, to: max(0.001, min(progress, 1)))
    }
}

private struct CanvasClickCapture: NSViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        let view = ClickCaptureView()
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: ClickCaptureView, context: Context) {
        nsView.onTap = onTap
    }
}

private final class ClickCaptureView: NSView {
    var onTap: ((CGPoint) -> Void)?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onTap?(location)
    }
}

private struct CursorGlyph: View {
    let rotation: CGFloat
    let cursorBodyOffset: CGVector
    let fogOffset: CGVector
    let fogOpacity: CGFloat
    let fogScale: CGFloat
    let clickPulse: CGFloat

    var body: some View {
        ZStack {
            SynthesizedCursorGlyphRepresentable(
                rotation: rotation,
                cursorBodyOffset: cursorBodyOffset,
                fogOffset: fogOffset,
                fogOpacity: fogOpacity,
                fogScale: fogScale,
                clickProgress: clickPulse
            )
            .frame(
                width: SynthesizedCursorOverlayMetrics.windowSize.width,
                height: SynthesizedCursorOverlayMetrics.windowSize.height
            )
        }
        .frame(
            width: SynthesizedCursorOverlayMetrics.windowSize.width,
            height: SynthesizedCursorOverlayMetrics.windowSize.height
        )
    }
}

private struct SynthesizedCursorGlyphRepresentable: NSViewRepresentable {
    let rotation: CGFloat
    let cursorBodyOffset: CGVector
    let fogOffset: CGVector
    let fogOpacity: CGFloat
    let fogScale: CGFloat
    let clickProgress: CGFloat

    func makeNSView(context: Context) -> SynthesizedCursorGlyphView {
        SynthesizedCursorGlyphView(
            frame: CGRect(
                origin: .zero,
                size: SynthesizedCursorOverlayMetrics.windowSize
            )
        )
    }

    func updateNSView(_ nsView: SynthesizedCursorGlyphView, context: Context) {
        nsView.rotation = rotation
        nsView.cursorBodyOffset = cursorBodyOffset
        nsView.fogOffset = fogOffset
        nsView.fogOpacity = fogOpacity
        nsView.fogScale = fogScale
        nsView.clickProgress = clickProgress
    }
}

private struct CursorToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var accent: Color = CursorLabPalette.mainStrong

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(CursorLabPalette.ink.opacity(0.82))
                .tracking(0.8)

            Toggle("", isOn: $isOn)
                .toggleStyle(CursorToggleStyle(accent: accent))
                .labelsHidden()
        }
    }
}

private struct CursorToggleStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(configuration.isOn ? accent : CursorLabPalette.ink.opacity(0.18))
            .frame(width: 38, height: 20)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .padding(2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                configuration.isOn.toggle()
            }
    }
}

private struct CursorActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(CursorLabPalette.ink.opacity(configuration.isPressed ? 0.16 : 0.10))
            .foregroundStyle(CursorLabPalette.ink.opacity(0.88))
            .clipShape(Capsule())
    }
}

private struct CursorLabBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                CursorLabPalette.mainSoft,
                CursorLabPalette.main,
                CursorLabPalette.mainMuted,
                Color(red: 0.72, green: 0.73, blue: 0.79),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Canvas { context, size in
                let blobs: [(CGPoint, CGSize, Color)] = [
                    (CGPoint(x: size.width * 0.18, y: size.height * 0.20), CGSize(width: 360, height: 620), Color.white.opacity(0.28)),
                    (CGPoint(x: size.width * 0.55, y: size.height * 0.58), CGSize(width: 420, height: 720), CursorLabPalette.main.opacity(0.36)),
                    (CGPoint(x: size.width * 0.82, y: size.height * 0.26), CGSize(width: 360, height: 520), CursorLabPalette.mainStrong.opacity(0.16)),
                ]

                for blob in blobs {
                    let rect = CGRect(origin: .zero, size: blob.1)
                        .offsetBy(dx: blob.0.x - blob.1.width / 2, dy: blob.0.y - blob.1.height / 2)
                    context.addFilter(.blur(radius: 48))
                    context.fill(Path(ellipseIn: rect), with: .color(blob.2))
                }
            }
        }
        .ignoresSafeArea()
    }
}
