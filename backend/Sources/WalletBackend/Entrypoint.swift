import Logging
import Vapor

/// `swift run WalletBackend serve` starts the sandbox API on http://127.0.0.1:8080.
/// `DATABASE_PATH` picks the SQLite file (default `wallet-sandbox.sqlite`, gitignored).
/// `SIMULATION_HEADERS=on` enables the `X-Sim-*` fault injection headers (off by default).
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        do {
            let path = Environment.get("DATABASE_PATH") ?? "wallet-sandbox.sqlite"
            let simulation = BackendEnvironment.simulationEnabled(setting: Environment.get("SIMULATION_HEADERS"))
            try await configure(app, environment: .live(databasePath: path, simulationEnabled: simulation))
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
