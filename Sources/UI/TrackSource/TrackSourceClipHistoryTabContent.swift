import SwiftUI

struct TrackSourceClipHistoryTabContent: View {
    let model: ClipHistoryTransferViewModel
    let accent: Color
    let sourceSummary: String
    let isDestinationMode: Bool
    var isTransportRunning = true
    let onSaveClip: () -> Void

    // Renders inside the editor's `StudioTabWell` (unified tab grammar,
    // Variant D), which owns the outline + content inset.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            captureToolbar
            historyStrip
            virtualClipPreview
            footer
        }
        .onDisappear {
            model.stopAudition()
        }
    }

    private var captureToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            selectionLengthPicker
            Spacer(minLength: 0)
            Button {
                onSaveClip()
            } label: {
                Text(isDestinationMode ? "Choose slot" : "Save")
                    .studioText(.labelBold)
                    .foregroundStyle(model.selectedPseudoClip == nil ? StudioTheme.mutedText : StudioTheme.background)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        (model.selectedPseudoClip == nil ? StudioTheme.subtleFill : accent),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(model.selectedPseudoClip == nil ? StudioTheme.border : Color.clear, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
            .disabled(model.selectedPseudoClip == nil || isDestinationMode)
        }
    }

    private var virtualClipPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClipHistoryPianoRollPreview(
                content: model.previewContent,
                gridSteps: model.previewGridSteps,
                liveFillStepIndex: model.liveFillStepIndex,
                accent: accent,
                isTransportRunning: isTransportRunning
            )
            .frame(minHeight: 190)
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var selectionLengthPicker: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Length")
                .studioText(.microEmphasis)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 6) {
                ForEach(ClipHistoryTransferViewModel.lengthOptions, id: \.self) { option in
                    Button {
                        model.setLengthSteps(option)
                    } label: {
                        Text(ClipHistoryTransferViewModel.lengthLabel(for: option))
                            .studioText(.micro)
                            .foregroundStyle(lengthOptionTextColor(option))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(lengthOptionBackground(option), in: Capsule())
                            .overlay(Capsule().stroke(lengthOptionBorder(option), lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lengthOptionIsActive(_ option: Int) -> Bool {
        model.selectedPseudoClip != nil && model.lengthSteps == option
    }

    private func lengthOptionTextColor(_ option: Int) -> Color {
        lengthOptionIsActive(option) ? StudioTheme.background : StudioTheme.mutedText
    }

    private func lengthOptionBackground(_ option: Int) -> Color {
        lengthOptionIsActive(option) ? accent : Color.clear
    }

    private func lengthOptionBorder(_ option: Int) -> Color {
        lengthOptionIsActive(option) ? Color.clear : StudioTheme.border
    }

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: historyColumns, spacing: 0) {
                ForEach(model.sourceCells) { cell in
                    ClipHistoryMinibarCell(
                        cell: cell,
                        content: thumbnailContent(for: cell),
                        lengthLabel: historyCellLengthLabel(for: cell),
                        isSelected: model.selectedSourceIndex == cell.index,
                        isInRange: model.isSourceInSelectedRange(cell.index),
                        accent: accent
                    ) {
                        model.selectSource(cell.index)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .help("Tap a region to loop it; tap again to clear")
        }
    }

    // Canon Rule 3: the footer carries real failure state only — the workflow
    // hints that used to sit here were explainer prose.
    @ViewBuilder
    private var footer: some View {
        if let saveError = model.saveError {
            HStack(spacing: 10) {
                Text(saveError)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.warning)

                Spacer(minLength: 0)
            }
        }
    }

    private var historyColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 28), spacing: 4), count: ClipHistoryTransferViewModel.sourceCellCount)
    }

    private func thumbnailContent(for cell: ClipHistoryTransferViewModel.SourceCell) -> ClipContent? {
        guard !cell.isEmpty else {
            return nil
        }
        guard cell.isSelectable else {
            return nil
        }

        return PseudoClipState.materialize(
            sourceTrackID: model.trackID,
            from: model.snapshot,
            startStep: cell.startStep,
            lengthSteps: ClipHistoryTransferViewModel.stepsPerCell
        ).noteGrid
    }

    private func historyCellLengthLabel(for cell: ClipHistoryTransferViewModel.SourceCell) -> String {
        if cell.isEmpty {
            return "empty"
        }
        if !cell.isSelectable {
            return "live"
        }
        return model.selectedLengthLabel
    }
}

enum ClipHistoryCellPresentation {
    static func accessibilityLabel(
        index: Int,
        isEmpty: Bool,
        isSelectable: Bool,
        isSelected: Bool,
        lengthLabel: String
    ) -> String {
        if isEmpty {
            return "History region \(index + 1), unavailable, empty"
        }
        if !isSelectable {
            return "History region \(index + 1), unavailable, live buffer"
        }
        let selection = isSelected ? ", selected" : ""
        return "History region \(index + 1), available, \(lengthLabel)\(selection)"
    }
}

