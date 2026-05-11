import SwiftUI

struct TrackSourceSelectedWellBody<Content: View>: View {
    let accent: Color
    let isEmpty: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            accent.opacity(isEmpty ? StudioOpacity.subtleFill : StudioOpacity.selectedFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(
                    accent.opacity(isEmpty ? StudioOpacity.subtleStroke : StudioOpacity.ghostStroke),
                    style: StrokeStyle(lineWidth: 1.5, dash: isEmpty ? [7, 5] : [])
                )
        )
        .padding(.horizontal, 10)
    }
}
