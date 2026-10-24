import Testing

@testable import AuthFeature

@Suite struct AuthFeatureModuleTests {
    @Test func moduleIsLinked() {
        #expect(AuthFeatureModule.name == "AuthFeature")
    }
}
