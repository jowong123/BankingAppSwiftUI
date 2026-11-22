import Foundation

/// Small key-value storage for secrets. `KeychainStore` is the real one; tests and the
/// UI-test mock use an in-memory one. Values are opaque `Data`.
public protocol SecureStore: Sendable {
    func data(for key: String) throws(SecureStoreError) -> Data?
    func set(_ data: Data, for key: String) throws(SecureStoreError)
    /// Removing a key that isn't there is not an error.
    func remove(_ key: String) throws(SecureStoreError)
}
