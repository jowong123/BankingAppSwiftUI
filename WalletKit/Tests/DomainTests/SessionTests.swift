import Foundation
import Testing

@testable import Domain

@Suite struct AutoLockPolicyTests {
    let policy = AutoLockPolicy()

    @Test(arguments: [(299, false), (300, true), (301, true)])
    func locksAfterFiveMinutesWithoutInteraction(seconds: Int, locks: Bool) {
        #expect(policy.shouldLock(idle: .seconds(seconds)) == locks)
    }

    @Test(arguments: [(119, false), (120, true), (600, true)])
    func locksAfterTwoMinutesInTheBackground(seconds: Int, locks: Bool) {
        #expect(policy.shouldLockOnReturn(away: .seconds(seconds)) == locks)
    }
}

@Suite struct SessionTokensTests {
    @Test func tokensNeverAppearWhenPrinted() {
        let tokens = SessionTokens(accessToken: "secret-access", refreshToken: "secret-refresh")
        let printed = "\(tokens) \(String(reflecting: tokens))"

        #expect(!printed.contains("secret-access"))
        #expect(!printed.contains("secret-refresh"))
        // Debuggers and test-failure diffs walk the mirror; it has nothing to show.
        #expect(Mirror(reflecting: tokens).children.isEmpty)
    }
}
