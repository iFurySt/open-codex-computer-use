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
        switch self {
        case .accessibility:
            return "Drag Open Computer Use above to allow Accessibility"
        case .screenRecording:
            return "Drag Open Computer Use above to allow Screenshots"
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
    public static let bundleIdentifier = "dev.opencodex.OpenComputerUse"

    public static func currentAppBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension == "app" ? bundleURL : nil
    }

    public static func openSystemSettings(for permission: SystemPermissionKind) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    public static func requestAccessibilityPrompt() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

private struct TCCAuthorizationStore {
    let accessibility: Bool?
    let screenRecording: Bool?

    static var current: TCCAuthorizationStore {
        let database = TCCDatabase(path: "/Library/Application Support/com.apple.TCC/TCC.db")
        return TCCAuthorizationStore(
            accessibility: database.authorization(for: .accessibility),
            screenRecording: database.authorization(for: .screenRecording)
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

    func authorization(for service: Service) -> Bool? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
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
        WHERE service = ? AND client = ?
        ORDER BY last_modified DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            if statement != nil {
                sqlite3_finalize(statement)
            }
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, service.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, bundleIdentifier, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return false
        }

        return sqlite3_column_int(statement, 0) == 2
    }
}
