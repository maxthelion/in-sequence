import SwiftUI

struct StudioPlaceholderTile: View {
    let title: String
    let detail: String
    var accent: Color = StudioTheme.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
    }
}
