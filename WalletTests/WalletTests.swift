import Testing

@testable import Wallet

@MainActor
struct AppEnvironmentTests {
    @Test func liveEnvironmentLinksEveryAppFacingModule() {
        let environment = AppEnvironment.live()
        #expect(Set(environment.linkedModules).count == 11)
        #expect(AppCoordinator(environment: environment).linkedModuleCount == 11)
    }
}
