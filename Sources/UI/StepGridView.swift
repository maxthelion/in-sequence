import SwiftUI

enum StepVisualState {
    case off
    case on
    case accented
}

struct StepGridView: View {
    let stepStates: [StepVisualState]
    let indexOffset: Int
    let playingStepIndex: Int?
    let onDoubleTap: ((Int) -> Void)?
    let advanceStep: (Int) -> Void

    init(
        stepStates: [StepVisualState],
        indexOffset: Int = 0,
        playingStepIndex: Int? = nil,
        onDoubleTap: ((Int) -> Void)? = nil,
        advanceStep: @escaping (Int) -> Void
    ) {
        self.stepStates = stepStates
        self.indexOffset = indexOffset
        self.playingStepIndex = playingStepIndex
        self.onDoubleTap = onDoubleTap
        self.advanceStep = advanceStep
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(stepStates.enumerated()), id: \.offset) { index, state in
                StepGridCell(
                    index: index + indexOffset,
                    state: state,
                    isPlaying: playingStepIndex == index + indexOffset,
                    action: { advanceStep(index + indexOffset) },
                    onDoubleTap: {
                        onDoubleTap?(index + indexOffset)
                    }
                )
            }
        }
    }
}

private struct StepGridCell: View {
    let index: Int
    let state: StepVisualState
    let isPlaying: Bool
    let action: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("\(index + 1)")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(labelStyle)

            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
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
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(isPlaying ? StudioTheme.success.opacity(0.95) : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(perform: action)
        .accessibilityLabel("Step \(index + 1)")
        .accessibilityValue(accessibilityText)
    }

    private var fillColor: Color {
        switch state {
        case .off:
            return Color.white.opacity(StudioOpacity.borderSubtle)
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
            return Color.white.opacity(StudioOpacity.borderSubtle)
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
