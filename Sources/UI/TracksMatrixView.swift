import SwiftUI

enum TracksWorkspaceMode: String, CaseIterable, Identifiable {
    case edit
    case perform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit:
            return "Edit"
        case .perform:
            return "Perform"
        }
    }
}

struct TracksWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var mode: TracksWorkspaceMode
    @Binding var selectedLayerID: String
    let onOpenTrack: () -> Void

    var body: some View {
        TracksMatrixView(
            document: $document,
            selectedLayerID: $selectedLayerID,
            isPerforming: mode == .perform,
            onTogglePerform: {
                mode = mode == .perform ? .edit : .perform
            },
            onOpenTrack: onOpenTrack
        )
        .padding(20)
    }
}

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let isPerforming: Bool
    let onTogglePerform: () -> Void
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var isPresentingAddSliceTrack = false
    @State private var isPresentingAddDrumGroup = false

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 112, maximum: 190), spacing: 12),
        count: 8
    )

    private var selectedLayer: PhraseLayerDefinition {
        let layers = session.store.layers
        return session.store.layer(id: selectedLayerID)
            ?? session.store.patternLayer
            ?? layers.first!
    }

    private var layers: [PhraseLayerDefinition] {
        session.store.layers
    }

    private var selectedLayerIndex: Int {
        layers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var editingPhrase: PhraseModel {
        let phrases = session.store.phrases
        return phrases.first(where: { $0.id == editingPhraseID }) ?? session.store.selectedPhrase
    }

    private var editingPhraseID: UUID {
        guard engineController.transportMode == .song,
              engineController.isRunning,
              let playbackPhraseIndex
        else {
            return session.store.selectedPhraseID
        }

        let phrases = session.store.phrases
        return phrases[playbackPhraseIndex].id
    }

    private var playbackPhraseIndex: Int? {
        let phrases = session.store.phrases
        guard engineController.isRunning, !phrases.isEmpty else {
            return nil
        }

        let totalBars = phrases.reduce(0) { $0 + max(1, $1.lengthBars) }
        guard totalBars > 0 else {
            return nil
        }

        let absoluteBar = Int(engineController.transportTickIndex) / max(1, session.store.selectedPhrase.stepsPerBar)
        var cycleBar = absoluteBar % totalBars

        for (index, phrase) in phrases.enumerated() {
            let phraseBars = max(1, phrase.lengthBars)
            if cycleBar < phraseBars {
                return index
            }
            cycleBar -= phraseBars
        }

        return nil
    }

    private var groupedSections: [GroupedTrackSection] {
        session.store.trackGroups.compactMap { group in
            let members = session.store.tracksInGroup(group.id)
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        session.store.tracks.filter { $0.groupID == nil }
    }

    var body: some View {
        let tracks = session.store.tracks
        let selectedTrackID = session.store.selectedTrackID
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: isPerforming ? StudioTheme.amber : StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    actionBar

                    if tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            detail: "Create a mono, poly, slice, or drum-kit bundle to start building the matrix.",
                            accent: StudioTheme.cyan
                        )
                    } else {
                        matrixSections(tracks: tracks, selectedTrackID: selectedTrackID)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(document: $document, onOpenTrack: onOpenTrack)
        }
        .sheet(isPresented: $isPresentingAddSliceTrack) {
            AddSliceTrackSheet(
                library: .shared,
                sampleEngine: engineController.sampleEngineSink,
                onCreate: { sample in
                    _ = session.appendSliceTrack(sample: sample)
                    isPresentingAddSliceTrack = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddSliceTrack = false
                }
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $isPresentingAddDrumGroup) {
            AddDrumGroupSheet(
                auInstruments: engineController.availableAudioInstruments,
                onCreate: { plan in
                    _ = session.addDrumGroup(plan: plan)
                    isPresentingAddDrumGroup = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddDrumGroup = false
                }
            )
            .presentationBackground(.clear)
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                createTrackButtons
                Spacer()
                layerControl
                basisPhrasePill
                performToggleButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    createTrackButtons
                }
                HStack(spacing: 10) {
                    layerControl
                    basisPhrasePill
                    performToggleButton
                    Spacer()
                }
            }
        }
    }

    private var createTrackButtons: some View {
        Group {
            Button("Add Mono") {
                session.appendTrack(trackType: .monoMelodic)
                onOpenTrack()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Add Poly") {
                session.appendTrack(trackType: .polyMelodic)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Button("New Slice Track") {
                isPresentingAddSliceTrack = true
            }
            .buttonStyle(.bordered)

            Button("Add Drum Group") {
                isPresentingAddDrumGroup = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var layerControl: some View {
        HStack(spacing: 8) {
            Button {
                cycleLayer(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(selectedLayer.name.uppercased())
                        .studioText(.labelBold)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)

                    Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                        .studioText(.micro)
                        .foregroundStyle(layerAccent(selectedLayer.id))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(layerAccent(selectedLayer.id).opacity(StudioOpacity.hoverFill), in: Capsule())
                }

                Text(layerSubtitle(selectedLayer))
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            Button {
                cycleLayer(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(layerAccent(selectedLayer.id).opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
    }

    private var basisPhrasePill: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("BASIS PHRASE")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Text(editingPhrase.name)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.violet)
                .lineLimit(1)
        }
        .frame(width: 130, alignment: .trailing)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(StudioTheme.violet.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    private var performToggleButton: some View {
        Button(action: onTogglePerform) {
            Label("Perform", systemImage: isPerforming ? "record.circle.fill" : "record.circle")
                .studioText(.labelBold)
                .frame(minWidth: 96)
        }
        .buttonStyle(.borderedProminent)
        .tint(isPerforming ? StudioTheme.amber : StudioTheme.cyan)
    }

    private func cycleLayer(by delta: Int) {
        guard !layers.isEmpty else {
            return
        }

        let nextIndex = (selectedLayerIndex + delta + layers.count) % layers.count
        selectedLayerID = layers[nextIndex].id
    }

    private func matrixSections(tracks: [StepSequenceTrack], selectedTrackID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !ungroupedTracks.isEmpty {
                tracksGrid(ungroupedTracks, group: nil, selectedTrackID: selectedTrackID)
            }

            ForEach(groupedSections) { section in
                GroupSectionView(
                    section: section,
                    grid: { tracksGrid(section.members, group: section.group, selectedTrackID: selectedTrackID) }
                )
            }
        }
    }

    @ViewBuilder
    private func tracksGrid(_ tracks: [StepSequenceTrack], group: TrackGroup?, selectedTrackID: UUID) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                let cell = editableCell(for: track.id)
                let resolvedValue = editingPhrase.resolvedValue(
                    for: selectedLayer,
                    trackID: track.id,
                    stepIndex: currentStepIndexInPhrase
                )
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: session.store.selectedPatternIndex(for: track.id),
                    layer: selectedLayer,
                    cell: cell,
                    resolvedValue: resolvedValue,
                    valueSummary: valueLabel(resolvedValue, layer: selectedLayer),
                    isSelected: track.id == selectedTrackID,
                    isPerforming: isPerforming
                ) {
                    session.setSelectedTrackID(track.id)
                    if isPerforming {
                        performPrimaryAction(trackID: track.id)
                    } else {
                        onOpenTrack()
                    }
                }
            }
        }
    }

    private var currentStepIndexInPhrase: Int {
        let stepCount = max(1, editingPhrase.stepCount)
        return Int(engineController.transportTickIndex) % stepCount
    }

    private var currentBarIndexInPhrase: Int {
        min(max(0, currentStepIndexInPhrase / max(1, editingPhrase.stepsPerBar)), max(editingPhrase.lengthBars - 1, 0))
    }

    private func performPrimaryAction(trackID: UUID) {
        let cell = editableCell(for: trackID)

        switch cell {
        case .inheritDefault:
            let seedValue = editingPhrase.resolvedValue(
                for: selectedLayer,
                trackID: trackID,
                stepIndex: currentStepIndexInPhrase
            )
            session.setPhraseCell(
                .single(cycledValue(seedValue, for: selectedLayer)),
                layerID: selectedLayer.id,
                trackIDs: [trackID],
                phraseID: editingPhraseID
            )
        case let .single(value):
            session.setPhraseCell(
                .single(cycledValue(value, for: selectedLayer)),
                layerID: selectedLayer.id,
                trackIDs: [trackID],
                phraseID: editingPhraseID
            )
        case let .bars(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentBarIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: selectedLayer)
            session.setPhraseCell(
                .bars(nextValues),
                layerID: selectedLayer.id,
                trackIDs: [trackID],
                phraseID: editingPhraseID
            )
        case let .steps(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentStepIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: selectedLayer)
            session.setPhraseCell(
                .steps(nextValues),
                layerID: selectedLayer.id,
                trackIDs: [trackID],
                phraseID: editingPhraseID
            )
        case .curve:
            let seedValue = editingPhrase.resolvedValue(
                for: selectedLayer,
                trackID: trackID,
                stepIndex: currentStepIndexInPhrase
            )
            session.setPhraseCell(
                .single(cycledValue(seedValue, for: selectedLayer)),
                layerID: selectedLayer.id,
                trackIDs: [trackID],
                phraseID: editingPhraseID
            )
        }
    }

    private func editableCell(for trackID: UUID) -> PhraseCell {
        editingPhrase.cell(for: selectedLayer.id, trackID: trackID)
    }

}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

private struct GroupSectionView<Grid: View>: View {
    let section: GroupedTrackSection
    @ViewBuilder let grid: Grid

    private var accent: Color {
        Color(hex: section.group.color) ?? StudioTheme.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(section.group.name)
                            .studioText(.title)
                            .foregroundStyle(StudioTheme.text)

                        Text("\(section.members.count) tracks")
                            .studioText(.eyebrowBold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                            .foregroundStyle(accent)
                    }

                    Text(section.group.sharedDestination?.summary ?? "Shared destination not assigned")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            grid
        }
        .padding(16)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
        )
    }
}

