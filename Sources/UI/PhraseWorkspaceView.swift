import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    @State private var selectedBarIndex = 0
    @State private var selectedLayer: PhraseAbstractKind = .intensity

    private let phraseColumnWidth: CGFloat = 190
    private let trackColumnWidth: CGFloat = 160

    private var phrases: [PhraseModel] {
        document.model.phrases
    }

    private var tracks: [StepSequenceTrack] {
        document.model.tracks
    }

    private var selectedPhrase: PhraseModel {
        document.model.selectedPhrase
    }

    private var selectedTrack: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var selectedRow: PhraseAbstractRow {
        row(for: selectedPhrase, kind: selectedLayer)
    }

    private var currentBarIndex: Int {
        min(selectedBarIndex, max(0, selectedPhrase.lengthBars - 1))
    }

    private var layerAccent: Color {
        accent(for: selectedLayer)
    }

    private var selectedCellMode: PhraseCellEditMode {
        selectedPhrase.cellMode(for: selectedLayer, trackID: selectedTrack.id)
    }

    private var selectedPatternIndex: Int {
        document.model.selectedPatternIndex(for: selectedTrack.id)
    }

    private var selectedPattern: TrackPatternSlot {
        document.model.selectedPattern(for: selectedTrack.id)
    }

    private var selectedSourceMode: TrackSourceMode {
        selectedPattern.sourceRef.mode
    }

    private var playbackPhase: PlaybackPhase? {
        guard engineController.isRunning, !phrases.isEmpty else {
            return nil
        }

        let stepsPerBar = max(1, phrases.first?.stepsPerBar ?? 16)
        let totalBars = phrases.reduce(0) { partial, phrase in
            partial + max(1, phrase.lengthBars)
        }

        guard totalBars > 0 else {
            return nil
        }

        let absoluteBar = Int(engineController.transportTickIndex) / stepsPerBar
        var cycleBar = absoluteBar % totalBars

        for (phraseIndex, phrase) in phrases.enumerated() {
            let phraseBars = max(1, phrase.lengthBars)
            if cycleBar < phraseBars {
                return PlaybackPhase(phraseIndex: phraseIndex, barIndex: cycleBar)
            }
            cycleBar -= phraseBars
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Phrase Matrix",
                eyebrow: "Tracks sit across the top, phrases run down the rows, and the selected layer changes what every cell means.",
                accent: StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    topMetrics
                    layerPalette
                    matrix
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(
                    title: "Selected Phrase",
                    eyebrow: "Edit the currently selected phrase row while the matrix stays focused on overview and playback.",
                    accent: layerAccent
                ) {
                    selectedPhrasePanel
                }

                StudioPanel(
                    title: "Selected Cell",
                    eyebrow: "Track-scoped cell mode and pipeline placeholders live here, like the old phatcontroller cell modal but kept docked in the main surface.",
                    accent: StudioTheme.amber
                ) {
                    selectedCellPanel
                }
            }
        }
        .onChange(of: document.model.selectedPhraseID) {
            selectedBarIndex = min(selectedBarIndex, max(0, selectedPhrase.lengthBars - 1))
        }
    }

    private var topMetrics: some View {
        HStack(alignment: .center, spacing: 10) {
            StudioMetricPill(title: "Transport", value: engineController.transportPosition, accent: StudioTheme.cyan)
            StudioMetricPill(title: "Layer", value: selectedLayer.label, accent: layerAccent)
            StudioMetricPill(title: "Rows", value: "\(phrases.count)", accent: StudioTheme.violet)
            StudioMetricPill(title: "Tracks", value: "\(tracks.count)", accent: StudioTheme.amber)

            if let playbackPhase {
                StudioMetricPill(
                    title: "Now Playing",
                    value: phrases[playbackPhase.phraseIndex].name,
                    accent: StudioTheme.success
                )
            }

            Spacer()

            Button("Add Phrase") {
                document.model.appendPhrase()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Duplicate") {
                document.model.duplicateSelectedPhrase()
            }
            .buttonStyle(.bordered)

            Button("Remove") {
                document.model.removeSelectedPhrase()
            }
            .buttonStyle(.bordered)
            .disabled(phrases.count == 1)
        }
    }

    private var layerPalette: some View {
        HStack(spacing: 10) {
            ForEach(PhraseAbstractKind.allCases, id: \.self) { kind in
                Button {
                    selectedLayer = kind
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.label.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                        Text(layerSubtitle(for: kind))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .foregroundStyle(StudioTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent(for: kind).opacity(selectedLayer == kind ? 0.18 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accent(for: kind).opacity(selectedLayer == kind ? 0.65 : 0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                matrixHeader

                ForEach(Array(phrases.enumerated()), id: \.element.id) { phraseIndex, phrase in
                    PhraseMatrixRow(
                        phrase: phrase,
                        tracks: tracks,
                        selectedLayer: selectedLayer,
                        selectedPhraseID: document.model.selectedPhraseID,
                        selectedTrackID: document.model.selectedTrackID,
                        phraseColumnWidth: phraseColumnWidth,
                        trackColumnWidth: trackColumnWidth,
                        rowAccent: layerAccent,
                        activePlayback: playbackPhase?.phraseIndex == phraseIndex ? playbackPhase : nil,
                        onSelectPhrase: {
                            document.model.selectPhrase(id: phrase.id)
                        },
                        onSelectCell: { trackID in
                            document.model.selectPhrase(id: phrase.id)
                            document.model.selectTrack(id: trackID)
                        }
                    )
                }
            }
        }
    }

    private var matrixHeader: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PHRASES")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("As transport advances, the active highlight moves down to the next phrase row.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: phraseColumnWidth, alignment: .leading)

            ForEach(tracks, id: \.id) { track in
                Button {
                    document.model.selectTrack(id: track.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        HStack(spacing: 6) {
                            Text(track.trackType.shortLabel.uppercased())
                            Text(track.output == .midiOut ? "MIDI" : "AU")
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    }
                    .frame(width: trackColumnWidth, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(document.model.selectedTrackID == track.id ? StudioTheme.cyan.opacity(0.14) : Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(document.model.selectedTrackID == track.id ? StudioTheme.cyan.opacity(0.55) : StudioTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedPhrasePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StudioMetricPill(title: "Phrase", value: selectedPhrase.name, accent: layerAccent)
                StudioMetricPill(title: "Bars", value: "\(selectedPhrase.lengthBars)", accent: StudioTheme.amber)
                StudioMetricPill(title: "Bar Page", value: "\(currentBarIndex + 1) / \(selectedPhrase.lengthBars)", accent: StudioTheme.success)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phrase Name")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)

                    TextField("Phrase Name", text: phraseNameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Length")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)

                    Stepper("\(selectedPhrase.lengthBars) bars", value: phraseBarCountBinding, in: 1...16)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Previous Bar") {
                        selectedBarIndex = max(0, currentBarIndex - 1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentBarIndex == 0)

                    Button("Next Bar") {
                        selectedBarIndex = min(max(0, selectedPhrase.lengthBars - 1), currentBarIndex + 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(layerAccent)
                    .disabled(currentBarIndex >= selectedPhrase.lengthBars - 1)
                }
            }

            PhraseLayerEditor(
                row: selectedRow,
                layer: selectedLayer,
                accent: layerAccent,
                currentBarIndex: currentBarIndex,
                stepsPerBar: selectedPhrase.stepsPerBar,
                onCycleStep: { stepIndex in
                    mutateSelectedPhrase { phrase in
                        phrase.cycleAbstractValue(for: selectedLayer, at: stepIndex)
                    }
                }
            )

            Text("This lower editor is the detailed lane view for the selected phrase row. The matrix above stays overview-first, while this panel gives the chosen phrase and layer a closer editing surface.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var selectedCellPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StudioMetricPill(title: "Track", value: selectedTrack.name, accent: StudioTheme.cyan)
                StudioMetricPill(title: "Type", value: selectedTrack.trackType.shortLabel, accent: StudioTheme.violet)
                StudioMetricPill(title: "Mode", value: selectedCellMode.shortLabel, accent: StudioTheme.amber)
                StudioMetricPill(title: "Pattern", value: "P\(selectedPatternIndex + 1)", accent: StudioTheme.success)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cell Mode")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                HStack(spacing: 10) {
                    ForEach(PhraseCellEditMode.allCases, id: \.self) { mode in
                        Button {
                            mutateSelectedPhrase { phrase in
                                phrase.setCellMode(mode, for: selectedLayer, trackID: selectedTrack.id)
                            }
                        } label: {
                            Text(mode.shortLabel)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedCellMode == mode ? StudioTheme.amber.opacity(0.16) : Color.white.opacity(0.03))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selectedCellMode == mode ? StudioTheme.amber.opacity(0.6) : StudioTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(selectedCellMode.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pattern Slot")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                PatternSlotPalette(selectedSlot: selectedPatternIndexBinding)

                Text("This phrase now stores a pattern index for each track. The selected slot resolves to a shared \(selectedSourceMode.label.lowercased()) entry, so changing slot numbers here is lightweight while editing the slot itself still happens in the Track workspace.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if selectedTrack.trackType != .instrument {
                StudioPlaceholderTile(
                    title: selectedTrack.trackType == .drumRack ? "Drum Lane Routing" : "Slice Lane Routing",
                    detail: selectedTrack.trackType == .drumRack
                        ? "This cell will eventually host tagged drum-lane sources and phrase-scoped trigger modes."
                        : "This cell will eventually host slice trigger patterns, slice groups, and phrase-specific loop transforms.",
                    accent: StudioTheme.violet
                )
            }

            VStack(spacing: 12) {
                StudioPlaceholderTile(
                    title: "Per-Layer Values",
                    detail: "The selected layer already has a durable cell mode. The next deeper slice is storing track-specific automation content, not just the lane's visual placeholder.",
                    accent: layerAccent
                )
                StudioPlaceholderTile(
                    title: "Concrete Rows",
                    detail: "Mute, fills, sends, repeat, transpose, and bus rows should land in this same matrix pattern once their models exist.",
                    accent: StudioTheme.success
                )
            }
        }
    }

    private var phraseNameBinding: Binding<String> {
        Binding(
            get: { selectedPhrase.name },
            set: { newValue in
                mutateSelectedPhrase { phrase in
                    phrase.name = newValue
                }
            }
        )
    }

    private var phraseBarCountBinding: Binding<Int> {
        Binding(
            get: { selectedPhrase.lengthBars },
            set: { newValue in
                mutateSelectedPhrase { phrase in
                    phrase.lengthBars = max(1, newValue)
                }
                selectedBarIndex = min(selectedBarIndex, max(0, selectedPhrase.lengthBars - 1))
            }
        )
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.model.selectedPatternIndex(for: selectedTrack.id) },
            set: { document.model.setSelectedPatternIndex($0, for: selectedTrack.id) }
        )
    }

    private func mutateSelectedPhrase(_ update: (inout PhraseModel) -> Void) {
        var phrase = selectedPhrase
        update(&phrase)
        document.model.selectedPhrase = phrase
    }

    private func row(for phrase: PhraseModel, kind: PhraseAbstractKind) -> PhraseAbstractRow {
        phrase.abstractRows.first(where: { $0.kind == kind }) ?? PhraseAbstractRow(kind: kind, values: Array(repeating: 0, count: phrase.stepCount))
    }

    private func accent(for kind: PhraseAbstractKind) -> Color {
        switch kind {
        case .intensity, .density:
            return StudioTheme.cyan
        case .register, .brightness:
            return StudioTheme.violet
        case .tension, .variance:
            return StudioTheme.amber
        }
    }

    private func layerSubtitle(for kind: PhraseAbstractKind) -> String {
        switch kind {
        case .intensity:
            return "overall lift"
        case .density:
            return "event amount"
        case .register:
            return "pitch height"
        case .tension:
            return "harmonic strain"
        case .variance:
            return "instability"
        case .brightness:
            return "tone color"
        }
    }
}

private struct PhraseMatrixRow: View {
    let phrase: PhraseModel
    let tracks: [StepSequenceTrack]
    let selectedLayer: PhraseAbstractKind
    let selectedPhraseID: UUID
    let selectedTrackID: UUID
    let phraseColumnWidth: CGFloat
    let trackColumnWidth: CGFloat
    let rowAccent: Color
    let activePlayback: PlaybackPhase?
    let onSelectPhrase: () -> Void
    let onSelectCell: (UUID) -> Void

    private var isSelected: Bool {
        selectedPhraseID == phrase.id
    }

    private var isPlaying: Bool {
        activePlayback != nil
    }

    private var layerValues: [Double] {
        phrase.abstractRows.first(where: { $0.kind == selectedLayer })?.values ?? Array(repeating: 0, count: phrase.stepCount)
    }

    private var averageValueText: String {
        let average = layerValues.isEmpty ? 0 : layerValues.reduce(0, +) / Double(layerValues.count)
        return "\(Int((average * 100).rounded()))%"
    }

    private var barPreview: [Double] {
        let maxBars = max(1, phrase.lengthBars)
        let stepsPerBar = max(1, phrase.stepsPerBar)
        return (0..<maxBars).map { barIndex in
            let start = barIndex * stepsPerBar
            let end = min(layerValues.count, start + stepsPerBar)
            guard start < end else {
                return 0
            }
            let slice = layerValues[start..<end]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onSelectPhrase) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phrase.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                            Text("\(phrase.lengthBars) bars")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)
                        }

                        Spacer()

                        if isPlaying {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(StudioTheme.success)
                        }
                    }

                    PhraseBarPreview(
                        values: barPreview,
                        accent: rowAccent,
                        activeBarIndex: activePlayback?.barIndex
                    )

                    Text(isPlaying ? "The transport is currently inside this phrase row." : "Select this row to edit its lane details below.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: phraseColumnWidth, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isPlaying ? rowAccent.opacity(0.14) : Color.white.opacity(isSelected ? 0.06 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            isPlaying ? rowAccent.opacity(0.7) : (isSelected ? rowAccent.opacity(0.35) : StudioTheme.border),
                            lineWidth: isPlaying ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            ForEach(tracks, id: \.id) { track in
                Button {
                    onSelectCell(track.id)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(phrase.cellMode(for: selectedLayer, trackID: track.id).shortLabel.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.9)
                                .foregroundStyle(rowAccent)
                            Spacer()
                            if selectedTrackID == track.id && isSelected {
                                Image(systemName: "scope")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(StudioTheme.text)
                            }
                        }

                        Text(averageValueText)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        PhraseBarPreview(
                            values: barPreview,
                            accent: rowAccent,
                            activeBarIndex: activePlayback?.barIndex
                        )

                        Text(footerText(for: track))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: trackColumnWidth, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(cellFill(for: track))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(cellStroke(for: track), lineWidth: selectedTrackID == track.id && isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footerText(for track: StepSequenceTrack) -> String {
        let patternIndex = phrase.patternIndex(for: track.id)
        return "P\(patternIndex + 1) • \(track.trackType.shortLabel)"
    }

    private func cellFill(for track: StepSequenceTrack) -> Color {
        if selectedTrackID == track.id && isSelected {
            return rowAccent.opacity(0.16)
        }
        if isPlaying {
            return Color.white.opacity(0.07)
        }
        return Color.white.opacity(0.03)
    }

    private func cellStroke(for track: StepSequenceTrack) -> Color {
        if selectedTrackID == track.id && isSelected {
            return rowAccent.opacity(0.7)
        }
        if isPlaying {
            return rowAccent.opacity(0.28)
        }
        return StudioTheme.border
    }
}

private struct PhraseLayerEditor: View {
    let row: PhraseAbstractRow
    let layer: PhraseAbstractKind
    let accent: Color
    let currentBarIndex: Int
    let stepsPerBar: Int
    let onCycleStep: (Int) -> Void

    private var barValues: ArraySlice<Double> {
        let start = currentBarIndex * stepsPerBar
        let end = min(row.values.count, start + stepsPerBar)
        return row.values[start..<end]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(layer.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                Text("Tap steps to cycle the lane amount for the selected bar page.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(barValues.enumerated()), id: \.offset) { offset, value in
                    Button {
                        onCycleStep(currentBarIndex * stepsPerBar + offset)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [accent.opacity(value == 0 ? 0.18 : 0.92), accent.opacity(0.35)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: max(12, 18 + (value * 54)))
                                .frame(maxWidth: .infinity, alignment: .bottom)

                            Text("\(offset + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 94, alignment: .bottom)
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct PhraseBarPreview: View {
    let values: [Double]
    let accent: Color
    var activeBarIndex: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill(for: value, isActive: activeBarIndex == index))
                    .frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12)
            }
        }
    }

    private func fill(for value: Double, isActive: Bool) -> Color {
        if isActive {
            return StudioTheme.success
        }
        if value == 0 {
            return Color.white.opacity(0.12)
        }
        return accent.opacity(0.28 + (value * 0.55))
    }
}

private struct PatternSlotPalette: View {
    @Binding var selectedSlot: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                Button {
                    selectedSlot = slotIndex
                } label: {
                    Text("\(slotIndex + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedSlot == slotIndex ? StudioTheme.success.opacity(0.2) : Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedSlot == slotIndex ? StudioTheme.success.opacity(0.7) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PlaybackPhase {
    let phraseIndex: Int
    let barIndex: Int
}
