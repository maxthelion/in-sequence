import SwiftUI

/// One cell in the performance layer matrix. The whole cell is the button.
/// Variant cells (note repeat intervals, step order maps) toggle: off is
/// normal playback, on is the chosen setting.
struct PerformanceLayerOptionCell: View {
    let option: PerformanceLayerOption
    let isSelected: Bool
    let onTap: () -> Void

    private var accent: Color { option.mode.selectorAccent }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: option.mode.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? StudioTheme.text : accent)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                    }
                }

                Spacer(minLength: 0)

                Text(option.title.uppercased())
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(option.variantLabel == nil ? option.mode.subtitle : option.mode.label)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(option.variantLabel.map { "\(option.mode.label) — \($0). Tap again to return to normal." } ?? option.mode.label)
        .accessibilityLabel("\(option.mode.label) \(option.variantLabel ?? "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
        }
    }
}
