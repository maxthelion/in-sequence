import SwiftUI

struct StudioMetricPill: View {
    let title: String
    let value: String
    var accent: Color = StudioTheme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(accent.opacity(0.24), lineWidth: 1)
        )
    }
}
