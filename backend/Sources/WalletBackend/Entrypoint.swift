import Logging
import Vapor

/// `swift run WalletBackend serve` starts the sandbox API on http://127.0.0.1:8080.
/// `DATABASE_PATH` picks the SQLite file (default `wallet-sandbox.sqlite`, gitignored).
/// `SIMULATION_HEADERS=on` enables the `X-Sim-*` fault injection headers (off by default).
/// `APP_ATTEST_APP_ID=<TeamID>.<bundle ID>` checks App Attest, production keys only unless
/// `APP_ATTEST_ENV=development` (debug builds); `ATTEST_MODE=sandbox` skips it for the
/// simulator. One of the two is required (ADR-023).
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        do {
            let path = Environment.get("DATABASE_PATH") ?? "wallet-sandbox.sqlite"
            let simulation = BackendEnvironment.simulationEnabled(setting: Environment.get("SIMULATION_HEADERS"))
            let attestation = try AttestationMode.from(
                mode: Environment.get("ATTEST_MODE"),
                appID: Environment.get("APP_ATTEST_APP_ID"),
                environment: Environment.get("APP_ATTEST_ENV")
            )
            try await configure(
                app,
                environment: .live(databasePath: path, simulationEnabled: simulation, attestation: attestation)
            )
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
