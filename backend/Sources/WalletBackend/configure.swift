import Fluent
import FluentSQLiteDriver
import Vapor

func configure(_ app: Application, environment: BackendEnvironment) async throws {
    app.databases.use(.sqlite(environment.database), as: .sqlite)
    app.migrations.add(CreateSchema())
    app.migrations.add(SeedSandboxData(bcryptCost: environment.bcryptCost, clock: environment.clock))
    try await app.autoMigrate()

    // Outermost first. Request ID wraps everything so errors and logs carry it.
    // The error envelope replaces Vapor's ErrorMiddleware. Simulation sits inside it,
    // so simulated failures are reported as envelopes too.
    app.middleware = Middlewares()
    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(NoStoreMiddleware())
    app.middleware.use(AccessLogMiddleware())
    app.middleware.use(ErrorEnvelopeMiddleware())
    if environment.simulationEnabled {
        app.middleware.use(SimulationMiddleware())
    }

    try routes(app, environment: environment)
}

func routes(_ app: Application, environment: BackendEnvironment) throws {
    let clock = environment.clock
    let api = app.grouped("v1")

    let auth = AuthController(clock: clock, dummyHash: try Bcrypt.hash("unused", cost: environment.bcryptCost))
    api.post("auth", "login", use: auth.login)
    api.post("auth", "refresh", use: auth.refresh)

    let signedIn = api.grouped(
        TokenAuthenticator(clock: clock),
        AuthenticatedUser.guardMiddleware(throwing: APIFailure.unauthorized)
    )

    let accounts = AccountsController()
    signedIn.get("accounts", use: accounts.list)
    signedIn.get("accounts", ":accountID", "transactions", use: accounts.transactions)
    signedIn.get("recipients", use: RecipientsController().list)

    // Quotes honour an Idempotency-Key if sent; transfers require one.
    let quotes = QuotesController(clock: clock, rates: environment.rates)
    signedIn.grouped(IdempotencyMiddleware(required: false, clock: clock)).post("quotes", use: quotes.create)

    let transfers = TransfersController(clock: clock)
    signedIn.grouped(IdempotencyMiddleware(required: true, clock: clock)).post("transfers", use: transfers.create)
    signedIn.get("transfers", ":transferID", use: transfers.show)
}
