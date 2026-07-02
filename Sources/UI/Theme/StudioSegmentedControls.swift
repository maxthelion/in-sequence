import SwiftUI

// Shared studio control grammars consolidated in W2 (UI component consolidation).
//
// Two distinct grammars live here:
//
//   • StudioSlotTabButton — the UNDERLINE tab: a neutral-filled pill with an
//     uppercase eyebrow label, an optional solid state badge, and a 2px accent
//     underline + ghost-stroke outline when selected. Used by the normal/slicer/
//     audio track tab bars (TrackSourceSlotWellTabBar) and the drum-kit tab bar
//     (DrumKitMatrixView). "Colour identifies, it never floods" (ux-canon rule
//     12): the selected tab keeps the neutral fill; its accent lives in the
//     outline, underline, and solid state badge only.
//
//   • StudioSegmentedControl / StudioSegment — the SOLID-thumb segmented chips:
//     a pill container holding chips where the selected chip is a fully solid
//     accent thumb. Used by the track source/record controls, the drum-group
//     routing-mode control, the drum-kit accordion row/source switches, and the
//     capture history-length control. Layout dimensions vary per call site, so
//     the geometry is supplied via StudioSegmentedControl.Layout to keep every
//     surface pixel-identical to its hand-rolled predecessor.

// MARK: - Underline tab button

