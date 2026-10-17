import AppKit

/// A separate native AX target, intentionally unrelated to FixtureBridge.
/// Real OCU get_app_state/click calls must traverse Accessibility and SCK.
@MainActor
final class ExternalFixture: NSObject {
    private let window: NSWindow
    private let label = NSTextField(labelWithString: "Counter: 0")
    private var counter = 0
    override init() {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 460, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Locked Use Native Validation"
        window.backgroundColor = .systemBlue
        window.isReleasedWhenClosed = false
        let button = NSButton(title: "Increment Counter", target: self, action: #selector(increment))
        button.setAccessibilityIdentifier("locked-use-validation-increment")
        button.frame = NSRect(x: 100, y: 50, width: 240, height: 44)
        label.frame = NSRect(x: 100, y: 120, width: 250, height: 34)
        label.font = .systemFont(ofSize: 24)
        label.textColor = .white
        window.contentView?.addSubview(button)
        window.contentView?.addSubview(label)
    }
    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func increment() { counter += 1; label.stringValue = "Counter: \(counter)" }
}
