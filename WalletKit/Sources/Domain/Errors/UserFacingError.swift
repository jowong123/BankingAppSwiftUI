/// An error ready to show: already localised by the feature that built it.
public struct UserFacingError: Error, Hashable, Sendable {
    public let title: String
    public let message: String
    /// Whether a Retry button makes sense (offline, server down), or the user must do
    /// something else first (sign in again).
    public let canRetry: Bool

    public init(title: String, message: String, canRetry: Bool) {
        self.title = title
        self.message = message
        self.canRetry = canRetry
    }
}
