import SwiftUI

/// iOS-only modifiers. The package also builds for macOS so `swift test` runs on the
/// host; there the defaults are fine.
extension View {
    func emailField() -> some View {
        #if os(iOS)
            textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            self
        #endif
    }

    func passwordField() -> some View {
        #if os(iOS)
            textContentType(.password)
        #else
            self
        #endif
    }
}
