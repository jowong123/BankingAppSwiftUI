/// Approves a transfer with the device's Secure Enclave key, behind Face ID (SPEC section 6,
/// ADR-008). Declared here so TransferFeature can use it; `TransferSigner` in WalletSecurity
/// implements it.
public protocol TransferSigning: Sendable {
    /// Never shows a prompt.
    func availability() async -> SigningAvailability

    /// Shows the Face ID prompt with `reason`, then signs the canonical form of `payload`.
    func sign(_ payload: ConfirmPayload, reason: String) async throws(SigningError) -> SignedConfirmation
}