/// The neutral-fill + accent-underline tab button shared by the track tab bars
/// and the drum-kit tab bar. Label-only when `badgeTitle` is nil.
struct StudioSlotTabButton: View {
    let title: String
    let isSelected: Bool
    /// The accent used for the underline + ghost outline when selected.
    let selectedAccent: Color
    /// Optional solid state badge shown to the right of the title.
    var badgeTitle: String?
    /// The accent used to fill the badge (ignored when `badgeTitle` is nil).
    var badgeAccent: Color = StudioTheme.border
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title.uppercased())
                        .studioText(.eyebrowBold)
                        .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                        .tracking(0.8)

                    if let badgeTitle {
                        StudioSlotTabBadge(title: badgeTitle, accent: badgeAccent)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

                Rectangle()
                    .fill(isSelected ? selectedAccent : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            // Colour identifies, it never floods (ux-canon rule 12): the
            // selected tab keeps the neutral fill; its accent lives in the
            // outline, underline, and solid state badge.
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(
                        isSelected ? selectedAccent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The solid state badge rendered inside `StudioSlotTabButton`.
struct StudioSlotTabBadge: View {
    let title: String
    let accent: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(StudioTheme.background)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                accent,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
    }
}

// MARK: - Solid-thumb segmented control

struct StudioSegment<Value: Equatable> {
    let title: String
    let value: Value
    var isEnabled: Bool = true
    var accessibilityIdentifier: String?
    var accessibilityLabel: String?
    var help: String?
}

struct StudioSegmentedControl<Value: Equatable>: View {
    /// Per-call-site chip geometry. Defaults match the track source/record
    /// controls; other surfaces pass their exact historical dimensions so the
    /// output stays pixel-identical.
    struct Layout {
        /// When true the chip fills the available width; otherwise it sizes to
        /// `minWidth`.
        var fillsWidth: Bool = true
        var minWidth: CGFloat = 0
        var minHeight: CGFloat = 28
        var horizontalPadding: CGFloat = 8
        /// Shrink-to-fit factor; nil disables `minimumScaleFactor`.
        var minimumScaleFactor: CGFloat? = 0.82

        static var trackControl: Layout { Layout() }
    }

    /// Optional eyebrow label rendered above the chips. When nil the control is
    /// a bare pill container with no title row.
    let title: String?
    let selection: Binding<Value>
    let segments: [StudioSegment<Value>]
    let accent: Color
    var layout: Layout = .trackControl
    /// Builds the accessibility label for a segment. Defaults to "<title> <seg>".
    var accessibilityLabel: (StudioSegment<Value>) -> String

    init(
        title: String?,
        selection: Binding<Value>,
        segments: [StudioSegment<Value>],
        accent: Color,
        layout: Layout = .trackControl,
        accessibilityLabel: ((StudioSegment<Value>) -> String)? = nil
    ) {
        self.title = title
        self.selection = selection
        self.segments = segments
        self.accent = accent
        self.layout = layout
        self.accessibilityLabel = accessibilityLabel ?? { segment in
            "\(title ?? "") \(segment.title)"
        }
    }

    var body: some View {
        if let title {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)

                container
            }
        } else {
            container
        }
    }

    private var container: some View {
        HStack(spacing: 4) {
            ForEach(segments.indices, id: \.self) { index in
                segmentButton(segments[index])
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
        )
    }

    @ViewBuilder
    private func segmentButton(_ segment: StudioSegment<Value>) -> some View {
        let isSelected = selection.wrappedValue == segment.value

        Button {
            selection.wrappedValue = segment.value
        } label: {
            chipLabel(segment, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(!segment.isEnabled)
        .help(segment.help ?? "")
        .modify { view in
            if let identifier = segment.accessibilityIdentifier {
                view.accessibilityIdentifier(identifier)
            } else {
                view
            }
        }
        .accessibilityLabel(segment.accessibilityLabel ?? accessibilityLabel(segment))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func chipLabel(_ segment: StudioSegment<Value>, isSelected: Bool) -> some View {
        let base = Text(segment.title)
            .studioText(.labelBold)
            .foregroundStyle(segmentForeground(isSelected: isSelected, isEnabled: segment.isEnabled))
            .lineLimit(1)

        Group {
            if let scale = layout.minimumScaleFactor {
                base.minimumScaleFactor(scale)
            } else {
                base
            }
        }
        .frame(
            minWidth: layout.fillsWidth ? nil : layout.minWidth,
            maxWidth: layout.fillsWidth ? .infinity : nil,
            minHeight: layout.minHeight
        )
        .padding(.horizontal, layout.horizontalPadding)
        // Colour identifies, it never floods (ux-canon rule 12): the selected
        // segment is a fully solid accent thumb.
        .background(
            isSelected ? accent : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
        )
        // An unselected chip has a clear fill; without an explicit hit shape its
        // tap target shrinks to the text glyph. The whole chip should be tappable.
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
    }

    private func segmentForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.4)
        }
        return isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78)
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

// MARK: - Capsule mode pill

/// One segment of `StudioModeSegmentedPill`: SF Symbol + uppercased label.
struct StudioModeSegmentedPillSegment<Mode: Hashable> {
    let mode: Mode
    let symbolName: String
    let label: String
    var help: String = ""
    var accessibilityIdentifier: String?
}

/// Third grammar: the capsule segmented MODE pill — fixed 96×32 glyph+label
/// segments on a subtleFill capsule track with a medium-stroke accent
/// outline; the selected segment is a fully solid accent capsule thumb
/// ("colour identifies, it never floods": accent only on the live thumb and
/// outline). Shared by the phrase-workspace mode switches (layer edit mode,
/// scene Macros|Slots) so every mode switch reads identically — add new mode
/// switches through this component, not per-surface copies.
struct StudioModeSegmentedPill<Mode: Hashable>: View {
    let segments: [StudioModeSegmentedPillSegment<Mode>]
    let selection: Mode
    let accent: Color
    var accessibilityIdentifier: String?
    let onSelect: (Mode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.mode) { segment in
                segmentButton(segment)
            }
        }
        .padding(2)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
        .overlay(
            Capsule()
                .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .modify { view in
            if let accessibilityIdentifier {
                view.accessibilityIdentifier(accessibilityIdentifier)
            } else {
                view
            }
        }
    }

    private func segmentButton(_ segment: StudioModeSegmentedPillSegment<Mode>) -> some View {
        let isSelected = selection == segment.mode

        return Button {
            onSelect(segment.mode)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: segment.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(segment.label.uppercased())
                    .studioText(.microEmphasis)
                    .tracking(0.8)
            }
            .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
            .frame(width: 96, height: 32)
            .background(
                isSelected ? accent : Color.white.opacity(StudioOpacity.subtleFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .modify { view in
            if let identifier = segment.accessibilityIdentifier {
                view.accessibilityIdentifier(identifier)
            } else {
                view
            }
        }
        .help(segment.help)
    }
}
