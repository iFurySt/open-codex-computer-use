import AppKit
import SwiftUI

@main
enum CursorMotionMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let delegate = CursorMotionAppDelegate()
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class CursorMotionAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cursor Motion"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1120, height: 760)
        window.contentView = NSHostingView(rootView: CursorLabRootView())

        self.window = window
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.level = .normal
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Cursor Motion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }
}
