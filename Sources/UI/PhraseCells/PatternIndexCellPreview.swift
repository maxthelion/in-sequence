import SwiftUI

/// Pattern-slot cell: a 4×4 matrix of pills, one per pattern slot, with the
/// active slot lit in that pattern's identity colour and the cell tinted to
/// match. The matrix *is* the value — no "P1"/"Pattern slot" caption repeating
/// what the layer header and the colour already say (ux-canon rules 1/3).
struct PatternIndexCellPreview: View {
    let layer: PhraseLayerDefinition
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    private let slotCount = TrackPatternBank.slotCount
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: StudioMetrics.Spacing.hairline),
        count: 4
    )

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.tight) {
            LazyVGrid(columns: columns, spacing: StudioMetrics.Spacing.hairline) {
                ForEach(0..<slotCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .fill(slotFill(for: index))
                        .frame(height: pillHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                                .stroke(slotStroke(for: index), lineWidth: 1)
                        )
                }
            }

            if isMixed {
                Text("Mixed")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.text.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.compact)
        .frame(height: metrics.valueHeight)
        .background(cellFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(isMixed ? "Mixed pattern slots" : "Pattern \(summary)")
    }

    var activeIndex: Int? {
        if case let .index(index) = resolvedValue.normalized(for: layer) {
            return min(max(index, 0), slotCount - 1)
        }
        return nil
    }

    private var activeColor: Color? {
        activeIndex.map { StudioTheme.patternColor($0) }
    }

    private var pillHeight: CGFloat {
        // Four pill rows plus the cell padding must fit metrics.valueHeight.
        let inset = StudioMetrics.Spacing.compact * 2 + StudioMetrics.Spacing.hairline * 3
        return max(8, (metrics.valueHeight - inset) / 4)
    }

    private var cellFill: Color {
        guard let activeColor, !isMixed else {
            return Color.white.opacity(StudioOpacity.subtleFill)
        }
        return activeColor.opacity(StudioOpacity.softFill)
    }

    func slotFill(for index: Int) -> Color {
        guard let activeIndex, !isMixed else {
            return Color.white.opacity(StudioOpacity.subtleFill)
        }
        return index == activeIndex
            ? StudioTheme.patternColor(index).opacity(0.85)
            : Color.white.opacity(StudioOpacity.borderSubtle)
    }

    func slotStroke(for index: Int) -> Color {
        guard let activeIndex, !isMixed else {
            return StudioTheme.border.opacity(0.4)
        }
        return index == activeIndex
            ? StudioTheme.patternColor(index).opacity(0.95)
            : StudioTheme.border.opacity(StudioOpacity.mediumStroke)
    }
}
