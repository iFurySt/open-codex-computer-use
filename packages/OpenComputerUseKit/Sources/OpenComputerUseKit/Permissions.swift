import ApplicationServices
import AppKit
import Foundation
import SQLite3

public enum SystemPermissionKind: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording

    public var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screenshots"
        }
    }

    public var subtitle: String {
        switch self {
        case .accessibility:
            return "Allows Open Computer Use to access app interfaces"
        case .screenRecording:
            return "Open Computer Use uses screenshots to know where to click"
        }
    }

    public var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }

    public var dragInstruction: String {
        let appName = PermissionSupport.currentBundleDisplayName()
        switch self {
        case .accessibility:
            return "Drag \(appName) above to allow Accessibility"
        case .screenRecording:
            return "Drag \(appName) above to allow Screenshots"
        }
    }

    public var systemSettingsTitle: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .screenRecording:
            return "Screen & System Audio Recording"
        }
    }

    public var symbolName: String {
        switch self {
        case .accessibility:
            return "figure.arms.open"
        case .screenRecording:
            return "camera.viewfinder"
        }
    }
}

public struct PermissionDiagnostics: Sendable {
    public let accessibilityTrusted: Bool
    public let screenCaptureGranted: Bool

    public static func current() -> PermissionDiagnostics {
        let persisted = TCCAuthorizationStore.current

        return PermissionDiagnostics(
            accessibilityTrusted: persisted.accessibility ?? AXIsProcessTrusted(),
            screenCaptureGranted: persisted.screenRecording ?? CGPreflightScreenCaptureAccess()
        )
    }

    public var summary: String {
        "Permissions: accessibility=\(accessibilityTrusted ? "granted" : "missing"), screenRecording=\(screenCaptureGranted ? "granted" : "missing")"
    }

    public var missingPermissions: [SystemPermissionKind] {
        SystemPermissionKind.allCases.filter { !isGranted($0) }
    }

    public func isGranted(_ permission: SystemPermissionKind) -> Bool {
        switch permission {
        case .accessibility:
            return accessibilityTrusted
        case .screenRecording:
            return screenCaptureGranted
        }
    }

    public var allGranted: Bool {
        accessibilityTrusted && screenCaptureGranted
    }
}

public enum PermissionSupport {
    public static let bundleDisplayName = "Open Computer Use"
    public static let bundleIdentifier = "com.ifuryst.opencomputeruse"
    public static let developmentBundleDisplayName = "Open Computer Use (Dev)"
    public static let developmentBundleIdentifier = "com.ifuryst.opencomputeruse.dev"
    private static let releaseAppBundleName = "\(bundleDisplayName).app"
    private static let developmentAppBundleName = "\(developmentBundleDisplayName).app"
    private static let appVariantInfoKey = "OpenComputerUseAppVariant"
    private static let npmPackageNames = [
        "open-computer-use",
        "open-computer-use-mcp",
        "open-codex-computer-use-mcp",
    ]

    public static func currentBundleDisplayName(bundle: Bundle = .main) -> String {
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String

        return displayName ?? bundleName ?? (isDevelopmentBundleIdentifier(bundle.bundleIdentifier) ? developmentBundleDisplayName : bundleDisplayName)
    }

