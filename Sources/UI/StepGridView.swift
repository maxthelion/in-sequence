import SwiftUI

enum StepVisualState {
    case off
    case on
    case accented
}

struct StepGridView: View {
    let stepStates: [StepVisualState]
    let advanceStep: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(stepStates.enumerated()), id: \.offset) { index, state in
                StepGridCell(
                    index: index,
                    state: state,
                    action: { advanceStep(index) }
                )
            }
        }
    }
}

private struct StepGridCell: View {
    let index: Int
    let state: StepVisualState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption2)
                    .foregroundStyle(labelStyle)

                RoundedRectangle(cornerRadius: 10)
                    .fill(fillColor)
                    .frame(height: 34)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.caption)
                            .foregroundStyle(iconStyle)
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1)")
        .accessibilityValue(accessibilityText)
    }

    private var fillColor: Color {
        switch state {
        case .off:
            return Color.secondary.opacity(0.15)
        case .on:
            return Color.accentColor
        case .accented:
            return Color.orange
        }
    }

    private var symbolName: String {
        switch state {
        case .off:
            return "circle"
        case .on:
            return "circle.fill"
        case .accented:
            return "bolt.fill"
        }
    }

    private var accessibilityText: String {
        switch state {
        case .off:
            return "Off"
        case .on:
            return "On"
        case .accented:
            return "Accented"
        }
    }

    private var labelStyle: AnyShapeStyle {
        state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private var iconStyle: AnyShapeStyle {
        state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white)
    }
}

#Preview {
    StepGridView(
        stepStates: [.on, .off, .accented, .off, .on, .off, .accented, .off, .on, .accented, .off, .off, .on, .on, .accented, .off],
        advanceStep: { _ in }
    )
    .padding()
}
