import Foundation
import Security
import LocalAuthentication

/// Isolated validation items only. Never enumerate, inspect, export or modify
/// an existing application's Keychain records. Never allow authentication UI.
public final class LockedUseKeychainProbe {
    public enum Failure: Error { case operation(OSStatus), verification }
    private let account = UUID().uuidString
    private let service = "dev.opencomputeruse.locked-use.validation"
    private var secret = Data()
    private var created: [Bool] = []
    public let includesDataProtection: Bool

    public init(includeDataProtection: Bool = true) throws {
        includesDataProtection = includeDataProtection
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.verification }
        secret = Data(bytes)
        do {
            for protection in (includeDataProtection ? [false, true] : [false]) {
                var attributes = query(dataProtection: protection)
                attributes[kSecValueData as String] = secret
                if protection { attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
                let status = SecItemAdd(attributes as CFDictionary, nil)
                guard status == errSecSuccess else { throw Failure.operation(status) }
                created.append(protection)
            }
            try verify()
        } catch { cleanup(); throw error }
    }

    public func verify() throws {
        guard created.count == (includesDataProtection ? 2 : 1) else { throw Failure.verification }
        for protection in created {
            var attributes = query(dataProtection: protection)
            attributes[kSecReturnData as String] = true
            attributes[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(attributes as CFDictionary, &value)
            guard status == errSecSuccess else { throw Failure.operation(status) }
            guard let data = value as? Data, data.count == secret.count,
                  zip(data, secret).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else { throw Failure.verification }
        }
    }

    /// Cleanup can fail while the OS denies locked Keychain operations. The
    /// caller retains this object and retries after a normal manual unlock.
    @discardableResult public func cleanup() -> Bool {
        created = created.filter {
            let result = SecItemDelete(query(dataProtection: $0) as CFDictionary)
            return result != errSecSuccess && result != errSecItemNotFound
        }
        if created.isEmpty { secret.resetBytes(in: 0..<secret.count); return true }
        return false
    }
    private func query(dataProtection: Bool) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: dataProtection,
         kSecUseAuthenticationContext as String: context]
    }
    deinit { cleanup() }
}
