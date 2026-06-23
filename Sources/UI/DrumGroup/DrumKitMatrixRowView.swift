import SwiftUI

/// One part row. Compact: part name + chevron column (left) and the SAME
/// full-size step grid (right). EXPANDED (AC21): the right area becomes the
/// inline detail panel (mini-tabs) — the row grows vertically while every other
/// row stays compact. Generator-backed and non-note-grid rows show their badge
/// and read-only cells when compact.
struct DrumKitMatrixRowView<DetailPanel: View>: View {
    let row: DrumKitMatrixModel.Row
    let layer: DrumKitMatrixLayer
    /// Absolute step index of the first visible cell (selected bar × 16).
    let pageOffset: Int
    /// Fixed grid width — always 16 columns.
    let stepsPerBar: Int
    let accent: Color
    /// Whether this row's inline accordion detail panel is open (AC21).
    let isExpanded: Bool
    /// Receives the ABSOLUTE step index (pageOffset + grid column).
    let onTapStep: (Int) -> Void
    let onDragStep: (Int, Double) -> Void
    /// Toggle the inline accordion for this row (the name button / chevron).
    let onToggleExpand: () -> Void
    /// The inline detail panel content (mini-tabs), owned by the parent so it
    /// can reach `session`/`engineController` for the member's real controls.
    @ViewBuilder let detailPanel: () -> DetailPanel

    var body: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 10) {
            nameColumn
            if isExpanded {
                detailPanel()
            } else {
                // Always fill the remaining row width so every layer renders the
                // same full-width 16-column grid. Without this the value-bar
                // (velocity/chance) cells let the LazyVGrid collapse to its
                // intrinsic width and the row looks squashed.
                stepRegion
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(
            (isExpanded ? accent.opacity(0.06) : Color.white.opacity(StudioOpacity.subtleFill)),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(
                    isExpanded
                        ? accent.opacity(StudioOpacity.mediumStroke)
                        : StudioTheme.border,
                    lineWidth: StudioMetrics.borderWidth
                )
        )
    }

    /// Part name + badges as a fixed-width column to the LEFT of the step grid /
    /// detail panel. The name button toggles the inline accordion (AC21); the
    /// full dive-in stays available as "Open full editor" inside the panel.
    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggleExpand) {
                HStack(spacing: 5) {
                    Text(row.partName)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isExpanded ? accent : StudioTheme.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(row.partName)" : "Expand \(row.partName) inline")
            .accessibilityIdentifier(isExpanded ? "kit-row-collapse" : "kit-row-expand")
            .accessibilityLabel(isExpanded ? "Collapse \(row.partName)" : "Expand \(row.partName)")

            if let clipLengthLabel = row.clipLengthLabel {
                Text(clipLengthLabel)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("kit-row-clip-length")
                    .help("Clip length for \(row.partName)")
            }

            readOnlyBadge
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private var readOnlyBadge: some View {
        switch row.content {
        case .editable:
            EmptyView()
        case let .generator(detail):
            limitedBadge("GEN", detail: detail)
        case let .readOnly(badge, detail, _):
            limitedBadge(badge, detail: detail)
        }
    }

    private func limitedBadge(_ badge: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(badge)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
            Text(detail)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
        }
        .help("Read-only: \(detail)")
    }

    @ViewBuilder
    private var stepRegion: some View {
        switch row.content {
        case let .editable(_, _, steps):
            // Always a 16-cell window starting at the selected bar. The grid's
            // `indexOffset` makes every closure index and cell label ABSOLUTE,
            // so tap/drag commit through the full-length step array unchanged.
            let states = windowedEditableStates(steps: steps)
            StepGridView(
                stepStates: states,
                indexOffset: pageOffset,
                contentProvider: { index, _ in
                    cellContent(steps: steps, index: index)
                },
                onValueDrag: layer == .steps ? nil : { index, fraction in
                    onDragStep(index, fraction)
                },
                advanceStep: { index in
                    onTapStep(index)
                }
            )

        case .generator:
            readOnlyGrid(states: Array(repeating: StepVisualState.off, count: stepsPerBar))

        case let .readOnly(_, _, pattern):
            readOnlyGrid(states: windowedReadOnlyStates(pattern: pattern))
        }
    }

    /// 16 visual states for the current bar window over `steps`, padding cells
    /// past the row's length with `.off`.
    private func windowedEditableStates(steps: [ClipStep]) -> [StepVisualState] {
        (0..<stepsPerBar).map { local in
            let absolute = pageOffset + local
            guard steps.indices.contains(absolute) else { return .off }
            return ClipNoteGridStepEditing.visualState(for: steps[absolute], lane: .main)
        }
    }

    /// 16 read-only states for the current bar window over a boolean pattern.
    private func windowedReadOnlyStates(pattern: [Bool]) -> [StepVisualState] {
        (0..<stepsPerBar).map { local in
            let absolute = pageOffset + local
            return pattern.indices.contains(absolute) && pattern[absolute] ? .on : .off
        }
    }

    private func readOnlyGrid(states: [StepVisualState]) -> some View {
        StepGridView(
            stepStates: states,
            indexOffset: pageOffset,
            advanceStep: { _ in }
        )
        .allowsHitTesting(false)
        .opacity(0.55)
    }

    private func cellContent(steps: [ClipStep], index: Int) -> StepCellContent {
        guard steps.indices.contains(index) else {
            return layer == .steps ? .toggle : .valueBar(fraction: 0)
        }
        switch layer {
        case .steps:
            return .toggle
        case .velocity:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.velocityValue(for: steps[index], lane: .main) / 127.0
            )
        case .chance:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.chanceValue(for: steps[index], lane: .main)
            )
        }
    }
}
