import AppKit
import Carbon.HIToolbox
import Foundation
import OpenComputerUseKit

@MainActor
final class KeyCaptureView: NSView {
    var onKey: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let value = debugKeyName(for: event)
        onKey?(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemTeal.setFill()
        dirtyRect.fill()

        let text = "Click here, then use press_key"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )

        if window?.firstResponder === self {
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
            path.lineWidth = 3
            path.stroke()
        }
    }
}

@MainActor
final class DragPadView: NSView {
    var onDrag: ((String) -> Void)?
    private var dragStart: CGPoint?

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let start = dragStart ?? current
        onDrag?("from (\(Int(start.x)), \(Int(start.y))) to (\(Int(current.x)), \(Int(current.y)))")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill()
        dirtyRect.fill()

        let text = "Drag inside this pad"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}

@MainActor
final class FixtureAppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let incrementButton = NSButton(title: "Increment Counter", target: nil, action: nil)
    private let counterLabel = NSTextField(labelWithString: "Counter: 0")
    private let inputField = NSTextField(string: "seed")
    private let keyLabel = NSTextField(labelWithString: "Last key: none")
    private let scrollLabel = NSTextField(labelWithString: "Scroll offset: 0")
    private let dragLabel = NSTextField(labelWithString: "Last drag: none")
    private let keyCaptureView = KeyCaptureView(frame: NSRect(x: 0, y: 0, width: 320, height: 72))
    private let dragPadView = DragPadView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
    private var scrollView: NSScrollView!
    private var counter = 0
    private weak var observedScrollView: NSScrollView?
    private var commandObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        startCommandObserver()
        updateExportedState()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let commandObserver {
            DistributedNotificationCenter.default().removeObserver(commandObserver)
        }
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 160, y: 180, width: 640, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenComputerUseFixture"
        window.setAccessibilityIdentifier("fixture-window")
        window.delegate = self

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let descriptionLabel = NSTextField(wrappingLabelWithString: "Fixture app for safe computer-use smoke tests.")
        incrementButton.target = self
        incrementButton.action = #selector(handleIncrement)
        incrementButton.bezelStyle = .rounded
        incrementButton.setAccessibilityIdentifier("fixture-increment")

        counterLabel.setAccessibilityIdentifier("fixture-counter-label")

        inputField.delegate = self
        inputField.setAccessibilityIdentifier("fixture-input")

        keyLabel.setAccessibilityIdentifier("fixture-key-label")
        keyCaptureView.setAccessibilityIdentifier("fixture-key-capture")
        keyCaptureView.onKey = { [weak self] value in
            self?.keyLabel.stringValue = "Last key: \(value)"
            self?.keyCaptureView.needsDisplay = true
            self?.updateExportedState()
        }

        scrollLabel.setAccessibilityIdentifier("fixture-scroll-status")
        scrollView = makeScrollView()
        scrollView.setAccessibilityIdentifier("fixture-scroll-view")

        dragLabel.setAccessibilityIdentifier("fixture-drag-status")
        dragPadView.setAccessibilityIdentifier("fixture-drag-pad")
        dragPadView.onDrag = { [weak self] value in
            self?.dragLabel.stringValue = "Last drag: \(value)"
            self?.updateExportedState()
        }

        let stack = NSStackView(views: [
            descriptionLabel,
            incrementButton,
            counterLabel,
            NSTextField(labelWithString: "Editable Text Field"),
            inputField,
            keyLabel,
            keyCaptureView,
            scrollLabel,
            scrollView,
            dragLabel,
            dragPadView,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            keyCaptureView.widthAnchor.constraint(equalToConstant: 320),
            keyCaptureView.heightAnchor.constraint(equalToConstant: 72),
            dragPadView.widthAnchor.constraint(equalToConstant: 320),
            dragPadView.heightAnchor.constraint(equalToConstant: 120),
            scrollView.widthAnchor.constraint(equalToConstant: 520),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
            inputField.widthAnchor.constraint(equalToConstant: 320),
        ])

        window.makeKeyAndOrderFront(nil)
    }

    @objc
    private func handleIncrement() {
        counter += 1
        counterLabel.stringValue = "Counter: \(counter)"
        updateExportedState()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field == inputField {
            inputField.stringValue = field.stringValue
            updateExportedState()
        }
    }

    @objc
    private func handleScrollBoundsChanged(_ notification: Notification) {
        guard let scrollView = observedScrollView else {
            return
        }

        let offset = Int(scrollView.contentView.bounds.origin.y)
        scrollLabel.stringValue = "Scroll offset: \(offset)"
        updateExportedState()
    }

    func windowDidMove(_ notification: Notification) {
        updateExportedState()
    }

    func windowDidResize(_ notification: Notification) {
        updateExportedState()
    }

    private func makeScrollView() -> NSScrollView {
        let documentView = NSStackView()
        documentView.orientation = .vertical
        documentView.alignment = .leading
        documentView.spacing = 8
        documentView.translatesAutoresizingMaskIntoConstraints = false

        for index in 1...40 {
            let label = NSTextField(labelWithString: "Scrollable row \(index)")
            documentView.addArrangedSubview(label)
        }

        let clipView = NSClipView()
        clipView.postsBoundsChangedNotifications = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.contentView = clipView
        scrollView.documentView = documentView
        observedScrollView = scrollView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        return scrollView
    }

    private func startCommandObserver() {
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: FixtureBridge.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let payload = notification.userInfo?["payload"] as? String,
                let data = payload.data(using: .utf8),
                let command = try? JSONDecoder().decode(FixtureCommand.self, from: data)
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.handle(command)
            }
        }
    }

    private func handle(_ command: FixtureCommand) {
        switch (command.kind, command.identifier) {
        case ("set_value", "fixture-input"):
            inputField.stringValue = command.value ?? ""
            updateExportedState()
        case ("click", "fixture-increment"):
            handleIncrement()
        case ("click", "fixture-input"):
            window.makeFirstResponder(inputField)
            updateExportedState()
        case ("click", "fixture-key-capture"):
            window.makeFirstResponder(keyCaptureView)
            keyCaptureView.needsDisplay = true
            updateExportedState()
        case ("scroll", "fixture-scroll-view"):
            let delta = CGFloat(120 * (command.pages ?? 1))
            let direction = command.direction ?? "down"
            let current = scrollView.contentView.bounds.origin
            let nextY = switch direction {
            case "up":
                max(0, current.y - delta)
            case "down":
                current.y + delta
            default:
                current.y
            }
            scrollView.contentView.scroll(to: CGPoint(x: current.x, y: nextY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateExportedState()
        case ("drag", "fixture-drag-pad"):
            let startX = Int(command.x ?? 0)
            let startY = Int(command.y ?? 0)
            let endX = Int(command.toX ?? 0)
            let endY = Int(command.toY ?? 0)
            dragLabel.stringValue = "Last drag: from (\(startX), \(startY)) to (\(endX), \(endY))"
            updateExportedState()
        case ("type_text", "fixture-input"):
            inputField.stringValue += command.value ?? ""
            window.makeFirstResponder(inputField)
            updateExportedState()
        case ("press_key", "fixture-key-capture"):
            keyLabel.stringValue = "Last key: \(command.value ?? "unknown")"
            window.makeFirstResponder(keyCaptureView)
            keyCaptureView.needsDisplay = true
            updateExportedState()
        default:
            break
        }
    }

    private func updateExportedState() {
        guard let contentView = window.contentView else {
            return
        }

        let state = FixtureAppState(
            windowTitle: window.title,
            windowBounds: FixtureRect(rect: windowBoundsInQuartzCoordinates()),
            focusedIdentifier: focusedIdentifier(),
            elements: [
                element(identifier: "fixture-window", index: 0, role: "standard window", title: window.title, value: nil, actions: ["Raise"], rect: CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)),
                element(identifier: "fixture-increment", index: 1, role: "button", title: incrementButton.title, value: nil, actions: [], rect: localRect(for: incrementButton, in: contentView)),
                element(identifier: "fixture-counter-label", index: 2, role: "static text", title: nil, value: counterLabel.stringValue, actions: [], rect: localRect(for: counterLabel, in: contentView)),
                element(identifier: "fixture-input", index: 3, role: "text field", title: nil, value: inputField.stringValue, actions: [], rect: localRect(for: inputField, in: contentView)),
                element(identifier: "fixture-key-label", index: 4, role: "static text", title: nil, value: keyLabel.stringValue, actions: [], rect: localRect(for: keyLabel, in: contentView)),
                element(identifier: "fixture-key-capture", index: 5, role: "group", title: "Key Capture", value: nil, actions: [], rect: localRect(for: keyCaptureView, in: contentView)),
                element(identifier: "fixture-scroll-status", index: 6, role: "static text", title: nil, value: scrollLabel.stringValue, actions: [], rect: localRect(for: scrollLabel, in: contentView)),
                element(identifier: "fixture-scroll-view", index: 7, role: "scroll area", title: nil, value: nil, actions: ["Scroll Up", "Scroll Down"], rect: localRect(for: scrollView, in: contentView)),
                element(identifier: "fixture-drag-status", index: 8, role: "static text", title: nil, value: dragLabel.stringValue, actions: [], rect: localRect(for: dragLabel, in: contentView)),
                element(identifier: "fixture-drag-pad", index: 9, role: "group", title: "Drag Pad", value: nil, actions: [], rect: localRect(for: dragPadView, in: contentView)),
            ]
        )

        try? FixtureBridge.writeState(state)
    }

    private func element(identifier: String, index: Int, role: String, title: String?, value: String?, actions: [String], rect: CGRect) -> FixtureElementState {
        FixtureElementState(
            identifier: identifier,
            index: index,
            role: role,
            title: title,
            value: value,
            actions: actions,
            frame: FixtureRect(rect: rect)
        )
    }

    private func focusedIdentifier() -> String? {
        if window.firstResponder === keyCaptureView {
            return "fixture-key-capture"
        }

        if window.firstResponder === inputField.currentEditor() || window.firstResponder === inputField {
            return "fixture-input"
        }

        return nil
    }

    private func windowBoundsInQuartzCoordinates() -> CGRect {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = window.frame
        let quartzY = screen.frame.maxY - frame.maxY
        return CGRect(x: frame.minX, y: quartzY, width: frame.width, height: frame.height)
    }

    private func localRect(for view: NSView, in contentView: NSView) -> CGRect {
        let rectInWindow = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let quartzWindow = windowBoundsInQuartzCoordinates()
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let quartzY = screen.frame.maxY - screenRect.maxY
        return CGRect(
            x: screenRect.minX - window.frame.minX,
            y: quartzY - quartzWindow.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}

private func debugKeyName(for event: NSEvent) -> String {
    switch Int(event.keyCode) {
    case kVK_Return:
        return "Return"
    case kVK_Tab:
        return "Tab"
    case kVK_Space:
        return "Space"
    case kVK_LeftArrow:
        return "Left"
    case kVK_RightArrow:
        return "Right"
    case kVK_UpArrow:
        return "Up"
    case kVK_DownArrow:
        return "Down"
    default:
        return event.charactersIgnoringModifiers?.isEmpty == false ? event.charactersIgnoringModifiers! : "unknown"
    }
}

@main
enum OpenComputerUseFixtureMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = FixtureAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
