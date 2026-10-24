import Testing

@testable import WalletSecurity

@Suite struct WalletSecurityModuleTests {
    @Test func moduleIsLinked() {
        #expect(WalletSecurityModule.name == "WalletSecurity")
    }
}
