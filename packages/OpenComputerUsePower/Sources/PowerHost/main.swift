import AppKit
import Foundation
import ServiceManagement
import ApplicationServices
import PowerCore
import PowerNative
import Darwin

func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
func registerHelper() throws {
    try ensureBundled()
    do { try service().register() }
    catch { if service().status != .requiresApproval { throw error } }
}
func service() -> SMAppService { .daemon(plistName: PowerPaths.service + ".plist") }
func ensureBundled() throws {
    guard Bundle.main.bundleURL.pathExtension == "app", ocu_power_is_signed_host() == 1 else { throw PowerFailure.invalid("Install management requires a Developer ID signed Power app bundle") }
    let expected = URL(fileURLWithPath: "/Applications").appendingPathComponent(PowerPaths.service.hasSuffix(".dev") ? "Open Computer Use Power (Dev).app" : "Open Computer Use Power.app")
    guard Bundle.main.bundleURL.standardizedFileURL == expected else { throw PowerFailure.invalid("Install the Power app at its standard /Applications location before managing the lid helper") }
}
func client(autostart: Bool = true) throws -> PowerClient {
    do { return try PowerClient() } catch {
        guard autostart, Bundle.main.bundleURL.pathExtension == "app" else { throw error }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-gj", Bundle.main.bundleURL.path, "--args", "serve"]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw PowerFailure.backend("Cannot launch Power coordinator") }
        let until = PowerClock.now + 5
        while PowerClock.now < until {
            if let connection = try? PowerClient() { return connection }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw PowerFailure.backend("Coordinator startup timed out; check that the app is installed and signed")
    }
}
final class PowerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let registry = PowerHoldRegistry(backend: NativePowerBackend())
    var server: PowerSocketServer?
    var timer: DispatchSourceTimer?
    var signalSource: DispatchSourceSignal?
    var metricsTimer: DispatchSourceTimer?
    var window: NSWindow?
    var text: NSTextView?
    let visible: Bool
    let metricsPath: String
    init(visible: Bool, metricsPath: String = MetricsStore.defaultPath) { self.visible = visible; self.metricsPath = metricsPath }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let server = PowerSocketServer(registry: registry)
            do { server.metricsService = try MetricsService(store: MetricsStore(path: metricsPath)) }
            catch { server.metricsError = error.localizedDescription }
            server.onShutdown = { [weak self] in self?.server?.stop(); NSApplication.shared.terminate(nil) }
            try server.start(); self.server = server
        } catch { fputs("\(error.localizedDescription)\n", stderr); NSApplication.shared.terminate(nil); return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "power.tick"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.registry.tick(environment: NativePowerBackend.environment())
            DispatchQueue.main.async { [weak self] in self?.updateText() }
        }
        timer.resume(); self.timer = timer
        let metricsTimer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "power.metrics"))
        metricsTimer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(250))
        metricsTimer.setEventHandler { [weak self] in
            guard let self else { return }
            self.server?.metricsService?.tick(status: try? self.registry.status(uid: getuid()))
        }
        metricsTimer.resume(); self.metricsTimer = metricsTimer
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }; source.resume(); signalSource = source
        if visible { showWindow() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try registry.shutdown(); server?.stop(); return .terminateNow }
        catch { fputs("Power restoration failed: \(error.localizedDescription)\n", stderr); return .terminateCancel }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 440), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Open Computer Use Power"; window.center(); window.delegate = self
            let scroll = NSScrollView(frame: NSRect(x: 16, y: 60, width: 618, height: 364))
            scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            scroll.documentView = text; window.contentView?.addSubview(scroll); self.text = text
            let install = NSButton(title: "Install lid helper", target: self, action: #selector(installHelper)); install.frame = NSRect(x: 16, y: 16, width: 165, height: 30)
            let stop = NSButton(title: "Release all and quit", target: self, action: #selector(stopAll)); stop.frame = NSRect(x: 190, y: 16, width: 190, height: 30)
            window.contentView?.addSubview(install); window.contentView?.addSubview(stop)
            self.window = window
            let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
            let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit Power", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = appMenu; NSApplication.shared.mainMenu = menu
        }
        updateText(); window?.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func updateText() {
        guard let status = try? registry.status(uid: getuid()) else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        text?.string = "Helper registration: \(service().status.rawValue)\nClosing this window preserves manual holds. Quit releases them.\n\n" + String(decoding: (try? encoder.encode(status)) ?? Data(), as: UTF8.self)
    }
    @objc func installHelper() {
        do { try registerHelper(); if service().status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }; updateText() }
        catch { let alert = NSAlert(); alert.messageText = "Helper installation failed"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
    @objc func stopAll() { NSApplication.shared.terminate(nil) }
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "app"
do {
    switch command {
    case "app", "serve":
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        var metricsPath = MetricsStore.defaultPath
        if args.count > 1 {
            guard command == "serve", args.count == 3, args[1] == "--metrics-path" else { throw PowerFailure.invalid("serve accepts only --metrics-path PATH") }
            metricsPath = args[2]
        }
        let delegate = PowerAppDelegate(visible: command == "app", metricsPath: metricsPath); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    case "help", "--help", "-h":
        print("""
        OCU Power — independent macOS power holds
        acquire [--options JSON]     Manual hold by default; prints hold ID as JSON
        status [ID]                 Requested and confirmed capabilities
        release ID                  Release one hold
        run [--options JSON] -- COMMAND [ARGS...]   Connection-bound hold
        shutdown                    Release all holds and stop this user's coordinator
        serve [--metrics-path PATH]  Foreground coordinator (unbundled development)
        install / uninstall         Manage the signed lid helper
        metrics [--query JSON]        Recent samples (epoch seconds, limit <=100)
        metrics-configure JSON       enabled, interval_seconds, retention_seconds
        metrics-clear                Delete stored samples
        doctor                      Read-only coordinator, helper and power diagnostics
        gui-smoke [--closed-lid] [--seconds N] [--display-id ID]  Attended real AX/SCK test
        Options: prevent_idle_sleep, prevent_display_sleep, prevent_lid_sleep,
                 lifetime (manual|timed|connection), seconds,
                 battery_floor_percent, stop_on_serious_thermal_state
        """)
    case "acquire", "run":
        var remaining = Array(args.dropFirst()), options = HoldOptions()
        if remaining.first == "--options" {
            guard remaining.count >= 2 else { throw PowerFailure.invalid("--options requires JSON") }
            options = try JSONDecoder().decode(HoldOptions.self, from: Data(remaining[1].utf8)); remaining.removeFirst(2)
        }
        if command == "run" {
            guard remaining.first == "--", remaining.count >= 2 else { throw PowerFailure.invalid("run requires -- COMMAND") }
            options.lifetime = .connection; options.seconds = nil
            let connection = try client(); let hold = try connection.acquire(options)
            try output(hold)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = Array(remaining.dropFirst())
            do { try process.run(); process.waitUntilExit(); try connection.release(hold.id) }
            catch { try? connection.release(hold.id); throw error }
            exit(process.terminationReason == .exit ? process.terminationStatus : 128 + process.terminationStatus)
        } else {
            guard remaining.isEmpty else { throw PowerFailure.invalid("Unexpected acquire arguments") }
            guard options.lifetime != .connection else { throw PowerFailure.invalid("Use run or a persistent SDK connection for connection holds") }
            try output(client().acquire(options))
        }
    case "status":
        guard args.count <= 2 else { throw PowerFailure.invalid("status accepts one optional ID") }
        try output(client().status(args.count == 2 ? args[1] : nil))
    case "release":
        guard args.count == 2 else { throw PowerFailure.invalid("release requires an ID") }
        try output(client().request(.init("release", id: args[1])))
    case "shutdown": try output(client(autostart: false).request(.init("shutdown")))
    case "install":
        try registerHelper()
        try output(["registration_status": String(service().status.rawValue), "requires_approval": service().status == .requiresApproval ? "true" : "false"])
        if service().status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    case "uninstall":
        try ensureBundled()
        if let active = try? client(autostart: false) { _ = try active.request(.init("shutdown")) }
        // Inspect recovery state before unregistering the only service capable of restoration.
        let registration = service().status
        if registration == .notRegistered || registration == .notFound {
            try output(["uninstalled": true]); break
        }
        if registration == .requiresApproval {
            guard try !PMSetSleepSwitch().read() else { throw PowerFailure.backend("Sleep is disabled; cannot remove a pending recovery service") }
        } else {
            do {
                let helper = try callPowerHelper(.init("status"))
                guard helper.sleepDisabled == false else { throw PowerFailure.backend("Sleep is still disabled; cannot safely uninstall helper") }
            } catch {
                // A registered job can fail to spawn. Only a verified disabled switch
                // allows removing that broken registration; unknown state still fails.
                guard try !PMSetSleepSwitch().read() else { throw error }
            }
        }
        let done = DispatchSemaphore(value: 0); var failure: Error?
        service().unregister { error in failure = error; done.signal() }
        guard done.wait(timeout: .now() + 15) == .success else { throw PowerFailure.backend("Helper unregister timed out") }
        if let failure { throw failure }
        try output(["uninstalled": true])
    case "gui-smoke":
        var remaining = Array(args.dropFirst()), seconds = 5.0, displayID: UInt32?, closed = false
        while !remaining.isEmpty {
            let flag = remaining.removeFirst()
            switch flag {
            case "--closed-lid": closed = true
            case "--seconds":
                guard let value = remaining.first, let parsed = Double(value), parsed.isFinite, parsed >= 1, parsed <= 300 else { throw PowerFailure.invalid("Probe seconds must be 1...300") }
                seconds = parsed; remaining.removeFirst()
            case "--display-id":
                guard let value = remaining.first, let parsed = UInt32(value) else { throw PowerFailure.invalid("Display ID must be a UInt32") }
                displayID = parsed; remaining.removeFirst()
            default: throw PowerFailure.invalid("Unknown GUI probe option")
            }
        }
        try PowerGUIProbe.run(waitForClosedLid: closed, seconds: seconds, displayID: displayID, connection: client())
    case "metrics":
        var query = MetricsQuery()
        if args.count > 1 {
            guard args.count == 3, args[1] == "--query" else { throw PowerFailure.invalid("metrics accepts --query JSON") }
            query = try JSONDecoder().decode(MetricsQuery.self, from: Data(args[2].utf8))
        }
        try output(client().metrics(query))
    case "metrics-configure":
        guard args.count == 2 else { throw PowerFailure.invalid("metrics-configure requires JSON") }
        try output(client().configureMetrics(JSONDecoder().decode(MetricsConfiguration.self, from: Data(args[1].utf8))))
    case "metrics-clear":
        guard args.count == 1 else { throw PowerFailure.invalid("metrics-clear accepts no arguments") }
        try client().clearMetrics(); try output(["cleared": true])
    case "doctor":
        var result: [String: Any] = ["bundle": Bundle.main.bundleURL.pathExtension == "app", "registration_status": service().status.rawValue, "developer_id_valid": ocu_power_is_signed_host() == 1, "accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess()]
        result["coordinator_running"] = (try? client(autostart: false)) != nil
        do { result["sleep_disabled"] = try PMSetSleepSwitch().read() } catch { result["power_error"] = error.localizedDescription }
        if Bundle.main.bundleURL.pathExtension == "app" && service().status == .enabled {
            do { result["helper_confirmed"] = try callPowerHelper(.init("status")).sleepDisabled as Any } catch { result["helper_error"] = error.localizedDescription }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    default: throw PowerFailure.invalid("Unknown command; use --help")
    }
} catch {
    let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription], options: [.sortedKeys])) ?? Data()
    fputs(String(decoding: data, as: UTF8.self) + "\n", stderr); exit(1)
}
