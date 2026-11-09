/// A failed Keychain call. `status` is the `OSStatus`, e.g. `errSecInteractionNotAllowed`
/// (-25308) while the device is locked.
public struct SecureStoreError: Error, Hashable, Sendable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }
}
