import SwiftUI

struct StudioPanel<Content: View>: View {
    let title: String
    var eyebrow: String? = nil
    var accent: Color = StudioTheme.cyan
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title.uppercased())
                        .studioText(.bodyEmphasis)
                        .tracking(1.1)
                        .foregroundStyle(StudioTheme.text)

                    Rectangle()
                        .fill(accent)
                        .frame(width: 36, height: 2)

                    Spacer()
                }

                if let eyebrow {
                    Text(eyebrow)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            content
        }
        .padding(StudioMetrics.Spacing.loose)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(StudioOpacity.subtleStroke), radius: StudioMetrics.CornerRadius.panel, x: 0, y: 10)
    }
}
