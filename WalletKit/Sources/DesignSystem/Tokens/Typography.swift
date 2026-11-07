import SwiftUI

/// Type scale. Every style maps to a Dynamic Type text style so it scales with the
/// user's setting; amounts use monospaced digits so columns and countdowns don't jitter.
public enum Typography {
    public static var balance: Font {
        .largeTitle.bold().monospacedDigit()
    }
    public static var title: Font {
        .title2.weight(.semibold)
    }
    public static var headline: Font {
        .headline
    }
    public static var body: Font {
        .body
    }
    public static var bodyEmphasised: Font {
        .body.weight(.semibold)
    }
    public static var caption: Font {
        .subheadline
    }
    public static var amount: Font {
        .body.weight(.semibold).monospacedDigit()
    }
    public static var pinKey: Font {
        .title.weight(.medium).monospacedDigit()
    }
}
