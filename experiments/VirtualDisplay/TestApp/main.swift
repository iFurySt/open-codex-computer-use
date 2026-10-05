import AppKit

final class DragSurface: NSView {
    let status = NSTextField(labelWithString: "Drag 0")
    private var drags = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.systemBlue.cgColor
        status.frame = NSRect(x: 12, y: 12, width: 180, height: 24); addSubview(status)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Drag surface")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) { drags += 1; status.stringValue = "Drag \(drags)" }
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
final class TestAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var inputField: NSTextField?
    private var timer: Timer?
    private var activationLosses = 0
    private var keyLosses = 0
    func applicationDidResignActive(_ notification: Notification) { activationLosses += 1 }
    func windowDidResignKey(_ notification: Notification) { keyLosses += 1 }
    var window: NSWindow!
    let counter = NSTextField(labelWithString: "Counter 0")
    var clicks = 0
    private var sheet: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let displayID: UInt32? = arguments.firstIndex(of: "--display-id").flatMap { arguments.indices.contains($0 + 1) ? UInt32(arguments[$0 + 1]) : nil }
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
        let origin = screen.map { CGPoint(x: $0.frame.minX + 70, y: $0.frame.maxY - 650) } ?? CGPoint(x: 80, y: 80)
        window = NSWindow(contentRect: NSRect(origin: origin, size: CGSize(width: 800, height: 560)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Virtual Display Test"; window.isReleasedWhenClosed = false; window.delegate = self
        let content = window.contentView!
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor.white.cgColor
        let marker = NSView(frame: NSRect(x: 0, y: 0, width: 55, height: 560))
        marker.wantsLayer = true; marker.layer?.backgroundColor = NSColor.systemRed.cgColor; content.addSubview(marker)
        counter.frame = NSRect(x: 75, y: 480, width: 220, height: 28); counter.setAccessibilityIdentifier("live-counter"); content.addSubview(counter)
        let button = NSButton(title: "Increment", target: self, action: #selector(increment))
        button.frame = NSRect(x: 310, y: 475, width: 130, height: 36); button.setAccessibilityIdentifier("live-increment"); content.addSubview(button)
        let input = NSTextField(frame: NSRect(x: 75, y: 420, width: 600, height: 32))
        inputField = input
        input.placeholderString = "Write here"; input.setAccessibilityIdentifier("live-input"); content.addSubview(input)
        let popup = NSButton(title: "Open sheet", target: self, action: #selector(openSheet))
        popup.frame = NSRect(x: 75, y: 365, width: 150, height: 32); content.addSubview(popup)
        let drag = DragSurface(frame: NSRect(x: 460, y: 215, width: 270, height: 150)); content.addSubview(drag)
        let scroll = NSScrollView(frame: NSRect(x: 75, y: 55, width: 350, height: 290))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 1400))
        for i in 0..<35 {
            let label = NSTextField(labelWithString: "Scroll row \(i)")
            label.frame = NSRect(x: 12, y: 12 + i * 38, width: 260, height: 26); document.addSubview(label)
        }
        scroll.documentView = document; scroll.setAccessibilityIdentifier("live-scroll"); content.addSubview(scroll)
        window.makeFirstResponder(input)
        window.orderFront(nil) // background target never activates
        if let index = arguments.firstIndex(of: "--foreground-probe"), arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: arguments[index + 1])
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(input)
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeProbe(url) }
            }
        }
    }
    func writeProbe(_ url: URL) {
        let focused = inputField?.currentEditor() != nil && window.firstResponder === inputField?.currentEditor()
        let value: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "active": NSApp.isActive, "key": window.isKeyWindow,
                                  "first_responder_is_input": focused, "activation_losses": activationLosses, "key_losses": keyLosses]
        if let data = try? JSONSerialization.data(withJSONObject: value) { try? data.write(to: url, options: .atomic) }
    }
    @objc func increment() { clicks += 1; counter.stringValue = "Counter \(clicks)" }
    @objc func openSheet() {
        // NSAlert may activate an inactive application on some desktops. The
        // controlled target deliberately uses a real nonactivating AppKit sheet.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Test sheet"; panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "Test sheet")
        label.frame = NSRect(x: 24, y: 90, width: 280, height: 28); panel.contentView?.addSubview(label)
        let button = NSButton(title: "Dismiss", target: self, action: #selector(dismissSheet))
        button.frame = NSRect(x: 230, y: 24, width: 100, height: 32); panel.contentView?.addSubview(button)
        sheet = panel
        window.beginSheet(panel)
    }
    @objc func dismissSheet() {
        guard let sheet else { return }
        window.endSheet(sheet); sheet.orderOut(nil); self.sheet = nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let application = NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--foreground-probe") ? .regular : .accessory)
let delegate = TestAppDelegate()
application.delegate = delegate
application.run()
