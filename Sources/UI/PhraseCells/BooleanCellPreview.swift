import SwiftUI

struct BooleanCellPreview: View {
    let layer: PhraseLayerDefinition
    let resolvedValue: PhraseCellValue
    let accent: Color
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(booleanFill)

            Text(booleanLabel)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
        }
        .frame(height: metrics.booleanHeight)
    }

    private var booleanState: Bool {
        if case let .bool(isOn) = resolvedValue.normalized(for: layer) {
            return isOn
        }
        return false
    }

    private var booleanLabel: String {
        if isMixed {
            return "Mixed"
        }
        if layer.id == "mute" {
            return booleanState ? "Muted" : "Live"
        }
        return booleanState ? "On" : "Off"
    }

    private var booleanFill: Color {
        if layer.id == "mute" {
            return booleanState ? Color.red.opacity(metrics.muteOnOpacity) : StudioTheme.success.opacity(0.55)
        }
        return booleanState ? accent.opacity(metrics.booleanAccentOpacity) : Color.white.opacity(0.04)
    }
}
