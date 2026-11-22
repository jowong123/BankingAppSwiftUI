import Testing

@testable import IdentitySDK

@Suite struct IdentitySDKModuleTests {
    @Test func moduleIsLinked() {
        #expect(IdentitySDKModule.name == "IdentitySDK")
    }
}
