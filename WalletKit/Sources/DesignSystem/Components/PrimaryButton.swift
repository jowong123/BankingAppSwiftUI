import SwiftUI

/// Full-width lime capsule for the main action on a screen.
///
/// While `isLoading` the title is replaced by a spinner and taps are ignored, which
/// stops a double tap from sending a second confirm request.
public struct PrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                // Kept in the layout while loading so the button doesn't change size.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(Palette.onAccent)
                }
            }
            .font(Typography.headline)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, Spacing.large)
            .background(Capsule().fill(Palette.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

#Preview("Light") {
    PrimaryButtonPreview()
}

#Preview("Dark") {
    PrimaryButtonPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    PrimaryButtonPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct PrimaryButtonPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                PrimaryButton("Send money") {}
                PrimaryButton("Send money", isLoading: true) {}
                PrimaryButton("Send money") {}.disabled(true)
            }
            .padding(Spacing.large)
        }
        .background(Palette.background)
    }
}
