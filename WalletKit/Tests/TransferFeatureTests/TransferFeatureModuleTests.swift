import Testing

@testable import TransferFeature

@Suite struct TransferFeatureModuleTests {
    @Test func moduleIsLinked() {
        #expect(TransferFeatureModule.name == "TransferFeature")
    }
}
