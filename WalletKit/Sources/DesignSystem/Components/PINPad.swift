import SwiftUI

/// Progress dots plus a round-key number pad. Calls `onComplete` once all digits are
/// entered, then clears itself, so the caller decides what a wrong PIN looks like.
///
/// The PIN is never shown as text and isn't exposed to accessibility beyond a count.
public struct PINPad: View {
    private let onComplete: (String) -> Void
    @State private var entry: PINEntry
    @ScaledMetric(relativeTo: .title) private var keySize: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 14

    public init(length: Int = 6, onComplete: @escaping (String) -> Void) {
        self.onComplete = onComplete
        self._entry = State(initialValue: PINEntry(length: length))
    }

    public var body: some View {
        VStack(spacing: Spacing.xxLarge) {
            dots
            keypad
        }
        .sensoryFeedback(.selection, trigger: entry.digits.count)
    }

    private var dots: some View {
        HStack(spacing: Spacing.medium) {
            ForEach(0..<entry.length, id: \.self) { index in
                Circle()
                    .fill(
                        index < entry.digits.count
                            ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.surfaceElevated)
                    )
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN")
        .accessibilityValue("\(entry.digits.count) of \(entry.length) digits entered")
    }

    private var keypad: some View {
        Grid(horizontalSpacing: Spacing.xLarge, verticalSpacing: Spacing.large) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digitKey($0) }
                }
            }
            GridRow {
                Color.clear.frame(width: keySize, height: keySize)
                digitKey(0)
                deleteKey
            }
        }
        // Number pads keep 1-2-3 left to right in RTL languages too.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func digitKey(_ digit: Int) -> some View {
        Button {
            entry.append(digit)
            if entry.isComplete {
                onComplete(entry.value)
                entry.reset()
            }
        } label: {
            Text("\(digit)")
                .font(Typography.pinKey)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: keySize, height: keySize)
                .background(Circle().fill(Palette.surface))
        }
        .buttonStyle(.plain)
    }

    private var deleteKey: some View {
        Button {
            entry.deleteLast()
        } label: {
            Image(systemName: "delete.backward")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: keySize, height: keySize)
        }
        .buttonStyle(.plain)
        .disabled(entry.digits.isEmpty)
        .accessibilityLabel("Delete")
    }
}

#Preview("Light") {
    PINPadPreview()
}

#Preview("Dark") {
    PINPadPreview()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    PINPadPreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

private struct PINPadPreview: View {
    var body: some View {
        ScrollView {
            PINPad { _ in }
                .padding(Spacing.large)
                .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}
