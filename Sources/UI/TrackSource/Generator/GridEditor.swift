import SwiftUI

struct GridEditor<Value: BinaryFloatingPoint>: View {
    let values: [Value]
    let allowedValues: [Value]
    let accent: Color
    let valueRange: ClosedRange<Value>?
    let indexOffset: Int
    let onDoubleTap: ((Int) -> Void)?
    let onLongPress: ((Int) -> Void)?
    let onChange: ([Value]) -> Void

    init(
        values: [Value],
        allowedValues: [Value],
        accent: Color,
        valueRange: ClosedRange<Value>? = nil,
        indexOffset: Int = 0,
        onDoubleTap: ((Int) -> Void)? = nil,
        onLongPress: ((Int) -> Void)? = nil,
        onChange: @escaping ([Value]) -> Void
    ) {
        self.values = values
        self.allowedValues = allowedValues
        self.accent = accent
        self.valueRange = valueRange
        self.indexOffset = indexOffset
        self.onDoubleTap = onDoubleTap
        self.onLongPress = onLongPress
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.85))
                        .frame(height: max(10, 64 * CGFloat(normalizedFill(for: value))))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text("\(index + indexOffset + 1)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                .onTapGesture {
                    onChange(cycledValues(tapping: index))
                }
                .onLongPressGesture {
                    onLongPress?(index + indexOffset)
                }
                .accessibilityLabel("Step \(index + indexOffset + 1)")
                .accessibilityAction(named: "Inspect Step") {
                    onDoubleTap?(index + indexOffset)
                }
                .contextMenu {
                    if let onDoubleTap {
                        Button("Inspect Step") {
                            onDoubleTap(index + indexOffset)
                        }
                    }
                    if let onLongPress {
                        Button("Clear Step") {
                            onLongPress(index + indexOffset)
                        }
                    }
                }
            }
        }
        .frame(height: 96)
    }

    func cycledValues(tapping index: Int) -> [Value] {
        var next = values
        guard next.indices.contains(index) else { return next }
        let value = next[index]
        let currentIndex = allowedValues.firstIndex(where: { abs(Double($0 - value)) < 0.01 }) ?? 0
        next[index] = allowedValues[(currentIndex + 1) % allowedValues.count]
        return next
    }

    func normalizedFill(for value: Value) -> Double {
        if let valueRange {
            let span = valueRange.upperBound - valueRange.lowerBound
            guard span > .zero else { return 0 }
            return min(max(Double((value - valueRange.lowerBound) / span), 0), 1)
        }
        guard let maxValue = allowedValues.max(), maxValue > .zero else { return 0 }
        return min(max(Double(value / maxValue), 0), 1)
    }
}
