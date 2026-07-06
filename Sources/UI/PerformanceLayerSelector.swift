import SwiftUI

/// One cell in the performance layer matrix. The whole cell is the button.
/// Variant cells (note repeat intervals, step order maps) toggle: off is
/// normal playback, on is the chosen setting.
struct PerformanceLayerOptionCell: View {
    let option: PerformanceLayerOption
    let isSelected: Bool
    let onTap: () -> Void

    private var accent: Color { option.mode.phraseAccent }

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

                // Variant cells carry the mode name (their title is the
                // variant, e.g. "1/8"). Plain cells carry NO subtitle — the
                // old "track mute"/"pattern slot"/"runtime fill" lines merely
                // restated the label (canon Rules 1/3, design review 11).
                if option.variantLabel != nil {
                    Text(option.mode.label)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            // Colour identifies, it never floods (ux-canon rule 12):
            // unselected cells are outline-only on the ground; selection
            // reads from the solid accent outline and check badge, with the
            // cell body on the neutral step.
            .background(
                isSelected ? StudioTheme.subtleFill : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? accent : StudioTheme.border, lineWidth: isSelected ? 2 : StudioMetrics.borderWidth)
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
    var phraseAccent: Color {
        StudioTheme.phraseAccent
    }
}
