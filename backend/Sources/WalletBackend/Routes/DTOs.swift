import Vapor

// Wire types. They match `backend/openapi.yaml` and the app's `Networking` DTOs.

struct MoneyDTO: Content, Equatable {
    let amountMinor: Int64
    let currency: String
}

struct LoginRequest: Content {
    let email: String
    let password: String
}

struct RefreshRequest: Content {
    let refreshToken: String
}

struct LogoutRequest: Content {
    let refreshToken: String
}

struct SessionTokens: Content {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int64
}

struct AccountDTO: Content {
    let id: String
    let currency: String
    let balance: MoneyDTO
    let updatedAt: Date

    init(_ row: AccountRow) {
        id = row.id
        currency = row.currency
        balance = MoneyDTO(amountMinor: row.balanceMinor, currency: row.currency)
        updatedAt = Date(millis: row.updatedAt)
    }
}

struct AccountsResponse: Content {
    let accounts: [AccountDTO]
}

struct TransactionDTO: Content {
    let id: String
    let accountId: String
    let amount: MoneyDTO
    let description: String
    let createdAt: Date

    init(_ row: TransactionRow) {
        id = row.id
        accountId = row.accountId
        amount = MoneyDTO(amountMinor: row.amountMinor, currency: row.currency)
        description = row.description
        createdAt = Date(millis: row.createdAt)
    }
}

struct TransactionPage: Content {
    let items: [TransactionDTO]
    let nextCursor: String?
}

struct RecipientDTO: Content {
    let id: String
    let name: String
    let currency: String
    let accountLast4: String

    init(_ row: RecipientRow) {
        id = row.id
        name = row.name
        currency = row.currency
        accountLast4 = row.accountLast4
    }
}

struct RecipientsResponse: Content {
    let recipients: [RecipientDTO]
}

struct QuoteRequest: Content {
    let sourceAmount: MoneyDTO
    let targetCurrency: String
}

struct QuoteDTO: Content {
    let id: String
    let sourceAmount: MoneyDTO
    let targetAmount: MoneyDTO
    let fee: MoneyDTO
    let rate: String
    let expiresAt: Date

    init(_ row: QuoteRow) {
        id = row.id
        sourceAmount = MoneyDTO(amountMinor: row.sourceMinor, currency: row.sourceCurrency)
        targetAmount = MoneyDTO(amountMinor: row.targetMinor, currency: row.targetCurrency)
        fee = MoneyDTO(amountMinor: row.feeMinor, currency: row.sourceCurrency)
        rate = row.rate
        expiresAt = Date(millis: row.expiresAt)
    }
}

struct TransferRequest: Content {
    let id: String
    let quoteId: String
    let recipientId: String
    let sourceAccountId: String
}

struct TransferDTO: Content {
    let id: String
    let quoteId: String
    let recipientId: String
    let sourceAccountId: String
    let sourceAmount: MoneyDTO
    let targetAmount: MoneyDTO
    let fee: MoneyDTO
    let status: String
    let failureReason: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ row: TransferRow) {
        id = row.id
        quoteId = row.quoteId
        recipientId = row.recipientId
        sourceAccountId = row.sourceAccountId
        sourceAmount = MoneyDTO(amountMinor: row.sourceMinor, currency: row.sourceCurrency)
        targetAmount = MoneyDTO(amountMinor: row.targetMinor, currency: row.targetCurrency)
        fee = MoneyDTO(amountMinor: row.feeMinor, currency: row.sourceCurrency)
        status = row.status
        failureReason = row.failureReason
        createdAt = Date(millis: row.createdAt)
        updatedAt = Date(millis: row.updatedAt)
    }
}

// MARK: - Device binding and signing (SPEC section 6)

/// `POST /v1/auth/login`: a single-use token for `POST /v1/devices`. No session yet.
struct BindingTokenResponse: Content {
    let bindingToken: String
    let expiresIn: Int64
}

struct DeviceBindingRequest: Content {
    let bindingToken: String
    /// Base64 X9.63 P-256 public key from the Secure Enclave. Absent when the phone has no
    /// Face ID or Touch ID set up: the device can then view but not send.
    let signingKey: String?
    /// Required unless the server runs with `ATTEST_MODE=sandbox`.
    let attestation: AttestationDTO?
}

/// `object` is the CBOR attestation from `DCAppAttestService.attestKey`, its client data
/// `"<bindingToken>.<signingKey or empty>"`. Both base64.
struct AttestationDTO: Content {
    let keyId: String
    let object: String
}

struct BoundDevice: Content {
    let deviceId: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int64
}

struct ChallengeDTO: Content {
    let nonce: String
    let expiresAt: Date
}

/// The confirm body. `payload` is the exact bytes that were signed, base64, so the server
/// never has to reproduce the app's JSON to check the signature.
struct ConfirmRequest: Content {
    let payload: String
    /// Base64 DER ECDSA P-256 signature over SHA-256 of the payload.
    let signature: String
    /// Base64 CBOR App Attest assertion over the payload. Required for an attested device.
    let assertion: String?
}

/// What the user approved with Face ID (SPEC section 6). Every field must match the
/// stored transfer and an unused, unexpired challenge.
struct ConfirmPayload: Codable, Equatable {
    let transferId: String
    let amountMinor: Int64
    let currency: String
    let recipientId: String
    let quoteId: String
    let nonce: String
    /// Unix milliseconds when the app signed.
    let timestamp: Int64
}
