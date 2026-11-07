import Foundation
import Testing

@testable import AccountsFeature

@Suite struct AccountsStringsTests {
    /// Every key the code asks for exists in `Localizable.strings`. A missing key would
    /// show up on screen as "accounts.error.offline.title".
    @Test func everyKeyTheCodeUsesIsInTheStringsFile() throws {
        let source = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/AccountsFeature/AccountsStrings.swift")
                .standardized,
            encoding: .utf8
        )
        let usedKeys = source.matches(of: /text\("([^"]+)"\)/).map {
            String($0.output.1)
        }
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "strings"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])

        #expect(usedKeys.count == 12)
        for key in usedKeys {
            #expect(table[key] != nil, "\(key) is missing from Localizable.strings")
        }
        #expect(Set(table.keys) == Set(usedKeys), "Localizable.strings has keys the code never uses")
    }

    @Test func stringsResolveToTheirEnglishText() {
        #expect(AccountsStrings.title == "Accounts")
        #expect(AccountsStrings.offlineTitle == "You're offline")
        #expect(AccountsStrings.couldNotUpdate == "Couldn't update. Pull down to try again.")
    }
}
