import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let chrome = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let panelTop = Color(red: 0.17, green: 0.18, blue: 0.21)
    static let panelBottom = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let border = Color.white.opacity(0.08)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let mutedText = Color(red: 0.61, green: 0.64, blue: 0.70)
    static let cyan = Color(red: 0.00, green: 0.80, blue: 1.00)
    static let amber = Color(red: 1.00, green: 0.53, blue: 0.22)
    static let violet = Color(red: 0.56, green: 0.48, blue: 1.00)
    static let success = Color(red: 0.47, green: 0.91, blue: 0.63)

    static let panelFill = LinearGradient(
        colors: [panelTop, panelBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let stageFill = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.09, blue: 0.11),
            Color(red: 0.05, green: 0.06, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

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
