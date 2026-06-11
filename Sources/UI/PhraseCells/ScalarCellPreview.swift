import SwiftUI

struct ScalarCellPreview: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    var clampedFillRatio: Double {
        min(max(scalarRatio(scalarValue(for: resolvedValue, layer: layer), layer: layer), 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let fillHeight = max(6, geometry.size.height * clampedFillRatio)

            ZStack(alignment: .bottomLeading) {
                // Bold-flat pass: outlined well on the ground; the level is
                // one fully solid accent block — no translucent wash.
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .fill(accent)
                    .frame(height: fillHeight)

                // One dominant value; inherit/single is shown by the cell's
                // muted variant, not by a per-cell mode label. The value
                // reads in the accent colour on the ground, flipping to the
                // dark ground colour once the solid fill rises behind it.
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(summary)
                        .studioText(.modalTitle)
                        .foregroundStyle(clampedFillRatio > 0.4 ? StudioTheme.background : accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if isMixed {
                        Text("Mixed")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(clampedFillRatio > 0.4 ? StudioTheme.background.opacity(0.85) : StudioTheme.text.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(StudioMetrics.Spacing.compact)
            }
        }
        .frame(height: metrics.valueHeight)
    }
}
