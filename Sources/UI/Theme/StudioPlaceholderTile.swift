import SwiftUI

struct StudioPlaceholderTile: View {
    let title: String
    /// Optional short state caption. Instructional prose belongs in a `.help`
    /// tooltip, not here (canon Rule 3: no explainer prose on surfaces).
    var detail: String? = nil
    var accent: Color = StudioTheme.transportAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .studioText(.placeholderTitle)
                .foregroundStyle(StudioTheme.text)

            if let detail {
                Text(detail)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.softFill), lineWidth: StudioMetrics.borderWidth)
        )
    }
}
