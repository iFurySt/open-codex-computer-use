import Foundation

/// Diagnostic classification against OS-owned localization resources. Return
/// only static resource keys, never an AX label, account name or field value.
enum LockScreenPublicLabels {
    private static let keys: [String: Set<String>] = {
        var result: [String: Set<String>] = [:]
        let roots = ["/System/Library/CoreServices/loginwindow.app/Contents/Resources",
            "/System/Library/PrivateFrameworks/LoginUIKit.framework/Versions/A/Resources",
            "/System/Library/PrivateFrameworks/LoginUIKit.framework/Versions/A/Frameworks/LoginUICore.framework/Versions/A/Resources"]
        for root in roots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".loctable") {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(name)), data.count <= 2 * 1024 * 1024,
                      let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                for locale in table.values {
                    guard let values = locale as? [String: String] else { continue }
                    for (key, value) in values where !value.isEmpty && key.utf8.count <= 100 && key.range(of: "^[A-Z0-9_]+$", options: .regularExpression) != nil {
                        result[value, default: []].insert(key)
                    }
                }
            }
        }
        return result
    }()
    static func matchingKeys(_ labels: [String]) -> [String] {
        Array(Set(labels.flatMap { Array(keys[$0] ?? []) })).sorted()
    }
}
