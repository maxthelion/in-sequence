import SwiftUI

struct BooleanCellPreview: View {
    let layer: PhraseLayerDefinition
    let resolvedValue: PhraseCellValue
    let accent: Color
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .fill(booleanFill)

            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(booleanStroke, lineWidth: StudioMetrics.borderWidth)

            Text(booleanLabel)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(booleanForeground)
        }
        .frame(height: metrics.booleanHeight)
    }

    var booleanState: Bool {
        if case let .bool(isOn) = resolvedValue.normalized(for: layer) {
            return isOn
        }
        return false
    }

    var booleanLabel: String {
        if isMixed {
            return "Mixed"
        }
        if layer.id == "mute" {
            return booleanState ? "Muted" : "Live"
        }
        return booleanState ? "On" : "Off"
    }

    /// Bold-flat pass: every filled state is a fully solid block, so its
    /// label flips to the dark ground colour for contrast; only the
    /// outline-only "Off" state keeps light text.
    var booleanForeground: Color {
        if isFilled {
            return StudioTheme.background
        }
        return StudioTheme.text
    }

    /// Bold-flat pass: solid accent block when on; the off state is
    /// outline-only on the ground — no in-between washes.
    var booleanFill: Color {
        return booleanState ? accent : Color.clear
    }

    var booleanStroke: Color {
        isFilled ? Color.clear : StudioTheme.border
    }

    private var isFilled: Bool {
        booleanState
    }
}
