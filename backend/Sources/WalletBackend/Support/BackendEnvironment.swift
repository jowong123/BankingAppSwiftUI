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

    /// Only the exact value `on` enables simulation; unset, empty or anything else keeps it off.
    static func simulationEnabled(setting: String?) -> Bool {
        setting == "on"
    }

    static func live(databasePath: String, simulationEnabled: Bool) -> BackendEnvironment {
        BackendEnvironment(
            database: .init(storage: .file(path: databasePath)),
            clock: .system,
            rates: .live,
            bcryptCost: 12,
            simulationEnabled: simulationEnabled
        )
    }
}

/// The current time, injected so tests can move past quote and token expiry.
struct BackendClock: Sendable {
    let now: @Sendable () -> Date

    static let system = BackendClock { Date() }

    /// A clock tests can move forward.
    static func manual(start: Date) -> (BackendClock, @Sendable (TimeInterval) -> Void) {
        let box = NIOLockedValueBox(start)
        let clock = BackendClock { box.withLockedValue { $0 } }
        return (clock, { seconds in box.withLockedValue { $0 += seconds } })
    }

    var nowMillis: Int64 { Int64((now().timeIntervalSince1970 * 1000).rounded(.down)) }
}

extension Date {
    init(millis: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
