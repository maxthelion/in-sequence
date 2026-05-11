import SwiftUI

struct TrackSourceSelectedWellBody<Content: View>: View {
    let accent: Color
    let isEmpty: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: StudioMetrics.CornerRadius.section,
                bottomTrailing: StudioMetrics.CornerRadius.section,
                topTrailing: 0
            ),
            style: .continuous
        )

        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            accent.opacity(isEmpty ? StudioOpacity.subtleFill : StudioOpacity.selectedFill),
            in: shape
        )
        .overlay(
            shape
                .stroke(
                    accent.opacity(isEmpty ? StudioOpacity.subtleStroke : StudioOpacity.ghostStroke),
                    style: StrokeStyle(lineWidth: 1.5, dash: isEmpty ? [7, 5] : [])
                )
        )
        .padding(.horizontal, 10)
    }
}
