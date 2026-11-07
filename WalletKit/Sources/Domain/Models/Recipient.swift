/// A saved payee (`GET /v1/recipients`).
public struct Recipient: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let currency: Currency
    /// Only the last four digits ever reach the app.
    public let accountLast4: String

    public init(id: String, name: String, currency: Currency, accountLast4: String) {
        self.id = id
        self.name = name
        self.currency = currency
        self.accountLast4 = accountLast4
    }
}
