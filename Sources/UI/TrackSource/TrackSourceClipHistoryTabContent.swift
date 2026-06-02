import SwiftUI

struct TrackSourceClipHistoryTabContent: View {
    let model: ClipHistoryTransferViewModel
    let accent: Color
    let sourceSummary: String
    let isDestinationMode: Bool
    let onRefresh: () -> Void
    let onSaveClip: () -> Void

    var body: some View {
        TrackSourceSelectedWellBody(accent: accent, isEmpty: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                virtualClipPreview
                historyStrip
                footer
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
        }
        .onDisappear {
            model.stopAudition()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("History")
                    .studioText(.bodyBold)
                    .foregroundStyle(StudioTheme.text)

                Text(sourceSummary)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)

            Button("Refresh") {
                onRefresh()
            }
            .buttonStyle(.plain)
            .studioText(.labelBold)
            .foregroundStyle(StudioTheme.mutedText)

            Button {
                onSaveClip()
            } label: {
                Text(isDestinationMode ? "Choose Slot" : "Save Clip")
                    .studioText(.labelBold)
                    .foregroundStyle(model.selectedPseudoClip == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        (model.selectedPseudoClip == nil ? Color.white.opacity(StudioOpacity.subtleFill) : accent.opacity(StudioOpacity.selectedFill)),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(model.selectedPseudoClip == nil ? StudioTheme.border : accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.selectedPseudoClip == nil || isDestinationMode)
        }
    }

    private var virtualClipPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Virtual Preview")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)

                Text(model.selectedLengthLabel)
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                    .overlay(Capsule().stroke(accent.opacity(StudioOpacity.ghostStroke), lineWidth: 1))

                if model.isAuditioning {
                    Text("Auditioning")
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.success)
                }

                Spacer(minLength: 0)
                lengthPicker
            }

            ClipHistoryPianoRollPreview(
                content: model.previewContent,
                lengthSteps: model.lengthSteps,
                accent: accent
            )
            .frame(minHeight: 250)
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var lengthPicker: some View {
        HStack(spacing: 6) {
            ForEach(ClipHistoryTransferViewModel.lengthOptions, id: \.self) { option in
                Button {
                    model.setLengthSteps(option)
                } label: {
                    Text(ClipHistoryTransferViewModel.lengthLabel(for: option))
                        .studioText(.micro)
                        .foregroundStyle(model.lengthSteps == option ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            (model.lengthSteps == option ? accent.opacity(StudioOpacity.selectedFill) : Color.clear),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(model.lengthSteps == option ? accent : StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Output")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Spacer()
                Text("Tap a region to loop it. Tap again to clear.")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            LazyVGrid(columns: historyColumns, spacing: 0) {
                ForEach(model.sourceCells) { cell in
                    ClipHistoryMinibarCell(
                        cell: cell,
                        content: thumbnailContent(for: cell),
                        lengthLabel: cell.isEmpty ? "empty" : model.selectedLengthLabel,
                        isSelected: model.selectedSourceIndex == cell.index,
                        isInRange: model.isSourceInSelectedRange(cell.index),
                        accent: accent
                    ) {
                        model.selectSource(cell.index)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let saveError = model.saveError {
                Text(saveError)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.amber)
            } else if model.selectedPseudoClip == nil {
                Text("Choose a history region before saving.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            } else {
                Text("Save Clip uses the pattern row above.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
    }

    private var historyColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 28), spacing: 4), count: ClipHistoryTransferViewModel.sourceCellCount)
    }

    private func thumbnailContent(for cell: ClipHistoryTransferViewModel.SourceCell) -> ClipContent? {
        guard !cell.isEmpty else {
            return nil
        }

        return PseudoClipState.materialize(
            sourceTrackID: model.trackID,
            from: model.snapshot,
            startStep: cell.startStep,
            lengthSteps: ClipHistoryTransferViewModel.stepsPerCell
        ).noteGrid
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text("\(cell.index + 1)")
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Spacer(minLength: 0)
                    Text(lengthLabel)
                        .studioText(.micro)
                        .foregroundStyle(cell.isEmpty ? StudioTheme.mutedText : StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }

                ClipHistoryMiniPianoThumbnail(content: content, accent: accent)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(5)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderFill, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: cell.isEmpty ? [4, 4] : []))
            )
        }
        .buttonStyle(.plain)
        .disabled(cell.isEmpty)
        .accessibilityLabel(cell.isEmpty ? "History region \(cell.index + 1), empty" : "History region \(cell.index + 1), \(lengthLabel)")
    }

    private var backgroundFill: Color {
        if isSelected {
            return accent.opacity(StudioOpacity.selectedFill)
        }
        if isInRange {
            return accent.opacity(StudioOpacity.subtleFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var borderFill: Color {
        if isSelected || isInRange {
            return accent
        }
        return StudioTheme.border
    }
}

private struct ClipHistoryPianoRollPreview: View {
    let content: ClipContent?
    let lengthSteps: Int
    let accent: Color

    private var notes: [ClipNote] {
        clipNotes(from: content)
    }

    private var pitchRange: ClosedRange<Int> {
        let pitches = notes.map(\.pitch)
        let low = max(0, (pitches.min() ?? 48) - 2)
        let high = min(127, (pitches.max() ?? 72) + 2)
        return low...max(low, high)
    }

    var body: some View {
        GeometryReader { geometry in
            let resolvedLength = max(1, lengthSteps)
            let pitchCount = max(1, pitchRange.upperBound - pitchRange.lowerBound + 1)
            let stepWidth = geometry.size.width / CGFloat(resolvedLength)
            let laneHeight = geometry.size.height / CGFloat(pitchCount)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.subtleFill))

                ForEach(0..<resolvedLength, id: \.self) { step in
                    Rectangle()
                        .fill(step % ClipHistoryTransferViewModel.stepsPerCell == 0 ? Color.white.opacity(StudioOpacity.borderFaint) : Color.white.opacity(0.03))
                        .frame(width: max(stepWidth, 1))
                        .offset(x: stepWidth * CGFloat(step))
                }

                ForEach(Array(pitchRange.reversed()), id: \.self) { pitch in
                    Rectangle()
                        .fill(Color.white.opacity(pitch % 12 == 0 ? StudioOpacity.borderFaint : 0.025))
                        .frame(height: max(laneHeight, 1))
                        .offset(y: laneHeight * CGFloat(pitchRange.upperBound - pitch))
                }

                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    let yIndex = pitchRange.upperBound - min(max(note.pitch, pitchRange.lowerBound), pitchRange.upperBound)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accent.opacity(0.82))
                        .frame(
                            width: max(stepWidth * CGFloat(max(1, note.lengthSteps)) - 2, 6),
                            height: max(laneHeight - 3, 5)
                        )
                        .offset(
                            x: stepWidth * CGFloat(min(max(note.startStep, 0), resolvedLength - 1)) + 1,
                            y: laneHeight * CGFloat(yIndex) + 1.5
                        )
                }

                if notes.isEmpty {
                    Text("Select a history region.")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
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
                    .fill(Color.white.opacity(StudioOpacity.subtleFill))

                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? StudioTheme.border.opacity(0.25) : Color.clear)
                            .frame(width: width / 4)
                    }
                }

                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    let normalizedPitch = Double(min(max(note.pitch, 36), 84) - 36) / 48.0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent.opacity(0.8))
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
