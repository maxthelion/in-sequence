import SwiftUI

struct StepGridView: View {
    let steps: [Bool]
    let toggleStep: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, isEnabled in
                Button {
                    toggleStep(index)
                } label: {
                    VStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(isEnabled ? .primary : .secondary)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.15))
                            .frame(height: 34)
                            .overlay {
                                Image(systemName: isEnabled ? "circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(isEnabled ? .white : .secondary)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(index + 1)")
                .accessibilityValue(isEnabled ? "On" : "Off")
            }
        }
    }
}

#Preview {
    StepGridView(
        steps: [true, false, true, false, true, false, true, false, true, true, false, false, true, true, true, false],
        toggleStep: { _ in }
    )
    .padding()
}
