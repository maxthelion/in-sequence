import SwiftUI

/// One cell in the performance layer matrix. The whole cell is the button.
/// Variant cells (note repeat intervals, step order maps) toggle: off is
/// normal playback, on is the chosen setting.
struct PerformanceLayerOptionCell: View {
    let option: PerformanceLayerOption
    let isSelected: Bool
    var presentsToggleState = false
    let onTap: () -> Void

    private var accent: Color { option.mode.phraseAccent }
    private var usesSolidToggleFill: Bool { presentsToggleState && isSelected }
    private var primaryForeground: Color {
        usesSolidToggleFill ? StudioTheme.background : StudioTheme.text
    }
    private var secondaryForeground: Color {
        usesSolidToggleFill ? StudioTheme.background : StudioTheme.mutedText
    }

    var body: some View {
        Button {
            guard option.isAvailable else { return }
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: option.mode.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(usesSolidToggleFill ? StudioTheme.background : accent)

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                Text(option.title.uppercased())
                    .studioText(.labelBold)
                    .foregroundStyle(primaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                // Variant cells carry the mode name (their title is the
                // variant, e.g. "1/8"). Plain cells carry NO subtitle — the
                // old "track mute"/"pattern slot"/"runtime fill" lines merely
                // restated the label (canon Rules 1/3, design review 11).
                if option.variantLabel != nil || option.unavailableReason != nil {
                    Text(option.unavailableReason ?? option.mode.label)
                        .studioText(.micro)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                usesSolidToggleFill
                    ? accent
                    : isSelected ? StudioTheme.subtleFill : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? accent : StudioTheme.border, lineWidth: isSelected ? 2 : StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(option.isAvailable)
        .help(option.variantLabel.map { "\(option.mode.label) — \($0)" } ?? option.mode.label)
        .accessibilityLabel("\(option.mode.label) \(option.variantLabel ?? "")")
        .accessibilityValue(
            !option.isAvailable
                ? (option.unavailableReason ?? "Unavailable")
                : presentsToggleState
                ? (isSelected ? "On" : "Off")
                : (isSelected ? "Selected" : "Not selected")
        )
    }
}

/// A value button in Phrase Values. Expansion and pin controls are siblings
/// of the main button so every hit target remains independent and full-size.
struct GlobalApplyValueOptionCell: View {
    let option: PerformanceLayerOption
    let isSelected: Bool
    let isPinned: Bool
    let isExpanded: Bool
    let showsExpansionControl: Bool
    let onApply: () -> Void
    let onToggleExpansion: () -> Void
    let onTogglePin: () -> Void

    private var accent: Color { option.mode.phraseAccent }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PerformanceLayerOptionCell(
                option: option,
                isSelected: isSelected,
                presentsToggleState: true,
                onTap: onApply
            )

            HStack(spacing: 4) {
                if showsExpansionControl {
                    accessoryButton(
                        systemName: isExpanded ? "chevron.up" : "chevron.down",
                        isActive: isExpanded,
                        help: isExpanded ? "Collapse \(option.mode.label) values" : "Expand \(option.mode.label) values",
                        action: onToggleExpansion
                    )
                }

                if option.isAvailable {
                    accessoryButton(
                        systemName: isPinned ? "pin.fill" : "pin",
                        isActive: isPinned,
                        help: isPinned ? "Unpin \(option.title)" : "Pin \(option.title)",
                        action: onTogglePin
                    )
                }
            }
            .padding(6)
        }
    }

    private func accessoryButton(
        systemName: String,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? accent : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(StudioTheme.background, in: Circle())
                .overlay(
                    Circle().stroke(
                        isActive ? accent : StudioTheme.border,
                        lineWidth: StudioMetrics.borderWidth
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension TrackPerformLayerMode {
    var phraseAccent: Color {
        StudioTheme.phraseAccent
    }
}
