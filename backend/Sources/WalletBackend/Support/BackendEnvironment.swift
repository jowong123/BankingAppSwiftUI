import FluentSQLiteDriver
import NIOConcurrencyHelpers
import Vapor

/// Everything the routes depend on that tests need to control.
struct BackendEnvironment: Sendable {
    var database: SQLiteConfiguration
    var clock: BackendClock
    var rates: RateTable
    /// Bcrypt cost for the seeded sandbox passwords. Tests use the minimum to stay fast.
    var bcryptCost: Int
    /// `X-Sim-*` fault injection. It runs before authentication and can hold a connection
    /// for 30 s, so it is off unless the server is started with `SIMULATION_HEADERS=on`.
    var simulationEnabled: Bool
    /// How device binding and confirms prove they come from a genuine app (ADR-023, ADR-024).
    var attestation: AttestationMode

    /// Only the exact value `on` enables simulation; unset, empty or anything else keeps it off.
    static func simulationEnabled(setting: String?) -> Bool {
        setting == "on"
    }

    static func live(databasePath: String, simulationEnabled: Bool, attestation: AttestationMode)
        -> BackendEnvironment
    {
        BackendEnvironment(
            database: .init(storage: .file(path: databasePath)),
            clock: .system,
            rates: .live,
            bcryptCost: 12,
            simulationEnabled: simulationEnabled,
            attestation: attestation
        )
    }
}

/// Whether App Attest is required.
///
/// - `apple`: every binding must carry a valid App Attest attestation for `appID`, and every
///   confirm from such a device a valid assertion. The default.
/// - `sandbox`: attestation is not asked for, because the simulator can't make one. The
///   signing key, the nonce and the payload are still checked on every confirm. Only by
///   starting the server with `ATTEST_MODE=sandbox` (ADR-023).
enum AttestationMode: Sendable {
    case apple(AppAttestVerifier)
    case sandbox

    /// Reads `ATTEST_MODE` and `APP_ATTEST_APP_ID`. Fails closed: with neither set, the server
    /// refuses to start rather than quietly accepting unattested devices.
    /// Development App Attest keys (debug builds, not risk-assessed by Apple) only with
    /// `APP_ATTEST_ENV=development`; unset means production.
    static func from(mode: String?, appID: String?, environment: String?) throws -> AttestationMode {
        let allowsDevelopment: Bool
        switch environment {
        case nil, "", "production": allowsDevelopment = false
        case "development": allowsDevelopment = true
        default: throw ConfigurationError("APP_ATTEST_ENV must be production or development.")
        }
        switch mode {
        case "sandbox":
            return .sandbox
        case nil, "", "apple":
            guard let appID, !appID.isEmpty else {
                throw ConfigurationError(
                    "Set APP_ATTEST_APP_ID=<TeamID>.<bundle ID>, or ATTEST_MODE=sandbox for the simulator."
                )
            }
            return .apple(
                AppAttestVerifier(
                    appID: appID, roots: [try AppAttestVerifier.appleRoot()], allowsDevelopment: allowsDevelopment)
            )
        default:
            throw ConfigurationError("ATTEST_MODE must be apple or sandbox.")
        }
    }
}

struct ConfigurationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// The current time, injected so tests can move past quote and token expiry.
struct BackendClock: Sendable {
    let now: @Sendable () -> Date

    static let system = BackendClock {
        Date()
    }

    /// A clock tests can move forward.
    static func manual(start: Date) -> (BackendClock, @Sendable (TimeInterval) -> Void) {
        let box = NIOLockedValueBox(start)
        let clock = BackendClock {
            box.withLockedValue {
                $0
            }
        }
        return (
            clock,
            { seconds in
                box.withLockedValue {
                    $0 += seconds
                }
            }
        )
    }

    var nowMillis: Int64 {
        Int64((now().timeIntervalSince1970 * 1000).rounded(.down))
    }
}

extension Date {
    init(millis: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
