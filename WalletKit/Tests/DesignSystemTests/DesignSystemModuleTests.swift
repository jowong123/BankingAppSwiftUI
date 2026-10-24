import Testing

@testable import DesignSystem

@Suite struct DesignSystemModuleTests {
    @Test func moduleIsLinked() {
        #expect(DesignSystemModule.name == "DesignSystem")
    }
}
