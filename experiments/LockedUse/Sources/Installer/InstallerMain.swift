import Darwin
import Foundation
import LockedUseNative
import OpenComputerUseKit
import Security

private let root = URL(fileURLWithPath: "/Library/Application Support/OpenComputerUse/LockedUse", isDirectory: true)
private let pluginName = "OpenComputerUseLockedUseAuthorizationPlugin.bundle"
private let guardianName = "Open Computer Use Guardian (Dev).app"
private let service = "dev.opencomputeruse.locked-use.broker"
private let daemon = URL(fileURLWithPath: "/Library/LaunchDaemons/dev.opencomputeruse.locked-use.broker.plist")
private let plugin = URL(fileURLWithPath: "/Library/Security/SecurityAgentPlugins/" + pluginName)
private let screensaver = "system.login.screensaver"

private enum InstallError: Error { case invalidArguments, untrusted, existingInstallation, authentication(OSStatus), changedPolicy, process(Int32) }

@main
struct InstallerMain {
    static func main() {
        do {
            guard geteuid() == 0 else { throw InstallError.untrusted }
            // The administrator staging shell is deliberately private. System
            // client traversal must not inherit that shell's umask 077.
            _ = umask(0o022)
            let identity = try LockedUseSigningIdentity.current()
            guard identity.signingIdentifier == "dev.opencomputeruse.locked-use.installer", let team = identity.teamIdentifier else { throw InstallError.untrusted }
            let lockDirectory = URL(fileURLWithPath: "/Library/Application Support/OpenComputerUseLockedUseStaging", isDirectory: true)
            try makeDirectory(lockDirectory)
            let lockFD = open(lockDirectory.appendingPathComponent("installation.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockFD >= 0 else { throw InstallError.untrusted }
            defer { Darwin.close(lockFD) }
            var lockInfo = stat()
            guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == 0, lockInfo.st_mode & S_IFMT == S_IFREG,
                  lockInfo.st_mode & 0o077 == 0, ocu_has_mutating_acl(lockFD) == 0,
                  flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw InstallError.existingInstallation }
            let args = Array(CommandLine.arguments.dropFirst())
            if args.count == 4, args[0] == "install" {
                guard let uid = UInt32(args[2]), uid > 0,
                      ["validation", "production"].contains(args[3]) else { throw InstallError.invalidArguments }
                try install(source: URL(fileURLWithPath: args[1], isDirectory: true), uid: uid, team: team, validation: args[3] == "validation")
            } else if args == ["uninstall"] { try uninstall(team: team) }
            else if args == ["recover"] { try recover(team: team) }
            else if args == ["reconcile-stopped-guards"] { try reconcileStoppedGuards() }
            else if args == ["promote"] { try promote(team: team) }
            else { throw InstallError.invalidArguments }
        } catch {
            fputs("Locked Use installation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func verify(_ url: URL, id: String, team: String) throws -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw InstallError.untrusted }
        var requirement: SecRequirement?
        let text = "identifier \"\(id)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess else { throw InstallError.untrusted }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & SecCodeSignatureFlags.runtime.rawValue != 0 else { throw InstallError.untrusted }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        for key in ["com.apple.security.get-task-allow", "get-task-allow", "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"] {
            guard (entitlements[key] as? NSNumber)?.boolValue != true else { throw InstallError.untrusted }
        }
        return info
    }

    /// Every source has already been copied into an administrator-owned staging
    /// directory before execution. Refuse symlinks and writable ancestry so a
    /// source replacement cannot race code validation and installation.
    private static func trustedTree(_ url: URL) throws {
        var ancestor = url.standardizedFileURL
        while ancestor.path != "/" {
            let fd = open(ancestor.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw InstallError.untrusted }
            defer { Darwin.close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == 0,
                  info.st_mode & 0o022 == 0, ocu_has_mutating_acl(fd) == 0 else { throw InstallError.untrusted }
            ancestor.deleteLastPathComponent()
        }
        let urls = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [])
        while let item = urls?.nextObject() as? URL {
            var info = stat()
            guard lstat(item.path, &info) == 0, info.st_uid == 0,
                  [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT), info.st_mode & 0o6022 == 0 else { throw InstallError.untrusted }
            let fd = open(item.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw InstallError.untrusted }
            let acl = ocu_has_mutating_acl(fd); Darwin.close(fd)
            guard acl == 0 else { throw InstallError.untrusted }
        }
    }

    private static func makeDirectory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try makeDirectory(url.deletingLastPathComponent())
            guard mkdir(url.path, 0o755) == 0 else { throw InstallError.untrusted }
        }
        try trustedTreeShallow(url)
    }
    private static func trustedTreeShallow(_ url: URL) throws {
        var cursor = url
        while cursor.path != "/" {
            let fd = open(cursor.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw InstallError.untrusted }
            var info = stat()
            let valid = fstat(fd, &info) == 0 && info.st_uid == 0 && info.st_mode & 0o022 == 0 && ocu_has_mutating_acl(fd) == 0
            Darwin.close(fd)
            guard valid else { throw InstallError.untrusted }
            cursor.deleteLastPathComponent()
        }
    }
    private static func write<T: Encodable>(_ value: T, name: String, replacing: Bool = false) throws {
        if replacing { _ = try LockedUseBrokerConfiguration.loadInstalled() }
        guard replacing || !FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) else { throw InstallError.existingInstallation }
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name), options: [.atomic])
        guard chmod(root.appendingPathComponent(name).path, 0o644) == 0 else { throw InstallError.untrusted }
    }
    private static func readRight(_ name: String) throws -> Data {
        var dictionary: CFDictionary?
        let result = AuthorizationRightGet(name, &dictionary)
        guard result == errSecSuccess, let dictionary else { throw InstallError.authentication(result) }
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
    private static func setRight(_ name: String, data: Data, authorization: AuthorizationRef) throws {
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary else { throw InstallError.changedPolicy }
        let result = AuthorizationRightSet(authorization, name, dictionary, nil, nil, nil)
        guard result == errSecSuccess else { throw InstallError.authentication(result) }
    }
    private static func authorization() throws -> AuthorizationRef {
        var reference: AuthorizationRef?
        let result = AuthorizationCreate(nil, nil, [], &reference)
        guard result == errSecSuccess, let reference else { throw InstallError.authentication(result) }
        return reference
    }
    private static func remoteDefinition() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["class": "evaluate-mechanisms",
            "mechanisms": ["OpenComputerUseLockedUseAuthorizationPlugin:remote"], "shared": false,
            "timeout": 0, "tries": 1, "comment": "Open Computer Use single-use protected-session authorization"], format: .xml, options: 0)
    }
    private static func install(source: URL, uid: UInt32, team: String, validation: Bool) throws {
        try trustedTree(source)
        let broker = source.appendingPathComponent("OpenComputerUseLockedUseBroker")
        _ = try verify(broker, id: service, team: team)
        _ = try verify(source.appendingPathComponent("OpenComputerUseLockedUseInstaller"), id: "dev.opencomputeruse.locked-use.installer", team: team)
        _ = try verify(source.appendingPathComponent(guardianName), id: "dev.opencomputeruse.locked-use.guardian.dev", team: team)
        _ = try verify(source.appendingPathComponent(pluginName), id: "dev.opencomputeruse.locked-use.authorization", team: team)
        let client = source.appendingPathComponent("Client.app")
        guard let identifier = Bundle(url: client)?.bundleIdentifier,
              ["com.ifuryst.opencomputeruse", "com.ifuryst.opencomputeruse.dev"].contains(identifier) else { throw InstallError.untrusted }
        _ = try verify(client, id: identifier, team: team)
        guard !FileManager.default.fileExists(atPath: root.path), !FileManager.default.fileExists(atPath: plugin.path),
              !FileManager.default.fileExists(atPath: daemon.path) else { throw InstallError.existingInstallation }
        var existing: CFDictionary?
        guard AuthorizationRightGet(LockedUseAuthorizationRules.remoteRight, &existing) == errAuthorizationDenied else { throw InstallError.existingInstallation }
        let plan = try LockedUseAuthorizationRules.planInstallation(current: readRight(screensaver))
        let reference = try authorization(); defer { AuthorizationFree(reference, []) }
        try makeDirectory(root)
        // Only this application's fixed system namespace is made traversable;
        // private recovery journals still retain their explicit mode 0600.
        guard chmod(root.deletingLastPathComponent().path, 0o755) == 0,
              chmod(root.path, 0o755) == 0 else { throw InstallError.untrusted }
        try makeDirectory(root.appendingPathComponent("run", isDirectory: true))
        try write(plan, name: "authorization-plan.json")
        let approvals = try LockedUseClientApprovals(approvals: [
            .init(userID: uid, role: .client, signingIdentifier: identifier, teamIdentifier: team),
            .init(userID: uid, role: .agent, signingIdentifier: identifier, teamIdentifier: team),
            .init(userID: uid, role: .guardian, signingIdentifier: "dev.opencomputeruse.locked-use.guardian.dev", teamIdentifier: team)
        ])
        try write(approvals, name: "clients.json")
        try write(LockedUseBrokerConfiguration(enabled: true), name: "configuration.json")
        for name in ["OpenComputerUseLockedUseBroker", guardianName, "OpenComputerUseLockedUseInstaller"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: root.appendingPathComponent(name))
        }
        try makeDirectory(plugin.deletingLastPathComponent())
        try FileManager.default.copyItem(at: source.appendingPathComponent(pluginName), to: plugin)
        // Preserve a recoverable plan before writes; never blindly repair a
        // concurrently modified authentication policy in a failure handler.
        do {
            try setRight(LockedUseAuthorizationRules.remoteRight, data: remoteDefinition(), authorization: reference)
            guard try LockedUseAuthorizationRules.installationStillApplicable(current: readRight(screensaver), plan: plan) else { throw InstallError.changedPolicy }
            try setRight(screensaver, data: plan.installed, authorization: reference)
            guard try LockedUseAuthorizationRules.installationObserved(current: readRight(screensaver), plan: plan) else { throw InstallError.changedPolicy }
            let plist: [String: Any] = ["Label": service,
                "ProgramArguments": [root.appendingPathComponent("OpenComputerUseLockedUseBroker").path, validation ? "--serve-validation" : "--serve"],
                "RunAtLoad": true, "KeepAlive": true, "ProcessType": "Interactive", "ThrottleInterval": 5]
            try makeDirectory(daemon.deletingLastPathComponent())
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: daemon, options: [.withoutOverwriting])
            guard chmod(daemon.path, 0o644) == 0 else { throw InstallError.untrusted }
            try run("/bin/launchctl", ["bootstrap", "system", daemon.path])
            print("Installed Locked Use with preserved native fallback. Profile: \(validation ? "explicit validation" : "production; backend remains unvalidated").")
        } catch {
            if let current = try? readRight(screensaver), let original = try? LockedUseAuthorizationRules.planUninstallation(current: current, plan: plan) {
                try? setRight(screensaver, data: original, authorization: reference)
            }
            // Retain the root-owned recovery plan on any partial failure.
            throw error
        }
    }
    private static func promote(team: String) throws {
        let evidence = try LockedUseComponentValidation.current(team: team)
        let report = try LockedUseValidationReport.loadInstalled()
        guard report.canPromote(current: evidence) else { throw InstallError.changedPolicy }
        let plan = try LockedUseAuthorizationRules.loadInstalledPlan()
        guard try LockedUseAuthorizationRules.installationObserved(current: readRight(screensaver), plan: plan) else { throw InstallError.changedPolicy }
        try trustedTree(daemon)
        let bytes = try Data(contentsOf: daemon)
        guard var definition = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              definition["Label"] as? String == service,
              definition["ProgramArguments"] as? [String] == [root.appendingPathComponent("OpenComputerUseLockedUseBroker").path, "--serve-validation"] else { throw InstallError.changedPolicy }
        let admin = try LockedUseIPCClient(endpoint: .admin, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
        let reply = try admin.request(.init(operation: .disable)); admin.close()
        guard reply.result != .denied else { throw InstallError.changedPolicy }
        // No active or incompletely released lease can cross this service epoch.
        try run("/bin/launchctl", ["bootout", "system/" + service])
        try write(LockedUseBrokerConfiguration(enabled: true, validatedOSBuild: evidence.osBuild,
            validatedBrokerHash: evidence.brokerHash, validatedGuardianHash: evidence.guardianHash,
            validatedPluginHash: evidence.pluginHash), name: "configuration.json", replacing: true)
        definition["ProgramArguments"] = [root.appendingPathComponent("OpenComputerUseLockedUseBroker").path, "--serve"]
        let updated = try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
        try updated.write(to: daemon, options: [.atomic])
        guard chmod(daemon.path, 0o644) == 0 else { throw InstallError.untrusted }
        try run("/bin/launchctl", ["bootstrap", "system", daemon.path])
        print("Enabled production Locked Use for the verified OS and component build.")
    }

    /// Explicit administrator maintenance for missing release ACKs after a
    /// failed test. No policy mutation, permit restoration or certification.
    private static func reconcileStoppedGuards() throws {
        try trustedTreeShallow(root)
        let client = try LockedUseIPCClient(endpoint: .admin, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
        let status = try client.request(.init(operation: .status))
        client.close()
        guard status.result != .denied, let record = try LockedUseRecoveryRecord.loadInstalled() else {
            throw InstallError.changedPolicy
        }
        func exited(_ context: LockedUseBrokerCoordinator.Context) -> Bool {
            context.processID > 0 && kill(context.processID, 0) != 0 && errno == ESRCH
        }
        let peers = [record.guardian, record.watchdog].compactMap { $0 }
        guard record.canRetireStoppedGuards(phase: status.phase, allGuardsExited: peers.allSatisfy(exited)) else {
            throw InstallError.changedPolicy
        }
        // An idle epoch with unreleased peers cannot accept another begin.
        // Stop it before changing its durable fence; keep the original record.
        try run("/bin/launchctl", ["bootout", "system/" + service])
        var retired: URL?
        do {
            let lockFD = open(root.appendingPathComponent("run/broker.lock").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            guard lockFD >= 0 else { throw InstallError.untrusted }
            defer { Darwin.close(lockFD) }
            var lockInfo = stat()
            guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == 0, lockInfo.st_mode & S_IFMT == S_IFREG,
                  lockInfo.st_mode & 0o077 == 0, ocu_has_mutating_acl(lockFD) == 0,
                  flock(lockFD, LOCK_EX | LOCK_NB) == 0,
                  let current = try LockedUseRecoveryRecord.loadInstalled(), current.leaseID == record.leaseID,
                  current.owner.id == record.owner.id,
                  current.guardian?.id == record.guardian?.id, current.watchdog?.id == record.watchdog?.id,
                  current.canRetireStoppedGuards(phase: .idle, allGuardsExited: peers.allSatisfy(exited)) else {
                throw InstallError.changedPolicy
            }
            let archive = root.appendingPathComponent("retired-lease-" + UUID().uuidString + ".json")
            guard rename(root.appendingPathComponent("lease-recovery.json").path, archive.path) == 0 else {
                throw InstallError.untrusted
            }
            retired = archive
            let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw InstallError.untrusted }
            defer { Darwin.close(directory) }
            guard fsync(directory) == 0 else { throw InstallError.untrusted }
        } catch {
            // Restore service with its original fence on any failed check.
            if let retired, rename(retired.path, root.appendingPathComponent("lease-recovery.json").path) != 0 {
                throw InstallError.untrusted
            }
            try? run("/bin/launchctl", ["bootstrap", "system", daemon.path])
            throw error
        }
        try run("/bin/launchctl", ["bootstrap", "system", daemon.path])
        print("Retired the drained idle epoch after kernel-confirmed guard exits; authentication policy unchanged.")
    }

    private static func recover(team: String) throws {
        // If the service is alive, its authenticated drain/freeze is mandatory.
        if let client = try? LockedUseIPCClient(endpoint: .admin, brokerRequirement: LockedUseSigningIdentity.brokerRequirement()) {
            client.close()
            try uninstall(team: team)
            return
        }
        try trustedTreeShallow(root.appendingPathComponent("run", isDirectory: true))
        let lockFD = open(root.appendingPathComponent("run/broker.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw InstallError.untrusted }
        defer { Darwin.close(lockFD) }
        var info = stat()
        guard fstat(lockFD, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, ocu_has_mutating_acl(lockFD) == 0,
              flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw InstallError.existingInstallation }
        if let record = try LockedUseRecoveryRecord.loadInstalled(), !record.fullyReleased {
            // Never interpret service death or a visible old lock as drainage.
            // Restart the installed service to reconnect the old guardians.
            throw InstallError.changedPolicy
        }
        let plan = try LockedUseAuthorizationRules.loadInstalledPlan()
        let current = try readRight(screensaver)
        let reference = try authorization(); defer { AuthorizationFree(reference, []) }
        if try LockedUseAuthorizationRules.installationStillApplicable(current: current, plan: plan) {
            // Installation already rolled back its authentication mutation.
        } else {
            try setRight(screensaver, data: LockedUseAuthorizationRules.planUninstallation(current: current, plan: plan), authorization: reference)
        }
        let inspection = Process()
        inspection.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        inspection.arguments = ["print", "system/" + service]
        inspection.standardOutput = FileHandle.nullDevice; inspection.standardError = FileHandle.nullDevice
        try inspection.run(); inspection.waitUntilExit()
        if inspection.terminationStatus == 0 { try run("/bin/launchctl", ["bootout", "system/" + service]) }
        else if ![3, 113].contains(inspection.terminationStatus) { throw InstallError.process(inspection.terminationStatus) }
        try removeOwnArtifacts(team: team, authorization: reference)
        print("Recovered the partial installation and preserved the native authentication policy.")
    }

    private static func uninstall(team: String) throws {
        let observer = try LockedUseIPCClient(endpoint: .admin, brokerRequirement: LockedUseSigningIdentity.brokerRequirement())
        let status = try observer.request(.init(operation: .disable)); observer.close()
        guard status.result != .denied, status.phase == .idle || status.phase == .awaitingManualUnlock else { throw InstallError.changedPolicy }
        let plan = try LockedUseAuthorizationRules.loadInstalledPlan()
        let original = try LockedUseAuthorizationRules.planUninstallation(current: readRight(screensaver), plan: plan)
        _ = try verify(plugin, id: "dev.opencomputeruse.locked-use.authorization", team: team)
        let reference = try authorization(); defer { AuthorizationFree(reference, []) }
        try setRight(screensaver, data: original, authorization: reference)
        try run("/bin/launchctl", ["bootout", "system/" + service])
        try removeOwnArtifacts(team: team, authorization: reference)
        print("Removed Locked Use and restored the original authentication policy.")
    }
    private static func removeOwnArtifacts(team: String, authorization: AuthorizationRef) throws {
        var existing: CFDictionary?
        let found = AuthorizationRightGet(LockedUseAuthorizationRules.remoteRight, &existing)
        if found == errSecSuccess {
            guard let right = existing as? [String: Any], right["class"] as? String == "evaluate-mechanisms",
                  right["mechanisms"] as? [String] == ["OpenComputerUseLockedUseAuthorizationPlugin:remote"] else { throw InstallError.changedPolicy }
            let result = AuthorizationRightRemove(authorization, LockedUseAuthorizationRules.remoteRight)
            guard result == errSecSuccess else { throw InstallError.authentication(result) }
        } else if found != errAuthorizationDenied { throw InstallError.authentication(found) }
        for candidate in [plugin, plugin.deletingLastPathComponent().appendingPathComponent("StagedPlugins/" + pluginName)] {
            if FileManager.default.fileExists(atPath: candidate.path) {
                _ = try verify(candidate, id: "dev.opencomputeruse.locked-use.authorization", team: team)
                try FileManager.default.removeItem(at: candidate)
            }
        }
        if FileManager.default.fileExists(atPath: daemon.path) { try FileManager.default.removeItem(at: daemon) }
        try trustedTreeShallow(root)
        try FileManager.default.removeItem(at: root)
    }
    private static func run(_ path: String, _ args: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.process(process.terminationStatus) }
    }
}
