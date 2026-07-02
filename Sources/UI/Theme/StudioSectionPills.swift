import SwiftUI

// StudioSectionPills — THE section switcher of the unified tab grammar
// (Variant D, owner-locked 2026-07-02; see docs/roadmap/track-view-ia/
// tab-unification-and-canon-creep.md → DECISION, rendered ground truth in
// docs/roadmap/track-view-ia/prototypes/rendered/08-unified-tab-well-D/ and
// 09-kit-and-part-D/).
//
// EVERY section switcher — track-level (Source/FX/Macros/Mixer…), kit-level
// (Matrix/FX/Macros/Mixer), and part-level (Steps·Clip/Sound/FX/Macros/Mixer)
// — uses this one grammar: a neutral-outlined strip of pills floating a small
// gap (StudioTabWellGrammar.pillRowToWellGap) ABOVE the StudioTabWell, where
// the selected pill is a fully solid accent thumb with a dark glyph and
// unselected pills stay neutral. Left-aligned; NO subtitle explainers — the
// only adornment is an optional SOLID status badge carrying real state
// ("Empty", "Insert"), per ux-canon rule 12.
//
// This is NOT the grammar for value/layer selectors (Steps/Velocity/Chance,
// Normal/Fill, BAR ranges, slicer layer rows): those are solid thumbs inside
// a darker inset capsule track INSIDE the well — see StudioSegmentedControl /
// StudioModeSegmentedPill in StudioSegmentedControls.swift.
//
// One chrome accent per surface: the pills, the well outline, and the status
// badges all carry the track identity colour (kit surfaces use the group
// colour, including the part-level pills).

/// One section entry of a `StudioSectionPills` row.
struct StudioSectionPill<Section: Hashable> {
    let section: Section
    let title: String
    /// Optional SOLID status badge carrying real state ("Empty", "Insert").
    /// Never a subtitle explainer. The badge always renders in the row's one
    /// surface accent — state is the badge title, never a second colour.
    var badgeTitle: String?
    var isEnabled: Bool = true
    var accessibilityIdentifier: String?
    var help: String?
}

/// The D-pill section switcher strip.
struct StudioSectionPills<Section: Hashable>: View {
    let pills: [StudioSectionPill<Section>]
    let selection: Section
    /// The one chrome accent of the surface (track identity / kit group
    /// colour) — fills the selected thumb and the status badges.
    let accent: Color
    /// Track/kit-level switchers span the surface width with equal-width
    /// pills; part-level switchers pass `false` to hug their content,
    /// left-aligned flush to the sub-card edge.
    var fillsWidth: Bool = true
    var accessibilityIdentifier: String?
    let onSelect: (Section) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(pills, id: \.section) { pill in
                pillButton(pill)
            }
        }
        .padding(3)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
        )
        .modify { view in
            if let accessibilityIdentifier {
                view.accessibilityIdentifier(accessibilityIdentifier)
            } else {
                view
            }
        }
    }

    @ViewBuilder
    private func pillButton(_ pill: StudioSectionPill<Section>) -> some View {
        let isSelected = selection == pill.section

        Button {
            onSelect(pill.section)
        } label: {
            pillLabel(pill, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!pill.isEnabled)
        .help(pill.help ?? "")
        .modify { view in
            if let identifier = pill.accessibilityIdentifier {
                view.accessibilityIdentifier(identifier)
            } else {
                view
            }
        }
        .accessibilityLabel(pill.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func pillLabel(_ pill: StudioSectionPill<Section>, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(pill.title.uppercased())
                .studioText(.eyebrowBold)
                .tracking(0.8)
                .lineLimit(1)

            if let badgeTitle = pill.badgeTitle {
                StudioSectionPillBadge(
                    title: badgeTitle,
                    accent: accent,
                    isOnSolidThumb: isSelected
                )
            }
        }
        .foregroundStyle(pillForeground(isSelected: isSelected, isEnabled: pill.isEnabled))
        .padding(.vertical, 10)
        .padding(.horizontal, fillsWidth ? StudioMetrics.Spacing.snug : StudioMetrics.Spacing.standard)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        // Colour identifies, it never floods (ux-canon rule 12): the selected
        // pill is the one fully solid accent thumb with a dark glyph;
        // unselected pills stay neutral inside the outlined strip.
        .background(
            isSelected ? accent : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
        )
        // An unselected pill has a clear fill; without an explicit hit shape
        // its tap target shrinks to the text glyph.
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
    }

    private func pillForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.4)
        }
        return isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78)
    }
}

/// The solid status badge inside a section pill. On a neutral pill it is a
/// solid accent chip with a dark glyph; on the selected solid thumb the
/// colours invert so the badge stays legible against the accent fill.
struct StudioSectionPillBadge: View {
    let title: String
    let accent: Color
    let isOnSolidThumb: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(isOnSolidThumb ? accent : StudioTheme.background)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                isOnSolidThumb ? StudioTheme.background : accent,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
    }
}

private extension View {
    /// Conditionally apply a modifier while keeping a single concrete return
    /// type, used so an optional accessibilityIdentifier doesn't fork the view.
    @ViewBuilder
    func modify<Result: View>(@ViewBuilder _ transform: (Self) -> Result) -> some View {
        transform(self)
    }
}
