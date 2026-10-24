import Testing

@testable import Persistence

@Suite struct PersistenceModuleTests {
    @Test func moduleIsLinked() {
        #expect(PersistenceModule.name == "Persistence")
    }
}