private struct ClipHistoryMinibarCell: View {
    let cell: ClipHistoryTransferViewModel.SourceCell
    let content: ClipContent?
    let lengthLabel: String
    let isSelected: Bool
    let isInRange: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ClipHistoryMiniPianoThumbnail(content: content, accent: accent)
                .frame(height: 42)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(5)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderFill, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: cell.isEmpty ? [4, 4] : []))
            )
        }
        .buttonStyle(.plain)
        .disabled(!cell.isSelectable)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        ClipHistoryCellPresentation.accessibilityLabel(
            index: cell.index,
            isEmpty: cell.isEmpty,
            isSelectable: cell.isSelectable,
            isSelected: isSelected,
            lengthLabel: lengthLabel
        )
    }

    /// Colour identifies, it never floods (ux-canon rule 12): region tiles
    /// stay neutral; selection/range reads from the accent border.
    private var backgroundFill: Color {
        StudioTheme.subtleFill
    }

    private var borderFill: Color {
        if isSelected || isInRange {
            return accent
        }
        return StudioTheme.border
    }
}

/// Layout math for the History tab's piano-roll preview, kept separate from
/// the view so the step-region division and pitch row mapping are testable.
struct ClipHistoryPreviewLayout: Equatable {
    enum StepDivision: Equatable {
        case bar
        case beat
        case step
    }

    static let stepsPerBar = 16
    static let stepsPerBeat = 4

    let gridSteps: Int
    let pitchRange: ClosedRange<Int>

    static func resolve(notes: [ClipNote], gridSteps: Int) -> ClipHistoryPreviewLayout {
        let pitches = notes.map(\.pitch)
        let low = max(0, (pitches.min() ?? 48) - 2)
        let high = min(127, (pitches.max() ?? 72) + 2)
        return ClipHistoryPreviewLayout(
            gridSteps: max(1, gridSteps),
            pitchRange: low...max(low, high)
        )
    }

    var pitchRowCount: Int {
        pitchRange.upperBound - pitchRange.lowerBound + 1
    }

    /// Vertical row for a pitch: row 0 is the highest pitch in range, so
    /// higher notes render higher in the preview.
    func rowIndex(forPitch pitch: Int) -> Int {
        pitchRange.upperBound - min(max(pitch, pitchRange.lowerBound), pitchRange.upperBound)
    }

    func clampedStep(_ step: Int) -> Int {
        min(max(step, 0), gridSteps - 1)
    }

    /// Emphasis of the vertical divider at a step boundary: bar starts are
    /// strongest, beat starts medium, plain steps faint, so the grid reads
    /// rhythmically at one step region per step of the selection.
    func stepDivision(at step: Int) -> StepDivision {
        if step % Self.stepsPerBar == 0 {
            return .bar
        }
        if step % Self.stepsPerBeat == 0 {
            return .beat
        }
        return .step
    }
}

/// The canonical clip-history live-buffer piano roll. Reused by the kit capture
/// surface (one per part) so kit history shares the single-track grammar instead
/// of a bespoke strip.
struct ClipHistoryPianoRollPreview: View {
    let content: ClipContent?
    let gridSteps: Int
    let liveFillStepIndex: Int?
    let accent: Color
    var isTransportRunning = true
    /// When set, an accent-bordered rectangle is drawn around these step
    /// columns over the buffer — the save-window highlight used by the kit
    /// capture surface. Default nil keeps the single-track caller unchanged.
    var selectionRange: Range<Int>? = nil

    private var notes: [ClipNote] {
        clipNotes(from: content)
    }

