import SwiftUI

struct StudioPlaceholderTile: View {
    let title: String
    let detail: String
    var accent: Color = StudioTheme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .studioText(.placeholderTitle)
                .foregroundStyle(StudioTheme.text)

            Text(detail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.softFill), lineWidth: 1)
        )
    }
}
