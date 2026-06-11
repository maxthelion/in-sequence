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

    /// Flat variant: the "Live" state fills with solid success green, so its
    /// label flips to the dark background colour for contrast.
    var booleanForeground: Color {
        if layer.id == "mute", !booleanState {
            return StudioTheme.background
        }
        return StudioTheme.text
    }

    var booleanFill: Color {
        if layer.id == "mute" {
            return booleanState ? Color.red.opacity(metrics.muteOnOpacity) : StudioTheme.success.opacity(StudioOpacity.accentFill)
        }
        return booleanState ? accent.opacity(metrics.booleanAccentOpacity) : Color.white.opacity(StudioOpacity.subtleFill)
    }
}