    private var layout: ClipHistoryPreviewLayout {
        ClipHistoryPreviewLayout.resolve(notes: notes, gridSteps: gridSteps)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = self.layout
            let resolvedLength = layout.gridSteps
            let pitchRange = layout.pitchRange
            let pitchCount = max(1, layout.pitchRowCount)
            let stepWidth = geometry.size.width / CGFloat(resolvedLength)
            let laneHeight = geometry.size.height / CGFloat(pitchCount)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(StudioTheme.subtleFill)

                ForEach(Array(pitchRange.reversed()), id: \.self) { pitch in
                    let rowOffset = laneHeight * CGFloat(pitchRange.upperBound - pitch)
                    if pitch % 12 == 0 {
                        Rectangle()
                            .fill(StudioTheme.subtleFill)
                            .frame(height: max(laneHeight, 1))
                            .offset(y: rowOffset)
                    }
                    Rectangle()
                        .fill(StudioTheme.borderSubtleFill)
                        .frame(height: 1)
                        .offset(y: rowOffset)
                }

                ForEach(0..<resolvedLength, id: \.self) { step in
                    Rectangle()
                        .fill(stepDividerFill(layout.stepDivision(at: step)))
                        .frame(width: 1)
                        .offset(x: stepWidth * CGFloat(step))
                }

                if let liveFillStepIndex {
                    // Colour identifies, it never floods (ux-canon rule 12):
                    // the filled region is a neutral wash; the write head is a
                    // solid accent line.
                    Rectangle()
                        .fill(StudioTheme.subtleFill)
                        .frame(width: max(stepWidth * CGFloat(layout.clampedStep(liveFillStepIndex) + 1), 1))

                    Rectangle()
                        .fill(accent)
                        .frame(width: 2)
                        .offset(x: stepWidth * CGFloat(layout.clampedStep(liveFillStepIndex) + 1) - 1)
                }

                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    let yIndex = layout.rowIndex(forPitch: note.pitch)
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .fill(accent)
                        .frame(
                            width: max(stepWidth * CGFloat(max(1, note.lengthSteps)) - 2, 6),
                            height: max(laneHeight - 3, 5)
                        )
                        .offset(
                            x: stepWidth * CGFloat(layout.clampedStep(note.startStep)) + 1,
                            y: laneHeight * CGFloat(yIndex) + 1.5
                        )
                }

                if let selectionRange, !selectionRange.isEmpty {
                    let clampedLower = min(max(selectionRange.lowerBound, 0), resolvedLength)
                    let clampedUpper = min(max(selectionRange.upperBound, clampedLower), resolvedLength)
                    let selectionWidth = max(stepWidth * CGFloat(clampedUpper - clampedLower), 2)
                    // Colour identifies, it never floods (ux-canon rule 12):
                    // the save window reads from the accent outline alone.
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(accent, lineWidth: 2)
                        .frame(width: selectionWidth)
                        .frame(maxHeight: .infinity)
                        .offset(x: stepWidth * CGFloat(clampedLower))
                }

                // Canon Rule 3: no instruction prose on the surface — the
                // stopped-transport hint lives in the container tooltip below;
                // "Waiting for live notes" is real state while playing.
                if notes.isEmpty, isTransportRunning {
                    Text("Waiting for live notes")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .help("Press play to record live history into the rolling buffer")
        }
    }

    private func stepDividerFill(_ division: ClipHistoryPreviewLayout.StepDivision) -> Color {
        switch division {
        case .bar:
            return StudioTheme.dividerSubtleFill
        case .beat:
            return StudioTheme.dividerFaintFill
        case .step:
            return StudioTheme.dividerLowFill
        }
    }
}

private struct ClipHistoryMiniPianoThumbnail: View {
    let content: ClipContent?
    let accent: Color

    private var notes: [ClipNote] {
        Array(clipNotes(from: content).prefix(8))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let stepWidth = width / CGFloat(ClipHistoryTransferViewModel.stepsPerCell)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .fill(StudioTheme.subtleFill)

                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? StudioTheme.borderLowFill : Color.clear)
                            .frame(width: width / 4)
                    }
                }

                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    let normalizedPitch = Double(min(max(note.pitch, 36), 84) - 36) / 48.0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(
                            width: max(stepWidth * CGFloat(max(1, note.lengthSteps)), 3),
                            height: 4
                        )
                        .offset(
                            x: stepWidth * CGFloat(min(max(note.startStep, 0), ClipHistoryTransferViewModel.stepsPerCell - 1)),
                            y: max(1, height - CGFloat(normalizedPitch) * height - 5)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
    }
}

struct CompactStepPatternRowsPreview: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        let steps: [Bool]

        init(label: String, steps: [Bool]) {
            self.id = label
            self.label = label
            self.steps = steps
        }
    }

    let rows: [Row]
    let accent: Color
    var labelWidth: CGFloat = 54
    var cellSize: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Text(row.label)
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: labelWidth, alignment: .leading)
                        .lineLimit(1)

                    HStack(spacing: 2) {
                        ForEach(Array(row.steps.enumerated()), id: \.offset) { _, isOn in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(isOn ? accent : StudioTheme.inset)
                                .frame(width: cellSize, height: cellSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .stroke(StudioTheme.border.opacity(0.75), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
        }
    }
}

private func clipNotes(from content: ClipContent?) -> [ClipNote] {
    guard let steps = content?.normalized.noteGridSteps else {
        return []
    }

    return steps.enumerated().flatMap { stepIndex, step -> [ClipNote] in
        let notes = (step.main?.notes ?? []) + (step.fill?.notes ?? [])
        return notes.map { note in
            ClipNote(
                pitch: note.pitch,
                startStep: stepIndex,
                lengthSteps: note.lengthSteps,
                velocity: note.velocity
            )
        }
    }
}
