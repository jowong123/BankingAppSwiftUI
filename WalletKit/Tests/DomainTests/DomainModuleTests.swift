import Testing

@testable import Domain

@Suite struct DomainModuleTests {
    @Test func moduleIsLinked() {
        #expect(DomainModule.name == "Domain")
    }
}