    public static func isOpenComputerUseBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == Self.bundleIdentifier || bundleIdentifier == developmentBundleIdentifier
    }

    public static func currentAppBundleURL() -> URL? {
        let runningBundleURL = resolvedMainAppBundleURL()
        return preferredPermissionAppBundleURL(
            preferredInstalledBundleURL: preferredInstalledAppBundleURL(),
            runningBundleURL: runningBundleURL,
            fallbackDevelopmentBundleURL: fallbackDevelopmentAppBundleURL(),
            preferRunningBundle: runningBundleURL != nil
        )
    }

    public static func currentPermissionClients() -> [PermissionClientRecord] {
        let runningBundleURL = resolvedMainAppBundleURL()
        let mainBundleIdentifier = resolvedBundleIdentifier(for: runningBundleURL) ?? Bundle.main.bundleIdentifier
        return permissionClients(
            primaryBundleURL: currentAppBundleURL(),
            runningBundleURL: runningBundleURL,
            mainBundleIdentifier: mainBundleIdentifier,
            includeCanonicalBundleIdentifier: !isDevelopmentBundleIdentifier(mainBundleIdentifier)
        )
    }

    public static func openSystemSettings(for permission: SystemPermissionKind) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    public static func requestAccessibilityPrompt() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func preferredPermissionAppBundleURL(
        preferredInstalledBundleURL: URL?,
        runningBundleURL: URL?,
        fallbackDevelopmentBundleURL: URL?,
        preferRunningBundle: Bool = false
    ) -> URL? {
        if preferRunningBundle {
            return runningBundleURL ?? preferredInstalledBundleURL ?? fallbackDevelopmentBundleURL
        }

        return preferredInstalledBundleURL ?? runningBundleURL ?? fallbackDevelopmentBundleURL
    }

    static func permissionClients(
        primaryBundleURL: URL?,
        runningBundleURL: URL?,
        mainBundleIdentifier: String?,
        includeCanonicalBundleIdentifier: Bool = true,
        canonicalBundleIdentifier: String = bundleIdentifier
    ) -> [PermissionClientRecord] {
        var records: [PermissionClientRecord] = []
        var seen = Set<PermissionClientRecord>()

        func append(_ record: PermissionClientRecord?) {
            guard let record, seen.insert(record).inserted else {
                return
            }
            records.append(record)
        }

        if includeCanonicalBundleIdentifier {
            append(PermissionClientRecord(identifier: canonicalBundleIdentifier, type: 0))
        }

        if let mainBundleIdentifier,
           (!includeCanonicalBundleIdentifier || mainBundleIdentifier != canonicalBundleIdentifier)
        {
            append(PermissionClientRecord(identifier: mainBundleIdentifier, type: 0))
        }

        if let primaryBundleURL {
            append(PermissionClientRecord(identifier: primaryBundleURL.standardizedFileURL.path, type: 1))
        }

        if let runningBundleURL {
            append(PermissionClientRecord(identifier: runningBundleURL.standardizedFileURL.path, type: 1))
        }

        return records
    }

    static func preferredInstalledAppBundleURL(candidates: [URL]) -> URL? {
        var seenPaths = Set<String>()

        for candidate in candidates {
            let standardizedURL = candidate.standardizedFileURL
            if seenPaths.insert(standardizedURL.path).inserted {
                return standardizedURL
            }
        }

        return nil
    }

    private static func preferredInstalledAppBundleURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        var seenPaths = Set<String>()

        func appendCandidate(_ bundleURL: URL?) {
            guard let bundleURL else {
                return
            }

            let standardizedURL = bundleURL.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                return
            }

            guard isValidAppBundle(standardizedURL) else {
                return
            }

            candidates.append(standardizedURL)
        }

        appendCandidate(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier))

        for directory in standardApplicationDirectories() {
            appendCandidate(directory.appendingPathComponent(releaseAppBundleName, isDirectory: true))
        }

        for nodeModulesRoot in npmGlobalNodeModulesRoots() {
            for packageName in npmPackageNames {
                appendCandidate(
                    nodeModulesRoot
                    .appendingPathComponent(packageName, isDirectory: true)
                    .appendingPathComponent("dist", isDirectory: true)
                    .appendingPathComponent(releaseAppBundleName, isDirectory: true)
                )
            }
        }

        for prefix in homebrewPrefixes() {
            appendCandidate(prefix
                .appendingPathComponent("Caskroom", isDirectory: true)
                .appendingPathComponent("open-computer-use", isDirectory: true)
                .appendingPathComponent(releaseAppBundleName, isDirectory: true)
            )

            let caskroomRoot = prefix
                .appendingPathComponent("Caskroom", isDirectory: true)
                .appendingPathComponent("open-computer-use", isDirectory: true)
            if let versionDirectories = try? fileManager.contentsOfDirectory(at: caskroomRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for versionDirectory in versionDirectories {
                    appendCandidate(versionDirectory.appendingPathComponent(releaseAppBundleName, isDirectory: true))
                }
            }

            let cellarRoot = prefix
                .appendingPathComponent("Cellar", isDirectory: true)
                .appendingPathComponent("open-computer-use", isDirectory: true)
            if let versionDirectories = try? fileManager.contentsOfDirectory(at: cellarRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for versionDirectory in versionDirectories {
                    appendCandidate(versionDirectory
                        .appendingPathComponent("dist", isDirectory: true)
                        .appendingPathComponent(releaseAppBundleName, isDirectory: true)
                    )
                }
            }
        }

        return preferredInstalledAppBundleURL(candidates: candidates)
    }

    private static func fallbackDevelopmentAppBundleURL() -> URL? {
        guard let executableURL = Bundle.main.executableURL?.standardizedFileURL else {
            return nil
        }

        var directoryURL = executableURL.deletingLastPathComponent()

        while directoryURL.path != "/" {
            for (bundleName, acceptedBundleIdentifiers) in [
                (developmentAppBundleName, Set([developmentBundleIdentifier])),
                (releaseAppBundleName, Set([bundleIdentifier])),
            ] {
                let candidate = directoryURL
                    .appendingPathComponent("dist", isDirectory: true)
                    .appendingPathComponent(bundleName, isDirectory: true)

                if isValidAppBundle(candidate, acceptedBundleIdentifiers: acceptedBundleIdentifiers) {
                    return candidate
                }
            }

            let parentURL = directoryURL.deletingLastPathComponent()
            if parentURL == directoryURL {
                break
            }
            directoryURL = parentURL
        }

        return nil
    }

    private static func npmGlobalNodeModulesRoots() -> [URL] {
        let candidatePrefixes = packageManagerPrefixes()
        let roots = candidatePrefixes.map {
            $0.appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("node_modules", isDirectory: true)
                .standardizedFileURL
        }

        return uniqueStandardizedURLs(roots)
    }

    private static func standardApplicationDirectories() -> [URL] {
        let fileManager = FileManager.default
        let directories = fileManager.urls(for: .applicationDirectory, in: .allDomainsMask).map {
            $0.standardizedFileURL
        }

        return uniqueStandardizedURLs(directories)
    }

    private static func homebrewPrefixes() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let prefixes = [
            env["HOMEBREW_PREFIX"],
            env["npm_config_prefix"],
            env["NPM_CONFIG_PREFIX"],
            env["PREFIX"],
            "/opt/homebrew",
            "/usr/local",
        ]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

        return uniqueStandardizedURLs(prefixes)
    }

    private static func packageManagerPrefixes() -> [URL] {
        let env = ProcessInfo.processInfo.environment
        let prefixes = [
            env["npm_config_prefix"],
            env["NPM_CONFIG_PREFIX"],
            env["PREFIX"],
            env["HOMEBREW_PREFIX"],
            NSHomeDirectory() + "/.npm-global",
            "/opt/homebrew",
            "/usr/local",
        ]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

        return uniqueStandardizedURLs(prefixes)
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var uniqueURLs: [URL] = []
        var seenPaths = Set<String>()

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            if seenPaths.insert(standardizedURL.path).inserted {
                uniqueURLs.append(standardizedURL)
            }
        }

        return uniqueURLs
    }

    private static func resolvedMainAppBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app",
              isValidAppBundle(bundleURL, acceptedBundleIdentifiers: [bundleIdentifier, developmentBundleIdentifier])
        else {
            return nil
        }

        return bundleURL
    }

    private static func resolvedBundleIdentifier(for bundleURL: URL?) -> String? {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else {
            return nil
        }

        return bundle.bundleIdentifier
    }

    private static func isDevelopmentBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == developmentBundleIdentifier
    }

    private static func isDevelopmentAppBundle(_ bundleURL: URL?) -> Bool {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else {
            return false
        }

        if let variant = bundle.object(forInfoDictionaryKey: appVariantInfoKey) as? String,
           variant.caseInsensitiveCompare("dev") == .orderedSame
        {
            return true
        }

        if isDevelopmentBundleIdentifier(bundle.bundleIdentifier) {
            return true
        }

        return bundleURL.lastPathComponent == developmentAppBundleName
    }

    private static func isValidAppBundle(
        _ bundleURL: URL,
        acceptedBundleIdentifiers: Set<String> = [bundleIdentifier]
    ) -> Bool {
        let fileManager = FileManager.default
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlistURL.path),
              let bundle = Bundle(url: bundleURL),
              let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String,
              !executableName.isEmpty,
              acceptedBundleIdentifiers.contains(bundle.bundleIdentifier ?? "")
        else {
            return false
        }

        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        return fileManager.fileExists(atPath: executableURL.path)
    }
}

