import AppKit
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
        guard arguments.count == 2 || arguments == ["locked-use", "enable", "--validation"] else {
            throw OpenComputerUseCLIError(message: "Usage: ocu locked-use enable [--validation] | disable | recover | certify | settings")
        }
        let action = arguments[1]
        if action == "settings" {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "Locked Use"
            alert.informativeText = "在锁屏时继续使用已登录的 Mac。所有显示器会被遮蔽；移动鼠标或按键立即返回锁屏。启用需要管理员授权和已验证的解锁组件。"
            alert.addButton(withTitle: "启用")
            alert.addButton(withTitle: "停用并移除")
            alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn: try enable(validation: false)
            case .alertSecondButtonReturn: try disable()
            default: break
            }
        } else if action == "enable" { try enable(validation: arguments.last == "--validation") }
        else if action == "certify" { try certify() }
        else if action == "recover" { try enable(validation: false, recovering: true) }
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
    private static func enable(validation: Bool, recovering: Bool = false) throws {
        guard LockedUseSession.current().state == .unlocked else { throw OpenComputerUseCLIError(message: "Unlock the Mac normally before administrator installation or recovery.") }
        let identity = try LockedUseSigningIdentity.current()
        guard identity.userID > 0, ["com.ifuryst.opencomputeruse", "com.ifuryst.opencomputeruse.dev"].contains(identity.signingIdentifier),
              let team = identity.teamIdentifier else { throw OpenComputerUseCLIError(message: "Use the signed Open Computer Use app to enable Locked Use.") }
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/LockedUse")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("OpenComputerUseLockedUseInstaller").path) else {
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
            "/usr/bin/codesign --verify --strict -R " + quote(requirement) + " " + quote(stage + "/OpenComputerUseLockedUseInstaller") + "\n" +
            quote(stage + "/OpenComputerUseLockedUseInstaller") + (recovering ? " recover" : " install " + quote(stage) + " " + String(identity.userID) + " " + (validation ? "validation" : "production"))
        try elevate(shell)
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
        let path = "/Library/Application Support/OpenComputerUse/LockedUse/OpenComputerUseLockedUseInstaller"
        let requirement = "=identifier \"dev.opencomputeruse.locked-use.installer\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        try elevate("set -eu\n/usr/bin/codesign --verify --strict -R " + quote(requirement) + " " + quote(path) + "\n" + quote(path) + " " + quote(action))
    }

    private static func disable() throws {
        guard LockedUseSession.current().state == .unlocked else { throw OpenComputerUseCLIError(message: "Unlock the Mac normally before administrator removal.") }
        try installedAction("uninstall")
    }
}
