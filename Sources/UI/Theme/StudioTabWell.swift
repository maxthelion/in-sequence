import SwiftUI

// StudioTabWell — THE containing element of the unified tab grammar (Variant D,
// owner-locked 2026-07-02; see docs/roadmap/track-view-ia/
// tab-unification-and-canon-creep.md → DECISION, and the rendered ground truth
// in docs/roadmap/track-view-ia/prototypes/rendered/08-unified-tab-well-D/).
//
// One container primitive for every track/kit/part surface:
//   • full-strength surface-accent outline at StudioMetrics.borderWidth
//     (accent as OUTLINE only, never a fill — ux-canon rule 12);
//   • ALL four corners rounded at 12 px (StudioMetrics.CornerRadius.control);
//   • exactly one opaque neutral fill step above the ground
//     (StudioTheme.subtleFill).
//
// The section switcher (StudioSectionPills) floats ABOVE the well with the
// standard StudioTabWellGrammar.pillRowToWellGap; tab content and any
// secondary/value selectors live INSIDE the well (value selectors use the
// inset-track solid-thumb grammar, never the pill-row grammar).
//
// API modelled on the deleted TrackSourceSelectedWellBody (the square-top
// track-source well this primitive superseded; last caller migrated
// 2026-07-02).

/// Grammar constants shared by the tab strip + well pairing.
enum StudioTabWellGrammar {
    /// The small vertical gap between a floating `StudioSectionPills` row and
    /// the `StudioTabWell` below it (Variant D: the strip is a separate
    /// element hovering just above the well, not docked to it).
    static let pillRowToWellGap: CGFloat = 5
}

/// The unified tab-content container: neutral-filled, fully-rounded, outlined
/// at full-strength surface accent.
struct StudioTabWell<Content: View>: View {
    /// The one chrome accent of the surface (track identity colour; kit
    /// surfaces pass the group colour). Applied at full strength to the
    /// outline only.
    let accent: Color
    /// Inner padding between the outline and the tab content.
    var contentPadding: CGFloat = StudioMetrics.Spacing.loose
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: StudioMetrics.CornerRadius.control,
            style: .continuous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
            content
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Colour identifies, it never floods (ux-canon rule 12): the well body
        // is neutral — one fill step above the ground — and its accent lives
        // entirely in the full-strength outline.
        .background(
            StudioTheme.subtleFill,
            in: shape
        )
        .overlay(
            shape.stroke(accent, lineWidth: StudioMetrics.borderWidth)
        )
    }
}
