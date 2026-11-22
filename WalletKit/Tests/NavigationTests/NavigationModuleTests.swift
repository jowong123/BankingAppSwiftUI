import Testing

@testable import Navigation

@Suite struct NavigationModuleTests {
    @Test func moduleIsLinked() {
        #expect(NavigationModule.name == "Navigation")
    }
}
