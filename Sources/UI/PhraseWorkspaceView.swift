import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0

    private let phraseColumnWidth: CGFloat = 118
    private let trackColumnWidth: CGFloat = 126
    private let actionColumnWidth: CGFloat = 92
    private let gridSpacing: CGFloat = 10
    private let trackPageSize = 8

    private var phrases: [PhraseModel] { session.store.phrases }
    private var tracks: [StepSequenceTrack] { session.store.tracks }
    private var layers: [PhraseLayerDefinition] { session.store.layers }
    private var selectedPhrase: PhraseModel { session.store.selectedPhrase }
    private var selectedTrack: StepSequenceTrack { session.store.selectedTrack }

    private var selectedLayer: PhraseLayerDefinition {
        session.store.layer(id: selectedLayerID)
            ?? layers.first
            ?? PhraseLayerDefinition.defaultSet(for: tracks).first!
    }

    private var selectedLayerIndex: Int {
        layers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var trackPageCount: Int {
        max(1, Int(ceil(Double(tracks.count) / Double(trackPageSize))))
    }

    private var visibleTrackSlots: [StepSequenceTrack?] {
        let startIndex = min(trackPage * trackPageSize, tracks.count)
        let pagedTracks = Array(tracks.dropFirst(startIndex).prefix(trackPageSize))
        return pagedTracks.map(Optional.some) + Array(repeating: nil, count: max(0, trackPageSize - pagedTracks.count))
    }

    private var playbackPhraseIndex: Int? {
        guard engineController.isRunning, !phrases.isEmpty else {
            return nil
        }

        let totalBars = phrases.reduce(0) { $0 + max(1, $1.lengthBars) }
        guard totalBars > 0 else {
            return nil
        }

        let absoluteBar = Int(engineController.transportTickIndex) / max(1, selectedPhrase.stepsPerBar)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Phrase Matrix",
                eyebrow: "Project-scoped layers across the top, phrases down the rows, one cell per track and layer.",
                accent: layerAccent(selectedLayer.id)
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    layerBar
                    matrix
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .sheet(item: $editingCellTarget) { target in
            PhraseCellEditorSheet(
                target: target,
                accent: layerAccent(target.layerID)
            )
            .presentationBackground(.clear)
        }
        .onAppear {
            if session.store.layer(id: selectedLayerID) == nil {
                selectedLayerID = session.store.patternLayer?.id ?? layers.first?.id ?? "pattern"
            }
            clampTrackPage()
        }
        .onChange(of: session.store.selectedTrackID) {
            syncTrackPageToSelection()
        }
        .onChange(of: tracks.count) {
            clampTrackPage()
        }
        .onChange(of: phrases.map(\.id)) {
            dismissInvalidEditorTarget()
        }
        .onChange(of: tracks.map(\.id)) {
            dismissInvalidEditorTarget()
        }
        .onChange(of: layers.map(\.id)) {
            dismissInvalidEditorTarget()
        }
    }

    private var layerBar: some View {
        HStack(spacing: 12) {
            Button {
                cycleLayer(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(selectedLayer.name.uppercased())
                    .studioText(.bodyBold)
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)

                Rectangle()
                    .fill(layerAccent(selectedLayer.id))
                    .frame(width: 28, height: 3)
                    .clipShape(Capsule())

                Text(layerSubtitle(selectedLayer))
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(layerAccent(selectedLayer.id))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(layerAccent(selectedLayer.id).opacity(StudioOpacity.hoverFill), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(layerAccent(selectedLayer.id).opacity(StudioOpacity.subtleStroke), lineWidth: 1)
            )

            Button {
                cycleLayer(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .studioText(.chromeLabel)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                trackPageButton(systemImage: "chevron.left", action: { cycleTrackPage(by: -1) }, isEnabled: trackPage > 0)

                Text("Tracks \(trackPage + 1) / \(trackPageCount)")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())

                trackPageButton(systemImage: "chevron.right", action: { cycleTrackPage(by: 1) }, isEnabled: trackPage < trackPageCount - 1)
            }
        }
    }

    private func cycleLayer(by delta: Int) {
        guard !layers.isEmpty else {
            return
        }

        let nextIndex = (selectedLayerIndex + delta + layers.count) % layers.count
        selectedLayerID = layers[nextIndex].id
    }

    private func cycleTrackPage(by delta: Int) {
        trackPage = min(max(trackPage + delta, 0), trackPageCount - 1)
    }

    private func syncTrackPageToSelection() {
        guard let selectedIndex = tracks.firstIndex(where: { $0.id == session.store.selectedTrackID }) else {
            return
        }
        trackPage = min(max(selectedIndex / trackPageSize, 0), trackPageCount - 1)
    }

    private func clampTrackPage() {
        trackPage = min(max(trackPage, 0), trackPageCount - 1)
        syncTrackPageToSelection()
    }

    private func dismissInvalidEditorTarget() {
        guard let editingCellTarget else {
            return
        }

        let phraseExists = phrases.contains(where: { $0.id == editingCellTarget.phraseID })
        let trackExists = tracks.contains(where: { $0.id == editingCellTarget.trackID })
        let layerExists = layers.contains(where: { $0.id == editingCellTarget.layerID })

        if !(phraseExists && trackExists && layerExists) {
            self.editingCellTarget = nil
        }
    }

    private func handleSingleTap(on phraseID: UUID, trackID: UUID) {
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)

        if selectedLayer.valueType == .boolean {
            toggleBooleanCell(phraseID: phraseID, trackID: trackID)
        }
    }

    private func openCellEditor(phraseID: UUID, trackID: UUID) {
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)
        editingCellTarget = PhraseCellEditorTarget(
            phraseID: phraseID,
            trackID: trackID,
            layerID: selectedLayer.id
        )
    }

    @ViewBuilder
    private func trackPageButton(systemImage: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    Color.clear
                        .frame(width: phraseColumnWidth, height: 52)

                    ForEach(Array(visibleTrackSlots.enumerated()), id: \.offset) { _, track in
                        Group {
                            if let track {
                                Button {
                                    session.setSelectedTrackID(track.id)
                                } label: {
                                    PhraseMatrixTrackHeaderCell(
                                        track: track,
                                        isSelected: selectedTrack.id == track.id,
                                        accent: track.groupID == nil ? layerAccent(selectedLayer.id) : StudioTheme.success
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                PhraseMatrixEmptyTrackHeaderCell()
                            }
                        }
                        .frame(width: trackColumnWidth)
                    }

                    Color.clear
                        .frame(width: actionColumnWidth, height: 52)
                }

                let selectedPhraseID = session.store.selectedPhraseID
                let selectedTrackID = session.store.selectedTrackID
                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        PhraseMatrixPhraseCell(
                            phrase: phrase,
                            isSelected: selectedPhraseID == phrase.id,
                            isPlaying: playbackPhraseIndex == index
                        ) {
                            session.setSelectedPhraseID(phrase.id)
                        }
                        .frame(width: phraseColumnWidth)

                        ForEach(Array(visibleTrackSlots.enumerated()), id: \.offset) { _, track in
                            Group {
                                if let track {
                                    PhraseGridCell(
                                        layer: selectedLayer,
                                        cell: phrase.cell(for: selectedLayer.id, trackID: track.id),
                                        phrase: phrase,
                                        track: track,
                                        isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                        accent: layerAccent(selectedLayer.id)
                                    )
                                    .contentShape(Rectangle())
                                    .gesture(
                                        TapGesture(count: 2)
                                            .exclusively(before: TapGesture())
                                            .onEnded { value in
                                                switch value {
                                                case .first:
                                                    openCellEditor(phraseID: phrase.id, trackID: track.id)
                                                case .second:
                                                    handleSingleTap(on: phrase.id, trackID: track.id)
                                                }
                                            }
                                    )
                                } else {
                                    PhraseGridEmptyCell()
                                }
                            }
                            .frame(width: trackColumnWidth)
                        }

                        PhraseRowActions(
                            canRemove: phrases.count > 1,
                            onInsertBelow: {
                                session.insertPhrase(below: phrase.id)
                            },
                            onDuplicate: {
                                session.duplicatePhrase(id: phrase.id)
                            },
                            onRemove: {
                                session.removePhrase(id: phrase.id)
                            }
                        )
                        .frame(width: actionColumnWidth)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 280)
    }

    private func toggleBooleanCell(phraseID: UUID, trackID: UUID) {
        guard selectedLayer.valueType == .boolean else {
            assertionFailure("toggleBooleanCell called for non-boolean layer \(selectedLayer.id)")
            return
        }

        session.mutatePhrase(id: phraseID) { phrase in
            let currentCell = phrase.cell(for: selectedLayer.id, trackID: trackID)
            let resolvedValue = phrase.resolvedValue(for: selectedLayer, trackID: trackID, stepIndex: 0)
            let toggledValue = toggledBooleanValue(resolvedValue, for: selectedLayer)

            switch currentCell {
            case .inheritDefault, .curve:
                phrase.setCell(.single(toggledValue), for: selectedLayer.id, trackID: trackID)
            case .single:
                phrase.setCell(.single(toggledValue), for: selectedLayer.id, trackID: trackID)
            case let .bars(values):
                phrase.setCell(.bars(Array(repeating: toggledValue, count: values.count)), for: selectedLayer.id, trackID: trackID)
            case let .steps(values):
                phrase.setCell(.steps(Array(repeating: toggledValue, count: values.count)), for: selectedLayer.id, trackID: trackID)
            }
        }
    }
}

