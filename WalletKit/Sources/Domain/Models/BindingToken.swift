/// The single-use token login returns. It proves the password and nothing else: it is
/// exchanged once, within 5 minutes, for a session bound to this device (SPEC section 6).
/// Never stored; printing it never shows it.
public struct BindingToken: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String {
        "BindingToken(<redacted>)"
    }
    public var debugDescription: String {
        description
    }
    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
