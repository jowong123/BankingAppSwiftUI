import SwiftUI

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

#Preview("Light") {
    CircleIconButtonPreview()
}

#Preview("Dark") {
    CircleIconButtonPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    CircleIconButtonPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct CircleIconButtonPreview: View {
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Spacing.xLarge) {
                CircleIconButton("Add money", systemImage: "plus") {}
                CircleIconButton("Card details", systemImage: "creditcard") {}
                CircleIconButton("Freeze card", systemImage: "snowflake") {}
            }
            .padding(Spacing.large)
        }
        .background(Palette.background)
    }
}