private struct PhraseRowActions: View {
    let canRemove: Bool
    let onInsertBelow: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            actionButton(systemImage: "plus", action: onInsertBelow)
            actionButton(systemImage: "plus.square.on.square", action: onDuplicate)
            actionButton(systemImage: "trash", action: onRemove, isDisabled: !canRemove)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void, isDisabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.accentFill) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct PhraseMatrixTrackHeaderCell: View {
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
            Text(track.trackType.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background((isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }
}

private struct PhraseMatrixEmptyTrackHeaderCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            .fill(Color.white.opacity(0.015))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
    }
}

private struct PhraseMatrixPhraseCell: View {
    let phrase: PhraseModel
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                Text(phrase.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)

                Text("\(phrase.lengthBars) bars")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)

                if isPlaying {
                    Text("Playing")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(StudioTheme.success)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((isSelected ? StudioTheme.violet.opacity(StudioOpacity.faintStroke) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke((isPlaying ? StudioTheme.success : StudioTheme.violet).opacity(isSelected || isPlaying ? 0.6 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PhraseGridCell: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cell.editMode.label.uppercased())
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
            }

            PhraseCellPreview(
                layer: layer,
                cell: cell,
                resolvedValue: phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0),
                accent: accent,
                summary: valueLabel(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0), layer: layer),
                metrics: .matrix
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }
}

private struct PhraseGridEmptyCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            .fill(Color.white.opacity(0.015))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
    }
}
