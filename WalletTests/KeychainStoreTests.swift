import Foundation
import Security
import Testing
import WalletSecurity

/// Runs inside the app on the simulator: the iOS Keychain isn't reachable from `swift test`.
@Suite(.serialized) struct KeychainStoreTests {
    let store = KeychainStore(service: "jw.Wallet.tests.\(UUID().uuidString)")

    @Test func savesReadsOverwritesAndRemoves() throws {
        #expect(try store.data(for: "k") == nil)

        try store.set(Data("one".utf8), for: "k")
        #expect(try store.data(for: "k") == Data("one".utf8))

        try store.set(Data("two".utf8), for: "k")
        #expect(try store.data(for: "k") == Data("two".utf8))

        try store.remove("k")
        #expect(try store.data(for: "k") == nil)
        try store.remove("k")
    }

    /// Readable only while the phone is unlocked, and never restored to another device (SPEC section 6).
    @Test func itemsAreThisDeviceOnlyAndNeedTheDeviceUnlocked() throws {
        try store.set(Data("secret".utf8), for: "k")
        defer {
            try? store.remove("k")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "k",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?

        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(
            attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                as String)
    }

    @Test func servicesDoNotSeeEachOthersItems() throws {
        let other = KeychainStore(service: store.service + ".other")
        try store.set(Data("mine".utf8), for: "k")
        defer {
            try? store.remove("k")
        }

        #expect(try other.data(for: "k") == nil)
    }
}
