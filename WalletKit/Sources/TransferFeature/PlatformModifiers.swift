import SwiftUI

/// iOS-only modifiers. The package also builds for macOS so `swift test` runs on the
/// host; there the defaults are fine.
extension View {
    func groupedListStyle() -> some View {
        #if os(iOS)
            listStyle(.insetGrouped)
        #else
            self
        #endif
    }

    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}

extension View {
    func navigationBarBackButtonHiddenOnIOS() -> some View {
        #if os(iOS)
            navigationBarBackButtonHidden()
        #else
            self
        #endif
    }
}
