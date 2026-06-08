import SwiftUI

struct PerformanceLayerOptionCard: View {
    let mode: TrackPerformLayerMode
    let selectedMode: TrackPerformLayerMode
    let selectedVariantLabel: String?
    let onSelectPlain: () -> Void
    let onSelectVariant: (String) -> Void

    private var accent: Color { mode.selectorAccent }
    private var isSelectedPlain: Bool {
        selectedMode == mode && selectedVariantLabel == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(StudioOpacity.selectedFill), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label.uppercased())
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(mode.subtitle)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            if mode.hasInlineVariants {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(mode.inlineVariantLabels, id: \.self) { variant in
                        Button {
                            onSelectVariant(variant)
                        } label: {
                            Text(variant)
                                .studioText(.microEmphasis)
                                .foregroundStyle(isSelectedVariant(variant) ? StudioTheme.text : StudioTheme.mutedText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .background(
                                    isSelectedVariant(variant)
                                        ? accent.opacity(StudioOpacity.selectedFill)
                                        : Color.white.opacity(StudioOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                        .stroke(isSelectedVariant(variant) ? accent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    onSelectPlain()
                } label: {
                    Text(isSelectedPlain ? "ACTIVE" : "SELECT")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(isSelectedPlain ? StudioTheme.text : StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            isSelectedPlain
                                ? accent.opacity(StudioOpacity.selectedFill)
                                : Color.white.opacity(StudioOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(isSelectedPlain ? accent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: mode.hasInlineVariants ? 146 : 116, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(cardStroke, lineWidth: selectedMode == mode ? 2 : 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var cardFill: Color {
        selectedMode == mode ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var cardStroke: Color {
        selectedMode == mode ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border
    }

    private func isSelectedVariant(_ variant: String) -> Bool {
        selectedMode == mode && selectedVariantLabel == variant
    }
}

extension TrackPerformLayerMode {
    var selectorAccent: Color {
        switch self {
        case .mute:
            return StudioTheme.success
        case .pattern:
            return StudioTheme.violet
        case .fill:
            return StudioTheme.success
        case .noteRepeat:
            return StudioTheme.cyan
        case .stepOrder:
            return StudioTheme.amber
        case .volume:
            return StudioTheme.cyan
        case .pan:
            return StudioTheme.violet
        case .latch:
            return StudioTheme.amber
        }
    }
}
