import Testing

@testable import OnboardingFeature

@Suite struct OnboardingFeatureModuleTests {
    @Test func moduleIsLinked() {
        #expect(OnboardingFeatureModule.name == "OnboardingFeature")
    }
}
