import SwiftUI

/// Standard rotary value control: drag vertically to change, arc shows the
/// normalized position, value reads in the center, label sits underneath.
struct StudioRotaryKnob: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var accent: Color = StudioTheme.cyan
    var size: CGFloat = 44
    var format: (Double) -> String = { "\(Int($0.rounded()))" }
    let onChange: (Double) -> Void
    /// Fired on every drag tick (in addition to `onChange` at release) so
    /// live controls can move the engine while the knob turns in place.
    var onLiveChange: ((Double) -> Void)?

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        accent: Color = StudioTheme.cyan,
        size: CGFloat = 44,
        format: @escaping (Double) -> String = { "\(Int($0.rounded()))" },
        onChange: @escaping (Double) -> Void,
        onLiveChange: ((Double) -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.accent = accent
        self.size = size
        self.format = format
        self.onChange = onChange
        self.onLiveChange = onLiveChange
        self._displayValue = State(initialValue: value)
    }

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (displayValue - range.lowerBound) / span
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border, lineWidth: 2)
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * normalized)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size - 6, height: size - 6)
                    .rotationEffect(.degrees(-90))

                Text(format(displayValue))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
            }
            .contentShape(Circle())
            .gesture(
                StudioDrag.verticalValueGesture(
                    value: Binding(
                        get: { displayValue },
                        set: { next in
                            displayValue = next
                            onLiveChange?(next)
                        }
                    ),
                    dragStart: $dragStartValue,
                    range: range,
                    onCommit: onChange
                )
            )

            Text(title.uppercased())
                .studioText(.micro)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .frame(width: size + 18)
        }
        .onChange(of: value) { _, newValue in
            if dragStartValue == nil {
                displayValue = newValue
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(format(displayValue))
    }
}
