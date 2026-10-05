import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var label: NSTextField!
    var count = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        var frame = NSRect(x: 80, y: 80, width: 360, height: 180)
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--display-id"), index + 1 < args.count, let displayID = UInt32(args[index + 1]), let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) {
            frame.origin = NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 40)
        }
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "OCU Power GUI Probe \(getpid())"
        label = NSTextField(labelWithString: "Count: 0"); label.frame = NSRect(x: 20, y: 110, width: 300, height: 30)
        label.setAccessibilityIdentifier("power-counter")
        let button = NSButton(title: "Increment", target: self, action: #selector(increment))
        button.frame = NSRect(x: 20, y: 40, width: 160, height: 40)
        button.setAccessibilityIdentifier("power-increment")
        window.contentView?.addSubview(label); window.contentView?.addSubview(button)
        if args.contains("--probe-owner") {
            DispatchQueue.global().async {
                _ = FileHandle.standardInput.readDataToEndOfFile()
                DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            }
        }
        window.orderFront(nil) // Do not activate or move the physical pointer.
    }
    @objc func increment() { count += 1; label.stringValue = "Count: \(count)" }
}
let delegate = Delegate(); app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
