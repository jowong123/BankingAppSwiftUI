import Foundation
import Security

/// Generic-password Keychain items, readable only while the device is unlocked and never
/// restored to another device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, SPEC
/// section 6). Uses the data-protection Keychain, the iOS behaviour, on every platform.
public struct KeychainStore: SecureStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(for key: String) throws(SecureStoreError) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureStoreError(status: status)
        }
    }

    public func set(_ data: Data, for key: String) throws(SecureStoreError) {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updated = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess {
            return
        }
        guard updated == errSecItemNotFound else {
            throw SecureStoreError(status: updated)
        }
        let item = baseQuery(key).merging(attributes) { _, new in
            new
        }
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw SecureStoreError(status: added)
        }
    }

    public func remove(_ key: String) throws(SecureStoreError) {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError(status: status)
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
