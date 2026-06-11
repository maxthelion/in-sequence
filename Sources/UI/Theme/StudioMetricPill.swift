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

            // Bold-flat pass: the value reads in the accent colour inside an
            // outline-only capsule on the ground — no tinted wash.
            Text(value)
                .studioText(.metricValue)
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            Capsule()
                .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }
}
