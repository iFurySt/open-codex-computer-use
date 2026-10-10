import CoreFoundation
import Foundation
import Security

/// Pure installation planning. No AuthorizationRightSet, privilege elevation,
/// or system writes occur here. The installer must retain the original plan in
/// root-owned storage and re-read immediately before and after each mutation.
public enum LockedUseAuthorizationRules {
    public static let remoteRight = "dev.opencomputeruse.locked-use.remote"
    public enum Failure: Error { case malformed, unsupported, alreadyPresent, changedSincePlanning }

    public struct Plan: Codable, Sendable {
        public let original: Data
        public let installed: Data
    }

    /// Preserve all original rule names and fields. Only an existing OR rule
    /// (k-of-n absent or exactly 1) can safely have another OR branch prepended.
    /// Nested rules such as psso-screensaver retain their own threshold.
    public static func planInstallation(current: Data) throws -> Plan {
        var rule = try decode(current)
        let fallback = try branches(rule)
        guard !fallback.contains(remoteRight) else { throw Failure.alreadyPresent }
        let original = try encode(rule)
        rule["rule"] = [remoteRight] + fallback
        rule["k-of-n"] = 1
        return .init(original: original, installed: try encode(rule))
    }

    /// Conservative restore: an unrelated installer changing any semantic
    /// field invalidates the plan. Never overwrite a new authentication policy.
    public static func planUninstallation(current: Data, plan: Plan) throws -> Data {
        try validate(plan)
        guard try equivalent(current, plan.installed) else { throw Failure.changedSincePlanning }
        return plan.original
    }

    public static func installationStillApplicable(current: Data, plan: Plan) throws -> Bool {
        try validate(plan)
        return try equivalent(current, plan.original)
    }

    public static func installationObserved(current: Data, plan: Plan) throws -> Bool {
        try validate(plan)
        return try equivalent(current, plan.installed)
    }

    public static func loadInstalledPlan() throws -> Plan {
        let data = try LockedUseSecureStore.read(components: ["Library", "Application Support", "OpenComputerUse", "LockedUse", "authorization-plan.json"])
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        try validate(plan)
        return plan
    }

    public static func installedRulesObserved() throws -> Bool {
        let plan = try loadInstalledPlan()
        var policy: CFDictionary?
        guard AuthorizationRightGet("system.login.screensaver", &policy) == errAuthorizationSuccess,
              let policy else { return false }
        let bytes = try PropertyListSerialization.data(fromPropertyList: policy, format: .xml, options: 0)
        guard try installationObserved(current: bytes, plan: plan) else { return false }
        var remote: CFDictionary?
        guard AuthorizationRightGet(remoteRight, &remote) == errAuthorizationSuccess,
              let rule = remote as? [String: Any] else { return false }
        return rule["class"] as? String == "evaluate-mechanisms"
            && rule["mechanisms"] as? [String] == ["OCULockAuth:remote"]
            && (rule["shared"] as? NSNumber)?.boolValue == false
    }

    private static func validate(_ plan: Plan) throws {
        let expected = try planInstallation(current: plan.original)
        guard try equivalent(expected.installed, plan.installed) else { throw Failure.malformed }
    }

    private static func branches(_ rule: [String: Any]) throws -> [String] {
        guard rule["class"] as? String == "rule",
              let names = rule["rule"] as? [String], !names.isEmpty, names.count <= 64,
              Set(names).count == names.count,
              names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && !$0.contains("\0") }) else {
            throw Failure.unsupported
        }
        if let threshold = rule["k-of-n"] {
            guard let number = threshold as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == 1 else { throw Failure.unsupported }
        }
        return names
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 128 * 1024,
              let rule = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              JSONSerialization.isValidJSONObject(rule) else { throw Failure.malformed }
        // authorizationdb generates these timestamps. They are not editable
        // policy and must not make a restored rule appear semantically changed.
        return rule.filter { $0.key != "created" && $0.key != "modified" }
    }

    private static func encode(_ rule: [String: Any]) throws -> Data {
        let data = try PropertyListSerialization.data(fromPropertyList: rule, format: .xml, options: 0)
        guard data.count <= 128 * 1024 else { throw Failure.malformed }
        return data
    }

    private static func equivalent(_ lhs: Data, _ rhs: Data) throws -> Bool {
        // Sorted JSON distinguishes Boolean true from integer 1, unlike common
        // NSNumber/NSDictionary equality, and ignores plist key ordering.
        try JSONSerialization.data(withJSONObject: decode(lhs), options: [.sortedKeys])
            == JSONSerialization.data(withJSONObject: decode(rhs), options: [.sortedKeys])
    }
}
