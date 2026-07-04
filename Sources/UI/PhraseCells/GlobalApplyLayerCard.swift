import SwiftUI

/// A By Value card. The INNER value is rendered with the same
/// `PhraseCellPreview` the Layers matrix uses, so a given layer value looks
/// identical in both views: mute → red "Muted" / green "Live"; pattern → the
/// 4×4 slot matrix; scalar → the level well. The card adds only the framing
/// the same-value picker legitimately needs on top of that shared cell:
///
///   - the layer NAME label (the matrix names the active layer in its header
///     once; here each card stands alone, so it carries its own name), and
///   - a divergence indicator: an amber border when the scoped tracks are not
///     unanimous, with the shared preview showing "Mixed" inside.
///
/// Tapping the whole card cycles/toggles the value through `onApply`
/// (applyGlobalOption → session.setPhraseCell / quantised arming), the same
/// write path as before — no behaviour change, only a unified cell grammar.
struct GlobalApplyLayerCard: View {
    let option: PerformanceLayerOption
    let layer: PhraseLayerDefinition
    let value: PhraseCellValue
    let isDivergent: Bool
    let summary: String
    let onApply: () -> Void

    private var accent: Color { option.mode.selectorAccent }

    private var borderColor: Color {
        isDivergent ? StudioTheme.amber : StudioTheme.border
    }

    var body: some View {
        Button(action: onApply) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: option.mode.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Text(option.title.uppercased())
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                PhraseCellPreview(
                    layer: layer,
                    cell: .single(value),
                    resolvedValue: value,
                    accent: accent,
                    summary: summary,
                    isMixed: isDivergent,
                    metrics: .matrix
                )
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: isDivergent ? 2 : StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrase-global-apply-cell-\(layer.id)")
        .accessibilityValue(isDivergent ? "Mixed" : summary)
    }
}
