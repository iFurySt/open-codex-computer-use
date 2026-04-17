import AppKit
import Foundation

public struct RunningAppDescriptor {
    public let name: String
    public let bundleIdentifier: String?
    public let pid: pid_t
    public let runningApplication: NSRunningApplication
}

enum AppDiscovery {
    static func listApps() -> [RunningAppDescriptor] {
        NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }

                return appName(lhs).localizedCaseInsensitiveCompare(appName(rhs)) == .orderedAscending
            }
            .map { app in
                RunningAppDescriptor(
                    name: appName(app),
                    bundleIdentifier: app.bundleIdentifier,
                    pid: app.processIdentifier,
                    runningApplication: app
                )
            }
    }

    static func resolve(_ query: String) throws -> RunningAppDescriptor {
        let running = listApps()

        if let match = running.first(where: { descriptor in
            descriptor.name.caseInsensitiveCompare(query) == .orderedSame
                || descriptor.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame
                || descriptor.runningApplication.executableURL?.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(query) == .orderedSame
        }) {
            return match
        }

        try launchIfPossible(query)

        for _ in 0..<20 {
            if let launched = listApps().first(where: { descriptor in
                descriptor.name.caseInsensitiveCompare(query) == .orderedSame
                    || descriptor.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame
            }) {
                return launched
            }

            Thread.sleep(forTimeInterval: 0.25)
        }

        throw ComputerUseError.appNotFound(query)
    }

    private static func launchIfPossible(_ query: String) throws {
        if query.contains(".") {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) {
                try NSWorkspace.shared.launchApplication(at: appURL, options: [], configuration: [:])
            }
            return
        }

        guard let fullPath = NSWorkspace.shared.fullPath(forApplication: query) else {
            return
        }

        try NSWorkspace.shared.launchApplication(at: URL(fileURLWithPath: fullPath), options: [], configuration: [:])
    }

    static func appName(_ app: NSRunningApplication) -> String {
        app.localizedName
            ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            ?? app.executableURL?.lastPathComponent
            ?? "pid-\(app.processIdentifier)"
    }
}
