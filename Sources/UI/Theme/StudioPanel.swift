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
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(StudioTheme.text)

                    Rectangle()
                        .fill(accent)
                        .frame(width: 36, height: 2)

                    Spacer()
                }

                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            content
        }
        .padding(18)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}
