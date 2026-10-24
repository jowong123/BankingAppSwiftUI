import Testing

@testable import AccountsFeature

@Suite struct AccountsFeatureModuleTests {
    @Test func moduleIsLinked() {
        #expect(AccountsFeatureModule.name == "AccountsFeature")
    }
}
