import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import OpenComputerUseKit

/// Explicit local enrollment. The elevated shell only stages signed artifacts
/// into a protected directory and verifies the installer before executing it.
/// It never executes a repository script with administrator privileges.
@MainActor
enum LockedUseSettings {
    static func handle(arguments: [String]) throws -> Bool {
        guard arguments.first == "locked-use", arguments.count > 1,
              ["enable", "disable", "recover", "certify", "settings"].contains(arguments[1]) else { return false }
        guard arguments.count == 2 else {
            throw OpenComputerUseCLIError(message: "Usage: ocu locked-use enable | disable | recover | certify | settings")
        }
        let action = arguments[1]
        if action == "settings" {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "Locked Use"
            alert.informativeText = "在锁屏时继续使用已登录的 Mac。所有显示器会被遮蔽；移动鼠标或按键立即返回锁屏。启用需要管理员授权、辅助功能、屏幕录制和输入监控权限。"
            alert.addButton(withTitle: "启用")
            alert.addButton(withTitle: "停用并移除")
            alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn: try enable()
            case .alertSecondButtonReturn: try disable()
            default: break
            }
        } else if action == "enable" { try enable() }
        else if action == "certify" { try certify() }
        else if action == "recover" { try enable(recovering: true) }
        else { try disable() }
        return true
    }

    private static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func elevate(_ commands: String) throws {
        // AppleScript receives one data string through an argument, avoiding
        // interpolation into AppleScript syntax or shell command substitution.
        let script = "on run argv\nreturn do shell script (item 1 of argv) with administrator privileges\nend run"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, commands]
        let output = Pipe(); process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw OpenComputerUseCLIError(message: "Locked Use administrator installation did not complete. Existing recovery records were retained.") }
        print(text, terminator: "")
    }
    private static func enable(recovering: Bool = false) throws {
        guard LockedUseSession.current().state == .unlocked else { throw OpenComputerUseCLIError(message: "Unlock the Mac normally before administrator installation or recovery.") }
        let identity = try LockedUseSigningIdentity.current()
        guard identity.userID > 0, ["com.ifuryst.opencomputeruse", "com.ifuryst.opencomputeruse.dev"].contains(identity.signingIdentifier),
              let team = identity.teamIdentifier else { throw OpenComputerUseCLIError(message: "Use the signed Open Computer Use app to enable Locked Use.") }
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/LockedUse")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("OCULockInstaller").path) else {
            throw OpenComputerUseCLIError(message: "Signed Locked Use components are missing from this app. Build with OPEN_COMPUTER_USE_INCLUDE_LOCKED_USE=1.")
        }
        // Administrator staging has a protected parent; /tmp ancestry would
        // permit path replacement even when a leaf happens to be root owned.
        let requirement = "=identifier \"dev.opencomputeruse.locked-use.installer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        let stageParent = "/Library/Application Support/OpenComputerUseLockedUseStaging"
        let stage = stageParent + "/" + UUID().uuidString
        let shell = "set -eu\numask 077\n" +
            "/bin/test ! -L " + quote(stageParent) + "\n" +
            "/bin/mkdir -p " + quote(stageParent) + "\n" +
            "/usr/sbin/chown root:wheel " + quote(stageParent) + "\n" +
            "/bin/chmod -N " + quote(stageParent) + "\n" +
            "/bin/chmod 700 " + quote(stageParent) + "\n" +
            "/bin/mkdir " + quote(stage) + "\n" +
            "trap " + quote("/bin/rm -rf " + quote(stage)) + " EXIT\n" +
            "/usr/bin/ditto " + quote(source.path) + " " + quote(stage) + "\n" +
            "/usr/bin/ditto " + quote(Bundle.main.bundleURL.path) + " " + quote(stage + "/Client.app") + "\n" +
            "/usr/bin/find " + quote(stage) + " -type l -print -quit | /usr/bin/awk 'END { exit(NR != 0) }'\n" +
            "/usr/sbin/chown -hR -P root:wheel " + quote(stage) + "\n" +
            "/bin/chmod -RN " + quote(stage) + "\n" +
            "/bin/chmod -R go-w " + quote(stage) + "\n" +
            "/usr/bin/codesign --verify --strict -R " + quote(requirement) + " " + quote(stage + "/OCULockInstaller") + "\n" +
            quote(stage + "/OCULockInstaller") + (recovering ? " recover" : " install " + quote(stage) + " " + String(identity.userID) + " " + "production")
        try elevate(shell)
        if !recovering { try requestPermissions() }
    }

    private static func requestPermissions() throws {
        let team = try LockedUseSigningIdentity.current().teamIdentifier!
        // Verify the administrator-installed components before launching Guardian.
        _ = try LockedUseComponentValidation.current(team: team)
        let guardian = Process()
        guardian.executableURL = URL(fileURLWithPath: "/Library/Application Support/OpenComputerUse/LockedUse/OCU Guardian.app/Contents/MacOS/OCUGuardian")
        guardian.arguments = ["--request-permissions"]
        try guardian.run()
        guardian.waitUntilExit()
        guard guardian.terminationStatus == 0 else {
            throw OpenComputerUseCLIError(message: "Locked Use is installed, but Guardian permission setup failed. Run locked-use status before using it.")
        }
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        print("Locked Use installed. Complete Open Computer Use and OCU Guardian permissions in System Settings, then run ocu locked-use status.")
    }
    private static func certify() throws {
        guard LockedUseSession.current().state == .unlocked else {
            throw OpenComputerUseCLIError(message: "Unlock normally before reviewing production validation.")
        }
        let alert = NSAlert()
        alert.messageText = "确认 Locked Use 实机验证"
        alert.informativeText = "请仅在这些测试均通过后继续：所有物理屏幕持续遮蔽；Secure Input 下键盘和鼠标立即接管；Guardian、watchdog、app agent、Broker 故障及显示器变化安全重锁；正常密码及 Touch ID 解锁。专用窗口 AX / ScreenCaptureKit 与两类 Keychain 测试证据还会由安装器独立检查。升级 macOS 或保护组件后须重新验证。"
        alert.addButton(withTitle: "全部通过，启用")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try installedAction("promote")
    }
    private static func installedAction(_ action: String) throws {
        let team = try LockedUseSigningIdentity.current().teamIdentifier!
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/LockedUse/OCULockInstaller")
        if action == "uninstall", FileManager.default.fileExists(atPath: bundled.path) {
            // Upgrade/removal must run the current fix, not an older installed
            // installer that may fail while deleting the OS-managed cache.
            let parent = "/Library/Application Support/OpenComputerUseLockedUseStaging"
            let stage = parent + "/" + UUID().uuidString
            let requirement = "=identifier \"dev.opencomputeruse.locked-use.installer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            let commands = "set -eu\numask 077\n" +
                "/bin/test ! -L " + quote(parent) + "\n" +
                "/bin/mkdir -p " + quote(parent) + "\n" +
                "/usr/sbin/chown root:wheel " + quote(parent) + "\n" +
                "/bin/chmod -N " + quote(parent) + "\n" +
                "/bin/chmod 700 " + quote(parent) + "\n" +
                "/bin/mkdir " + quote(stage) + "\n" +
                "trap " + quote("/bin/rm -rf " + quote(stage)) + " EXIT\n" +
                "/usr/bin/ditto " + quote(bundled.path) + " " + quote(stage + "/OCULockInstaller") + "\n" +
                "/bin/test ! -L " + quote(stage + "/OCULockInstaller") + "\n" +
                "/bin/test -f " + quote(stage + "/OCULockInstaller") + "\n" +
                "/usr/sbin/chown root:wheel " + quote(stage + "/OCULockInstaller") + "\n" +
                "/bin/chmod -N " + quote(stage + "/OCULockInstaller") + "\n" +
                "/bin/chmod 700 " + quote(stage + "/OCULockInstaller") + "\n" +
                "/usr/bin/codesign --verify --strict -R " + quote(requirement) + " " + quote(stage + "/OCULockInstaller") + "\n" +
                quote(stage + "/OCULockInstaller") + " uninstall"
            try elevate(commands)
            return
        }
        let base = "/Library/Application Support/OpenComputerUse/LockedUse/"
        let current = base + "OCULockInstaller"
        let legacy = base + "OpenComputerUseLockedUseInstaller"
        let path = FileManager.default.fileExists(atPath: current) ? current : legacy
        let requirement = "=identifier \"dev.opencomputeruse.locked-use.installer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        try elevate("set -eu\n/usr/bin/codesign --verify --strict -R " + quote(requirement) + " " + quote(path) + "\n" + quote(path) + " " + quote(action))
    }

    private static func disable() throws {
        guard LockedUseSession.current().state == .unlocked else { throw OpenComputerUseCLIError(message: "Unlock the Mac normally before administrator removal.") }
        try installedAction("uninstall")
    }
}
