import AppKit
import Foundation

@MainActor
final class EventStreamRecordingControls: NSObject {
    private let panel: NSPanel
    private let timerLabel: NSTextField
    private let startedAt: Date
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private var timer: Timer?

    init(startedAt: Date, onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.startedAt = startedAt
        self.onStop = onStop
        self.onCancel = onCancel

        let size = NSSize(width: 520, height: 54)
        self.panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.timerLabel = NSTextField(labelWithString: "00:00")

        super.init()

        configurePanel(size: size)
        configureContent(size: size)
    }

    func show() {
        updateElapsedTime()
        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(updateElapsedTime),
            userInfo: nil,
            repeats: true
        )
        panel.orderFrontRegardless()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    func performControlButtonForTesting(title: String) -> Bool {
        guard let contentView = panel.contentView,
              let button = firstButton(in: contentView, title: title)
        else {
            return false
        }

        button.performClick(nil)
        return true
    }

    private func configurePanel(size: NSSize) {
        panel.title = "Record & Replay Recording Controls"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        panel.setFrame(eventStreamRecordingControlsFrame(panelSize: size, visibleFrame: screenFrame), display: false)
    }

    private func configureContent(size: NSSize) {
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true

        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.setContentHuggingPriority(.required, for: .horizontal)
        dot.setContentHuggingPriority(.required, for: .vertical)

        let titleLabel = NSTextField(labelWithString: "Record & Replay is recording your actions")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timerLabel.textColor = .secondaryLabelColor
        timerLabel.alignment = .right
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(handleStop))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.toolTip = "Stop recording"

        let discardButton = NSButton(title: "Discard", target: self, action: #selector(handleCancel))
        discardButton.translatesAutoresizingMaskIntoConstraints = false
        discardButton.bezelStyle = .rounded
        discardButton.controlSize = .small
        discardButton.toolTip = "Discard recording"

        let stack = NSStackView(views: [dot, titleLabel, timerLabel, doneButton, discardButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        material.addSubview(stack)
        panel.contentView = material

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            timerLabel.widthAnchor.constraint(equalToConstant: 48),
            doneButton.widthAnchor.constraint(equalToConstant: 74),
            discardButton.widthAnchor.constraint(equalToConstant: 86),
            stack.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            stack.topAnchor.constraint(equalTo: material.topAnchor),
            stack.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
    }

    private func firstButton(in view: NSView, title: String) -> NSButton? {
        if let button = view as? NSButton, button.title == title {
            return button
        }

        for subview in view.subviews {
            if let button = firstButton(in: subview, title: title) {
                return button
            }
        }

        return nil
    }

    @objc
    private func handleStop() {
        onStop()
    }

    @objc
    private func handleCancel() {
        onCancel()
    }

    @objc
    private func updateElapsedTime() {
        let elapsed = max(Int(Date().timeIntervalSince(startedAt)), 0)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        timerLabel.stringValue = String(format: "%02d:%02d", minutes, seconds)
    }
}

func eventStreamRecordingControlsFrame(
    panelSize: NSSize,
    visibleFrame: NSRect,
    topInset: CGFloat = 18
) -> NSRect {
    let proposedX = visibleFrame.midX - panelSize.width / 2
    let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
    let originX = min(max(proposedX, visibleFrame.minX), maxX)
    let proposedY = visibleFrame.maxY - panelSize.height - topInset
    let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
    let originY = min(max(proposedY, visibleFrame.minY), maxY)
    return NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize)
}
