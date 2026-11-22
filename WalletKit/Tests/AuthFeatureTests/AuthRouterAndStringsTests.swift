import Domain
import Foundation
import Testing

@testable import AuthFeature

@MainActor
@Suite struct AuthRouterTests {
    /// Auth has no pushed screens today (its screens are coordinator roots); the router
    /// still behaves on an empty stack.
    @Test func popAndDismissOnAnEmptyFlowAreSafe() {
        let router = AuthRouter()

        router.pop()
        router.popToRoot()
        router.dismiss()

        #expect(router.path.isEmpty)
        #expect(router.sheet == nil)
    }
}

@Suite struct AuthStringsTests {
    /// Every key the code asks for exists in `Localizable.strings`, and the file has no extras.
    @Test func everyKeyTheCodeUsesIsInTheStringsFile() throws {
        let source = try String(
            contentsOf: URL(filePath: #filePath)
                .deletingLastPathComponent()
                .appending(path: "../../Sources/AuthFeature/AuthStrings.swift")
                .standardized,
            encoding: .utf8
        )
        let usedKeys = Set(
            source.matches(of: /text\("([^"]+)"\)/).map {
                String($0.output.1)
            })
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "strings"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])

        #expect(!usedKeys.isEmpty)
        #expect(usedKeys == Set(table.keys))
    }

    @Test func everyErrorThatIsShownHasText() {
        let shown: [AuthError] = [
            .invalidCredentials, .offline, .unavailable, .sessionExpired, .invalidPIN,
            .wrongPIN(attemptsLeft: 3), .biometryFailed, .biometryUnavailable, .biometryChanged, .storageUnavailable,
        ]
        for error in shown {
            let userFacing = AuthMessages.userFacing(error)
            for text in [userFacing?.title ?? "", userFacing?.message ?? ""] {
                #expect(!text.isEmpty && !text.hasPrefix("auth."), "\(error)")
            }
        }
        #expect(AuthMessages.userFacing(.cancelled) == nil)
        #expect(AuthMessages.userFacing(.tooManyAttempts) == nil)
    }

    /// Only a temporary problem invites trying the same thing again.
    @Test(arguments: [
        (AuthError.offline, true), (.unavailable, true), (.storageUnavailable, true),
        (.invalidCredentials, false), (.wrongPIN(attemptsLeft: 2), false), (.biometryChanged, false),
    ])
    func retryIsOfferedOnlyForTemporaryProblems(error: AuthError, canRetry: Bool) {
        #expect(AuthMessages.userFacing(error)?.canRetry == canRetry)
    }
}
