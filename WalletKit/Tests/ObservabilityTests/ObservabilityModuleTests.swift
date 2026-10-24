import Testing

@testable import Observability

@Suite struct ObservabilityModuleTests {
    @Test func moduleIsLinked() {
        #expect(ObservabilityModule.name == "Observability")
    }
}
