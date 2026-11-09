import Foundation

/// Remembers that the app has run before. iOS keeps Keychain items when an app is deleted,
/// so without this a reinstall would find the previous owner's session and PIN (ADR-019).
protocol FirstLaunchMarker: Sendable {
    func isFirstLaunch() -> Bool
    func markLaunched()
}

/// A plain flag in the app's defaults: not a secret, only "this install has started once".
/// Deleting the app deletes its defaults, which is exactly the signal needed.
struct DefaultsFirstLaunchMarker: FirstLaunchMarker {
    static let flag = "app.hasLaunched"

    func isFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        return !defaults.bool(forKey: Self.flag)
    }

    func markLaunched() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Self.flag)
    }
}
