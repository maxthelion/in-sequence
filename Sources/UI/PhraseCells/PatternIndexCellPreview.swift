import SwiftUI

struct PatternIndexCellPreview: View {
    let layer: PhraseLayerDefinition
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    let slotCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<slotCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(slotFill(for: index))
                        .frame(height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(slotStroke(for: index), lineWidth: 1)
                        )
                }
            }

            Spacer(minLength: 0)

            Text(summary)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(isMixed ? "Mixed member values" : "Pattern slot")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.text.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .frame(height: metrics.valueHeight)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var activeIndex: Int? {
        if case let .index(index) = resolvedValue.normalized(for: layer) {
            return min(max(index, 0), slotCount - 1)
        }
        return nil
    }

    func slotFill(for index: Int) -> Color {
        guard let activeIndex else {
            return Color.white.opacity(0.05)
        }
        return index == activeIndex ? accent.opacity(0.85) : Color.white.opacity(0.06)
    }

    func slotStroke(for index: Int) -> Color {
        guard let activeIndex else {
            return StudioTheme.border.opacity(0.4)
        }
        return index == activeIndex ? accent.opacity(0.95) : StudioTheme.border.opacity(0.45)
    }
}
