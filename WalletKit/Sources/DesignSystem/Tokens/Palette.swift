import SwiftUI

/// A colour with a light and a dark value, resolved from the environment's colour scheme.
///
/// Built as a SwiftUI `ShapeStyle` rather than a `UIColor` dynamic provider so this
/// module needs nothing beyond SwiftUI and still compiles on macOS for `swift test`.
public struct AdaptiveColor: ShapeStyle {
    public let light: Color
    public let dark: Color

    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }
}

/// Semantic colours. Dark-first: near-black background, charcoal surfaces, lime accent.
///
/// `accent` is only ever a fill with `onAccent` on top. Lime text on a light background
/// fails WCAG contrast, so text that must read as "positive" uses `positive` instead.
public enum Palette {
    public static let background = AdaptiveColor(light: Color(hex: 0xF5F5F3), dark: Color(hex: 0x000000))
    public static let surface = AdaptiveColor(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1C1C1E))
    public static let surfaceElevated = AdaptiveColor(light: Color(hex: 0xEDEDEA), dark: Color(hex: 0x2C2C2E))
    public static let accent = AdaptiveColor(light: Color(hex: 0x9FE870), dark: Color(hex: 0x9FE870))
    public static let onAccent = AdaptiveColor(light: Color(hex: 0x0E1A06), dark: Color(hex: 0x0E1A06))
    public static let textPrimary = AdaptiveColor(light: Color(hex: 0x0E0F0C), dark: Color(hex: 0xFFFFFF))
    public static let textSecondary = AdaptiveColor(light: Color(hex: 0x6A6C6A), dark: Color(hex: 0x8E8E93))
    public static let positive = AdaptiveColor(light: Color(hex: 0x2F7D1F), dark: Color(hex: 0x9FE870))
    public static let negative = AdaptiveColor(light: Color(hex: 0xC62828), dark: Color(hex: 0xFF6B6B))
    public static let separator = AdaptiveColor(light: Color(hex: 0xE2E2DE), dark: Color(hex: 0x2C2C2E))
}

extension Color {
    /// sRGB from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
