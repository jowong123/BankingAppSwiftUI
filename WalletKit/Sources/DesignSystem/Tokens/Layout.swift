import SwiftUI

/// 4-pt spacing scale.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32
}

/// Corner radii. Pills and round buttons use `Capsule` / `Circle` instead of a radius.
public enum Radius {
    public static let card: CGFloat = 24
    public static let control: CGFloat = 16
}

/// Type scale. Every style maps to a Dynamic Type text style so it scales with the
/// user's setting; amounts use monospaced digits so columns and countdowns don't jitter.
public enum Typography {
    public static var balance: Font { .largeTitle.bold().monospacedDigit() }
    public static var title: Font { .title2.weight(.semibold) }
    public static var headline: Font { .headline }
    public static var body: Font { .body }
    public static var bodyEmphasised: Font { .body.weight(.semibold) }
    public static var caption: Font { .subheadline }
    public static var amount: Font { .body.weight(.semibold).monospacedDigit() }
    public static var pinKey: Font { .title.weight(.medium).monospacedDigit() }
}
