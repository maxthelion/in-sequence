import SwiftUI

enum StepVisualState {
    case off
    case on
    case accented
}

struct StepGridView: View {
    let stepStates: [StepVisualState]
    let advanceStep: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
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
            VStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(labelStyle)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fillColor)
                    .frame(height: 44)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconStyle)
                    }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(edgeGlow)
                            .frame(width: 26, height: 3)
                            .padding(.top, 5)
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1)")
        .accessibilityValue(accessibilityText)
    }

    private var fillColor: Color {
        switch state {
        case .off:
            return Color.white.opacity(0.06)
        case .on:
            return StudioTheme.cyan.opacity(0.82)
        case .accented:
            return StudioTheme.amber.opacity(0.92)
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
        state == .off ? AnyShapeStyle(StudioTheme.mutedText) : AnyShapeStyle(StudioTheme.text)
    }

    private var iconStyle: AnyShapeStyle {
        state == .off ? AnyShapeStyle(StudioTheme.mutedText) : AnyShapeStyle(StudioTheme.text)
    }

    private var edgeGlow: Color {
        switch state {
        case .off:
            return .clear
        case .on:
            return StudioTheme.cyan
        case .accented:
            return StudioTheme.amber
        }
    }

    private var outlineColor: Color {
        switch state {
        case .off:
            return Color.white.opacity(0.06)
        case .on:
            return StudioTheme.cyan.opacity(0.34)
        case .accented:
            return StudioTheme.amber.opacity(0.34)
        }
    }
}

#Preview {
    StepGridView(
        stepStates: [.on, .off, .accented, .off, .on, .off, .accented, .off, .on, .accented, .off, .off, .on, .on, .accented, .off],
        advanceStep: { _ in }
    )
    .padding()
}