private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
    let patternIndex: Int
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let resolvedValue: PhraseCellValue
    let valueSummary: String
    let isSelected: Bool
    let isPerforming: Bool
    let onTap: () -> Void

    private var accent: Color {
        if let group {
            return Color(hex: group.color) ?? StudioTheme.cyan
        }
        switch track.trackType {
        case .monoMelodic:
            return StudioTheme.cyan
        case .polyMelodic:
            return StudioTheme.amber
        case .slice:
            return StudioTheme.violet
        }
    }

    private var typeLabel: String {
        track.trackType.label.uppercased()
    }

    private var destinationLabel: String {
        if case .inheritGroup = track.destination {
            return group?.sharedDestination?.kindLabel ?? "GROUP"
        }
        return track.destination.kindLabel
    }

    private var pitchOffsetLabel: String? {
        guard let group, let offset = group.noteMapping[track.id], offset != 0 else {
            return nil
        }
        return offset > 0 ? "+\(offset)" : "\(offset)"
    }

    private var layerAccentColor: Color {
        layerAccent(layer.id)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TrackTypeBadge(trackType: track.trackType, accent: accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 6) {
                            Text(typeLabel)
                            Text("P\(patternIndex + 1)")
                            Text(destinationLabel)
                            if let pitchOffsetLabel {
                                Text(pitchOffsetLabel)
                            }
                        }
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 0)
                }

                if let group {
                    Text(group.name.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(StudioOpacity.faintStroke), in: Capsule())
                        .lineLimit(1)
                } else {
                    Text(track.defaultDestination.summary)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(cell.editMode.label.uppercased())
                            .studioText(.micro)
                            .tracking(0.8)
                            .foregroundStyle(layerAccentColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if isPerforming {
                            Text("LIVE")
                                .studioText(.micro)
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
                        }
                    }

                    PhraseCellPreview(
                        layer: layer,
                        cell: cell,
                        resolvedValue: resolvedValue,
                        accent: layerAccentColor,
                        summary: valueSummary,
                        metrics: .matrix
                    )
                    .opacity(isPerforming ? 1 : 0.82)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(isSelected ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(
                        isPerforming
                            ? layerAccentColor.opacity(StudioOpacity.accentFill)
                            : (isSelected ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border),
                        lineWidth: isSelected || isPerforming ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TrackTypeBadge: View {
    let trackType: TrackType
    let accent: Color

    private var icon: String {
        switch trackType {
        case .monoMelodic:
            return "waveform.path"
        case .polyMelodic:
            return "pianokeys"
        case .slice:
            return "waveform"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(StudioTheme.text)
            .frame(width: 30, height: 30)
            .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SequencerDocumentSession.self) private var session
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Track")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text("Choose the kind of track to append to the matrix. You can rename and edit the destination in the Track workspace right after creation.")
                .studioText(.subtitleMuted)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 12) {
                createButton(title: "Mono", detail: "Single melodic lane", type: .monoMelodic, accent: StudioTheme.cyan)
                createButton(title: "Poly", detail: "Chord-capable lane", type: .polyMelodic, accent: StudioTheme.amber)
                createButton(title: "Slice", detail: "Sample/slice trigger lane", type: .slice, accent: StudioTheme.violet)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
        .background(StudioTheme.chrome)
    }

    private func createButton(title: String, detail: String, type: TrackType, accent: Color) -> some View {
        Button {
            session.appendTrack(trackType: type)
            dismiss()
            onOpenTrack()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .studioText(.title)
                    .foregroundStyle(StudioTheme.text)
                Text(detail)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(16)
            .background(accent.opacity(StudioOpacity.mutedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AddSliceTrackSheet: View {
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink
    let onCreate: (AudioSample) -> Void
    let onCancel: () -> Void

    @State private var previewingSampleID: UUID?

    private var samples: [AudioSample] {
        library.samples(in: .breaks).sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)]
    }

    private var breaksFolderPath: String {
        library.libraryRoot.appendingPathComponent("breaks", isDirectory: true).path
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            StudioTheme.stageFill
                .ignoresSafeArea()

            StudioPanel(title: "New Slice Track", eyebrow: "Choose a loop. Slices are detected after the track opens.", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 16) {
                    if samples.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Break Loops Found",
                            detail: "Add WAV loops to \(breaksFolderPath).",
                            accent: StudioTheme.violet
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(samples) { sample in
                                    sampleCard(sample)
                                }
                            }
                        }
                        .frame(maxHeight: 440)
                    }
                }
            }
            .padding(24)
            .frame(minWidth: 760, minHeight: 520)

            Button {
                sampleEngine.stopAudition()
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(30)
        }
        .onDisappear {
            sampleEngine.stopAudition()
        }
        .onAppear {
            library.reload()
        }
    }

    private func sampleCard(_ sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(sample.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(sampleDetail(sample))
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    togglePreview(sample)
                } label: {
                    Image(systemName: previewingSampleID == sample.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 28, height: 28)
                        .background(StudioTheme.violet.opacity(StudioOpacity.selectedFill), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(previewingSampleID == sample.id ? "Stop preview" : "Preview loop")
            }

            Button {
                sampleEngine.stopAudition()
                onCreate(sample)
            } label: {
                Text("Use Loop")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.violet.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                            .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
        )
    }

    private func togglePreview(_ sample: AudioSample) {
        if previewingSampleID == sample.id {
            sampleEngine.stopAudition()
            previewingSampleID = nil
            return
        }

        guard let url = try? sample.fileRef.resolve(libraryRoot: library.libraryRoot) else {
            return
        }

        sampleEngine.stopAudition()
        sampleEngine.audition(sampleURL: url)
        previewingSampleID = sample.id
    }

    private func sampleDetail(_ sample: AudioSample) -> String {
        let length = sample.lengthSeconds.map { String(format: "%.2fs", $0) } ?? "--"
        let rate = sample.sampleRate.map { String(format: "%.1fk", $0 / 1_000) } ?? "--"
        return "\(sample.category.displayName) • \(length) • \(rate)"
    }

}

private extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}
