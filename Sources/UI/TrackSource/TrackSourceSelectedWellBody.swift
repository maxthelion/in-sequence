import SwiftUI

struct TrackSourceSelectedWellBodyPresentation: Equatable {
    let isEmpty: Bool

    var usesDashedStroke: Bool { false }
    var usesActiveSectionFill: Bool { true }
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
        .background(
            accent.opacity(presentation.usesActiveSectionFill ? StudioOpacity.selectedFill : StudioOpacity.subtleFill),
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
