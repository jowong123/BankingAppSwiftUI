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

/// Round accent button with a caption underneath, e.g. "Add money" or "Freeze card".
public struct CircleIconButton: View {
    private let title: String
    private let systemImage: String
    private let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 56

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.small) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Palette.accent))
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Slight shrink on press, shared by the buttons in this file.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Light") {
    ButtonsPreview()
}

#Preview("Dark") {
    ButtonsPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    ButtonsPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct ButtonsPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                PrimaryButton("Send money") {}
                PrimaryButton("Send money", isLoading: true) {}
                PrimaryButton("Send money") {}.disabled(true)
                HStack(alignment: .top, spacing: Spacing.xLarge) {
                    CircleIconButton("Add money", systemImage: "plus") {}
                    CircleIconButton("Card details", systemImage: "creditcard") {}
                    CircleIconButton("Freeze card", systemImage: "snowflake") {}
                }
            }
            .padding(Spacing.large)
        }
        .background(Palette.background)
    }
}
