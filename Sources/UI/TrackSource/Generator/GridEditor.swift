import SwiftUI

struct GridEditor<Value: BinaryFloatingPoint>: View {
    let values: [Value]
    let allowedValues: [Value]
    let accent: Color
    let onChange: ([Value]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Button {
                    onChange(cycledValues(tapping: index))
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accent.opacity(0.85))
                            .frame(height: max(10, 64 * CGFloat(normalizedFill(for: value))))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
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
        guard let maxValue = allowedValues.max(), maxValue > .zero else { return 0 }
        return min(max(Double(value / maxValue), 0), 1)
    }
}
