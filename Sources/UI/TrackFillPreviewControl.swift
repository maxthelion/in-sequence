import SwiftUI

/// Compact fill-preview toggle shown in the track header. Status detail lives
/// in the hover tooltip rather than inline explainer text.
struct TrackFillPreviewControl: View {
    let presentation: TrackFillPreviewHeaderPresentation
    let accent: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: presentation.isActive ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg.rectangle")
                    .imageScale(.small)
                Text(presentation.buttonTitle)
                    .studioText(.labelBold)
                Text(presentation.isActive ? "ON" : "OFF")
                    .studioText(.microEmphasis)
                    .foregroundStyle(presentation.isActive && presentation.isEnabled ? StudioTheme.background : foreground)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        badgeFill,
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    )
            }
            .foregroundStyle(foreground)
            .frame(minHeight: 34)
            .padding(.horizontal, 10)
            .background(
                backgroundFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(border, lineWidth: presentation.isActive ? StudioMetrics.emphasisBorderWidth : StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isEnabled)
        .help(presentation.statusText)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.isActive ? "On" : "Off")
    }

    private var foreground: Color {
        if !presentation.isEnabled {
            return StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke)
        }
        return presentation.isActive ? StudioTheme.text : StudioTheme.mutedText
    }

    /// Colour identifies, it never floods (ux-canon rule 12): the control
    /// body stays neutral; the active state reads from the accent outline and
    /// the solid ON badge.
    private var backgroundFill: Color {
        StudioTheme.subtleFill
    }

    private var border: Color {
        if !presentation.isEnabled {
            return StudioTheme.border
        }
        return presentation.isActive ? accent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border
    }

    private var badgeFill: Color {
        if !presentation.isEnabled {
            return StudioTheme.border
        }
        return presentation.isActive ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.borderSubtleFill
    }
}
