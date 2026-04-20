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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.8))
                    .frame(height: fillHeight)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(summary)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(isMixed ? "Mixed member values" : cell.editMode.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.text.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(10)
            }
        }
        .frame(height: metrics.valueHeight)
    }
}
