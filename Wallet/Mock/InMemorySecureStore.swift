#if DEBUG
    import Foundation
    import WalletSecurity
    import os

    /// `SecureStore` in memory for UI tests (`-mockServer`): every launch starts signed out,
    /// and nothing touches the simulator's Keychain. Debug only.
    final class InMemorySecureStore: SecureStore {
        private let items = OSAllocatedUnfairLock(initialState: [String: Data]())

        func data(for key: String) throws(SecureStoreError) -> Data? {
            items.withLock {
                $0[key]
            }
        }

        func set(_ data: Data, for key: String) throws(SecureStoreError) {
            items.withLock {
                $0[key] = data
            }
        }

        func remove(_ key: String) throws(SecureStoreError) {
            _ = items.withLock {
                $0.removeValue(forKey: key)
            }
        }
    }
#endif
