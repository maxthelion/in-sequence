import SwiftUI

struct StudioMetricPill: View {
    let title: String
    let value: String
    var accent: Color = StudioTheme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .studioText(.microEmphasis)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            Text(value)
                .studioText(.metricValue)
                .foregroundStyle(StudioTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(StudioOpacity.borderFaint), in: Capsule())
        .overlay(
            Capsule()
                .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: 1)
        )
    }
}
