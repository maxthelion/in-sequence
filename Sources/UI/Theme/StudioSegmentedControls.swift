import SwiftUI

// Shared studio VALUE/LAYER selector grammars (W2 consolidation; Variant D
// tab unification 2026-07-02).
//
// Everything in this file is the inset-track solid-thumb family: solid accent
// thumbs inside a darker capsule/rounded track, used INSIDE a well for
// value/layer selection (Steps/Velocity/Chance, Normal/Fill, BAR ranges,
// routing modes, mode toggles). Section switchers are NOT here — they are
// `StudioSectionPills` (the D-pill row floating above `StudioTabWell`). The
// underline `StudioSlotTabButton` grammar this file used to host was deleted
// when the last tab bar migrated onto the unified tab well.
//
//   • StudioSegmentedControl / StudioSegment — the SOLID-thumb segmented chips:
//     a pill container holding chips where the selected chip is a fully solid
//     accent thumb. Used by the track source/record controls, the drum-group
//     routing-mode control, the drum-kit accordion row/source switches, and the
//     capture history-length control. Layout dimensions vary per call site, so
//     the geometry is supplied via StudioSegmentedControl.Layout to keep every
//     surface pixel-identical to its hand-rolled predecessor.
//
//   • StudioModeSegmentedPill — the capsule MODE pill variant of the same
//     grammar (glyph + label segments on a capsule track).

// MARK: - Solid-thumb segmented control

struct StudioSegment<Value: Equatable> {
    let title: String
    let value: Value
    var isEnabled: Bool = true
    /// Optional CONTENT-state indicator ring (e.g. the playhead page on a bar
    /// selector) drawn around the chip. Content accent, never surface chrome.
    var indicatorAccent: Color?
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
                    // ux-canon-allow: eyebrow captions are structural labels,
                    // not stateful chrome — mutedText is the caption token.
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
            StudioTheme.subtleFill,
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
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(segment.indicatorAccent ?? .clear, lineWidth: 2)
        )
        // An unselected chip has a clear fill; without an explicit hit shape its
        // tap target shrinks to the text glyph. The whole chip should be tappable.
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
    }

    private func segmentForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.4)
        }
        // ux-canon-allow: unselected chips are DELIBERATELY neutral — the
        // value-selector grammar (locked Variant D) puts the one accent on the
        // solid selected thumb only; the accent is required at init, so a grey
        // chip here is never a silently-missing accent.
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

// MARK: - Themed menu picker

/// Shared label chrome for compact disclosure controls. `StudioMenuPicker`
/// uses this directly; action buttons that open a custom modal can reuse the
/// same visual language without falling back to bespoke picker styling.
struct StudioDisclosureLabel: View {
    let title: String
    var detail: String? = nil
    var symbolName: String? = nil
    var relationshipSymbolName: String = "chevron.compact.right"
    var minimumWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
            }

            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)

            if let detail {
                Image(systemName: relationshipSymbolName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)

                Text(detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                // ux-canon-allow: chevron affordance glyph — mutedText is
                // the caption token, not stateful chrome.
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: minimumWidth, minHeight: 28)
        .background(
            StudioTheme.subtleFill,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
    }
}

/// One option of `StudioMenuPicker`.
struct StudioMenuPickerOption<Value: Hashable> {
    let label: String
    let value: Value
}

/// Themed replacement for the native white pop-up `Picker` (canon Rule 6 —
/// no stock chrome): a `Menu` whose label is the studio chip — selected value
/// text + chevron on a subtleFill rounded chip with a border stroke, with the
/// same optional eyebrow title grammar as `StudioSegmentedControl`. Use this
/// wherever a value list is too long for the inset-track segmented control.
struct StudioMenuPicker<Value: Hashable>: View {
    /// Optional eyebrow label rendered above the chip.
    let title: String?
    @Binding var selection: Value
    let options: [StudioMenuPickerOption<Value>]
    var help: String = ""
    var symbolName: String? = nil

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? "—"
    }

    var body: some View {
        if let title {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    // ux-canon-allow: eyebrow captions are structural labels,
                    // not stateful chrome — mutedText is the caption token.
                    .foregroundStyle(StudioTheme.mutedText)

                menu
            }
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.label) { selection = option.value }
            }
        } label: {
            StudioDisclosureLabel(
                title: selectedLabel,
                symbolName: symbolName
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(StudioTheme.text)
        .tint(StudioTheme.text)
        .fixedSize()
        .help(help)
        .accessibilityLabel("\(title ?? help) \(selectedLabel)")
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
        .background(StudioTheme.subtleFill, in: Capsule())
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
                isSelected ? accent : StudioTheme.subtleFill,
                in: Capsule()
            )
            .contentShape(Capsule())
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