public struct PermissionClientRecord: Sendable, Equatable, Hashable {
    public let identifier: String
    public let type: Int32
}

func tccAuthorizationGranted(authValues: [Int32?]) -> Bool {
    authValues.contains(2)
}

private struct TCCAuthorizationStore {
    let accessibility: Bool?
    let screenRecording: Bool?

    static var current: TCCAuthorizationStore {
        let database = TCCDatabase(path: "/Library/Application Support/com.apple.TCC/TCC.db")
        let clients = PermissionSupport.currentPermissionClients()
        return TCCAuthorizationStore(
            accessibility: database.authorization(for: .accessibility, clients: clients),
            screenRecording: database.authorization(for: .screenRecording, clients: clients)
        )
    }
}

private struct TCCDatabase {
    enum Service: String {
        case accessibility = "kTCCServiceAccessibility"
        case screenRecording = "kTCCServiceScreenCapture"
    }

    private let path: String
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) {
        self.path = path
    }

    func authorization(for service: Service, clients: [PermissionClientRecord]) -> Bool? {
        guard !clients.isEmpty else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT auth_value
        FROM access
        WHERE service = ? AND client = ? AND client_type = ?
        ORDER BY last_modified DESC
        LIMIT 1;
        """

        var authValues: [Int32?] = []

        for client in clients {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
                return nil
            }

            sqlite3_bind_text(statement, 1, service.rawValue, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, client.identifier, -1, sqliteTransient)
            sqlite3_bind_int(statement, 3, client.type)

            if sqlite3_step(statement) == SQLITE_ROW {
                authValues.append(sqlite3_column_int(statement, 0))
                sqlite3_finalize(statement)
                continue
            }

            sqlite3_finalize(statement)
        }

        return tccAuthorizationGranted(authValues: authValues)
    }
}
