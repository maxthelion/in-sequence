import SwiftUI

struct CellPreviewMetrics {
    let booleanHeight: CGFloat
    let valueHeight: CGFloat

    static let matrix = CellPreviewMetrics(
        booleanHeight: 72,
        valueHeight: 84
    )

    static let live = CellPreviewMetrics(
        booleanHeight: 92,
        valueHeight: 98
    )
}

struct PhraseCellPreview: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let metrics: CellPreviewMetrics

    init(
        layer: PhraseLayerDefinition,
        cell: PhraseCell,
        resolvedValue: PhraseCellValue,
        accent: Color,
        summary: String,
        isMixed: Bool = false,
        metrics: CellPreviewMetrics = .matrix
    ) {
        self.layer = layer
        self.cell = cell
        self.resolvedValue = resolvedValue
        self.accent = accent
        self.summary = summary
        self.isMixed = isMixed
        self.metrics = metrics
    }

    var body: some View {
        switch layer.valueType {
        case .boolean:
            BooleanCellPreview(
                layer: layer,
                resolvedValue: resolvedValue,
                accent: accent,
                isMixed: isMixed,
                metrics: metrics
            )
        case .scalar:
            ScalarCellPreview(
                layer: layer,
                cell: cell,
                resolvedValue: resolvedValue,
                accent: accent,
                summary: summary,
                isMixed: isMixed,
                metrics: metrics
            )
        case .patternIndex:
            PatternIndexCellPreview(
                layer: layer,
                resolvedValue: resolvedValue,
                accent: accent,
                summary: summary,
                isMixed: isMixed,
                metrics: metrics
            )
        }
    }
}
