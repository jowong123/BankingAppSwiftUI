import Domain
import Foundation

struct LoginRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let email: String
    let password: String

    var description: String {
        "LoginRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

struct RefreshRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let refreshToken: String

    var description: String {
        "RefreshRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

struct LogoutRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let refreshToken: String

    var description: String {
        "LogoutRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// Tokens from login and refresh. `RemoteAuthAPI` turns them into `SessionTokens`, which
/// go straight to the Keychain. Redacted so an accidental log or crash report can't leak them.
struct SessionTokensDTO: Decodable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    let accessToken: String
    let refreshToken: String
    /// Access-token lifetime in seconds.
    let expiresIn: Int

    var description: String {
        "SessionTokensDTO(<redacted>)"
    }
    var debugDescription: String {
        description
    }
    /// Empty, so `dump`, debuggers and test-failure diffs can't print the tokens either.
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// Login's answer: a single-use token for `POST /v1/devices`, not a session.
struct BindingTokenDTO: Decodable, Sendable, CustomStringConvertible, CustomReflectable {
    let bindingToken: String
    let expiresIn: Int

    var description: String {
        "BindingTokenDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// `POST /v1/devices`. Keys and attestation objects are base64.
struct DeviceBindingRequestDTO: Encodable, Sendable, CustomStringConvertible, CustomReflectable {
    let bindingToken: String
    let signingKey: String?
    let attestation: AttestationDTO?

    init(_ request: DeviceBindingRequest) {
        bindingToken = request.bindingToken.value
        signingKey = request.signingKey?.base64EncodedString()
        attestation = request.attestation.map {
            AttestationDTO(keyId: $0.keyID, object: $0.object.base64EncodedString())
        }
    }

    var description: String {
        "DeviceBindingRequestDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

struct AttestationDTO: Encodable, Sendable {
    let keyId: String
    let object: String
}

/// The session for the newly bound device.
struct BoundDeviceDTO: Decodable, Sendable, CustomStringConvertible, CustomReflectable {
    let deviceId: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    var description: String {
        "BoundDeviceDTO(<redacted>)"
    }
    var customMirror: Mirror {
        Mirror(self, children: [:])
    }

    func session() -> BoundSession {
        BoundSession(deviceID: deviceId, tokens: SessionTokens(accessToken: accessToken, refreshToken: refreshToken))
    }
}
