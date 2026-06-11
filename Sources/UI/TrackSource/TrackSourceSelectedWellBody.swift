import SwiftUI

struct TrackSourceSelectedWellBodyPresentation: Equatable {
    let isEmpty: Bool

    var usesDashedStroke: Bool { false }
}

struct TrackSourceSelectedWellBody<Content: View>: View {
    let accent: Color
    let isEmpty: Bool
    @ViewBuilder var content: Content

    private var presentation: TrackSourceSelectedWellBodyPresentation {
        TrackSourceSelectedWellBodyPresentation(isEmpty: isEmpty)
    }

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
        // Colour identifies, it never floods (ux-canon rule 12): the well body
        // is neutral; its accent lives in the outline and the solid tab badge.
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: shape
        )
        .overlay(
            shape
                .stroke(
                    accent.opacity(StudioOpacity.ghostStroke),
                    style: StrokeStyle(lineWidth: 1.5, dash: presentation.usesDashedStroke ? [7, 5] : [])
                )
        )
        .padding(.horizontal, 10)
    }
}
