import Testing

@testable import Networking

@Suite struct NetworkingModuleTests {
    @Test func moduleIsLinked() {
        #expect(NetworkingModule.name == "Networking")
    }
}
