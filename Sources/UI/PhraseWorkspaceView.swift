import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding private var visualControlsOpenIndex: Int?
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0
    @State private var phraseControlsState = PhraseButtonControlsState()

    private let phraseColumnWidth: CGFloat = 118
    private let trackColumnWidth: CGFloat = 126
    private let actionColumnWidth: CGFloat = 92
    private let matrixGutterWidth = PhraseMatrixLayoutPresentation.matrixGutterWidth
    private let gridSpacing: CGFloat = 10
    private let trackPageSize = PhraseMatrixLayoutPresentation.trackPageSize

    init(
        document: Binding<SeqAIDocument>,
        visualControlsOpenIndex: Binding<Int?> = .constant(nil)
    ) {
        self._document = document
        self._visualControlsOpenIndex = visualControlsOpenIndex
    }

    private var phrases: [PhraseModel] { session.store.phrases }
    private var tracks: [StepSequenceTrack] { session.store.tracks }
    private var layers: [PhraseLayerDefinition] { session.store.layers }
    private var matrixSelectableLayers: [PhraseLayerDefinition] {
        let selectableLayers = PhraseLayerSelectorPresentation.selectableLayers(from: layers)
        return selectableLayers.isEmpty ? layers : selectableLayers
    }
    private var selectedTrack: StepSequenceTrack { session.store.selectedTrack }

    private var selectedLayer: PhraseLayerDefinition {
        matrixSelectableLayers.first { $0.id == selectedLayerID }
            ?? matrixSelectableLayers.first
            ?? PhraseLayerDefinition.defaultSet(for: tracks).first!
    }

    private var selectedLayerIndex: Int {
        matrixSelectableLayers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var trackPageCount: Int {
        matrixLayout.pageCount
    }

    private var matrixLayout: PhraseMatrixLayoutPresentation {
        PhraseMatrixLayoutPresentation(trackCount: tracks.count, pageIndex: trackPage)
    }

    private var trackGridWidth: CGFloat {
        let columnCount = CGFloat(trackPageSize)
        return columnCount * trackColumnWidth + max(0, columnCount - 1) * gridSpacing
    }

    private var visibleTrackSlots: [StepSequenceTrack?] {
        let startIndex = min(trackPage * trackPageSize, tracks.count)
        let pagedTracks = Array(tracks.dropFirst(startIndex).prefix(trackPageSize))
        return pagedTracks.map(Optional.some) + Array(repeating: nil, count: max(0, trackPageSize - pagedTracks.count))
    }

    private var phraseControlsPanelWidth: CGFloat {
        let trackSlotsWidth = CGFloat(visibleTrackSlots.count) * trackColumnWidth
        let interiorSpacing = CGFloat(trackPageSize + 2) * gridSpacing
        return phraseColumnWidth + (matrixGutterWidth * 2) + interiorSpacing + trackSlotsWidth
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
            reconcileSelectedLayer()
            clampTrackPage()
            applyVisualControlsOpenIndex()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onDisappear {
            postRenderedMatrixVisualState(isVisible: false)
        }
        .onChange(of: visualControlsOpenIndex) {
            applyVisualControlsOpenIndex()
        }
        .onChange(of: session.store.selectedTrackID) {
            syncTrackPageToSelection()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: tracks.count) {
            clampTrackPage()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: trackPage) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: phrases.map(\.id)) {
            dismissInvalidEditorTarget()
            phraseControlsState.reconcile(availablePhraseIDs: phrases.map(\.id))
            applyVisualControlsOpenIndex()
        }
        .onChange(of: tracks.map(\.id)) {
            dismissInvalidEditorTarget()
        }
        .onChange(of: layers.map(\.id)) {
            dismissInvalidEditorTarget()
            reconcileSelectedLayer()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: selectedLayerID) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phraseMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyMatrixVisualCommand(command)
        }
    }

    private func reconcileSelectedLayer() {
        if matrixSelectableLayers.contains(where: { $0.id == selectedLayerID }) {
            return
        }
        selectedLayerID = matrixSelectableLayers.first?.id ?? session.store.patternLayer?.id ?? layers.first?.id ?? "pattern"
    }

    private func applyVisualControlsOpenIndex() {
        guard let visualControlsOpenIndex else {
            return
        }

        guard phrases.indices.contains(visualControlsOpenIndex) else {
            phraseControlsState.close()
            return
        }

        let phraseID = phrases[visualControlsOpenIndex].id
        session.setSelectedPhraseID(phraseID)
        phraseControlsState.openControls(for: phraseID)
    }

    private var layerBar: some View {
        HStack(spacing: gridSpacing) {
            Color.clear
                .frame(width: phraseColumnWidth, height: 44)

            Color.clear
                .frame(width: matrixGutterWidth, height: 44)

            layerSelectorRegion
                .frame(width: trackGridWidth, height: 44)

            Color.clear
                .frame(width: matrixGutterWidth, height: 44)

            Color.clear
                .frame(width: actionColumnWidth, height: 44)
        }
    }

    private var layerSelectorRegion: some View {
        let presentation = PhraseLayerSelectorPresentation(
            layerName: PhraseLayerSelectorPresentation.displayName(for: selectedLayer),
            subtitle: layerSubtitle(selectedLayer),
            indexLabel: "\(selectedLayerIndex + 1) / \(max(matrixSelectableLayers.count, 1))"
        )

        return HStack(spacing: 8) {
            layerCycleButton(systemImage: "chevron.left", action: { cycleLayer(by: -1) })

            HStack(spacing: 8) {
                Text(presentation.displayName)
                    .studioText(.bodyBold)
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(PhraseLayerSelectorPresentation.lineLimit)
                    .truncationMode(.tail)
                    .help(presentation.layerName)
                    .layoutPriority(1)

                Rectangle()
                    .fill(layerAccent(selectedLayer.id))
                    .frame(width: 24, height: 3)
                    .clipShape(Capsule())

                Text(presentation.indexLabel)
                    .studioText(.eyebrowBold)
                    .foregroundStyle(layerAccent(selectedLayer.id))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(layerAccent(selectedLayer.id).opacity(StudioOpacity.hoverFill), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(presentation.accessibilityLabel)

            layerCycleButton(systemImage: "chevron.right", action: { cycleLayer(by: 1) })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: PhraseLayerSelectorPresentation.fixedOuterWidth)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(layerAccent(selectedLayer.id).opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
        .accessibilityIdentifier("phrase-layer-selector")
    }

    private func cycleLayer(by delta: Int) {
        guard !layers.isEmpty else {
            return
        }

        let selectableLayers = matrixSelectableLayers
        guard !selectableLayers.isEmpty else {
            return
        }

        let nextIndex = (selectedLayerIndex + delta + selectableLayers.count) % selectableLayers.count
        selectedLayerID = selectableLayers[nextIndex].id
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
    }

    private func applyMatrixVisualCommand(_ command: String) {
        if command.hasPrefix("page-index:"),
           let rawPageIndex = command.split(separator: ":").last,
           let pageIndex = Int(rawPageIndex) {
            trackPage = min(max(pageIndex, 0), trackPageCount - 1)
            return
        }

        if command.hasPrefix("layer-id:") {
            let layerID = String(command.dropFirst("layer-id:".count))
            if matrixSelectableLayers.contains(where: { $0.id == layerID }) {
                selectedLayerID = layerID
            }
            return
        }

        if command.hasPrefix("layer-index:"),
           let rawIndex = command.split(separator: ":").last,
           let index = Int(rawIndex),
           matrixSelectableLayers.indices.contains(index) {
            selectedLayerID = matrixSelectableLayers[index].id
        }
    }

    private func postRenderedMatrixVisualState(isVisible: Bool) {
        let layout = matrixLayout
        NotificationCenter.default.post(
            name: .phraseMatrixRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "pageIndex": isVisible ? layout.pageIndex : 0,
                "pageCount": isVisible ? layout.pageCount : 0,
                "trackCount": isVisible ? tracks.count : 0,
                "previousEnabled": isVisible && layout.arrow(for: .previous).isEnabled,
                "nextEnabled": isVisible && layout.arrow(for: .next).isEnabled,
                "previousOccupancy": isVisible ? layout.arrow(for: .previous).adjacentTrackCount : 0,
                "nextOccupancy": isVisible ? layout.arrow(for: .next).adjacentTrackCount : 0,
                "selectedLayerID": isVisible ? selectedLayer.id : "none",
                "selectedLayerName": isVisible ? PhraseLayerSelectorPresentation.displayName(for: selectedLayer) : "none",
                "selectorWidth": isVisible ? PhraseLayerSelectorPresentation.fixedOuterWidth : 0,
                "trackGridWidth": isVisible ? trackGridWidth : 0,
            ]
        )
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

    private func layerCycleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func trackPageArrow(_ direction: PhraseMatrixPageDirection) -> some View {
        let presentation = matrixLayout.arrow(for: direction)
        let systemImage = direction == .previous ? "chevron.left" : "chevron.right"

        return Button {
            cycleTrackPage(by: direction == .previous ? -1 : 1)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(Color.white.opacity(presentation.isEnabled ? StudioOpacity.subtleFill : 0.015))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(StudioTheme.border.opacity(presentation.isEnabled ? StudioOpacity.mediumStroke : StudioOpacity.ghostStroke), lineWidth: 1)
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(presentation.isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let occupancyHint = presentation.occupancyHint {
                    Text(occupancyHint)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 15, height: 15)
                        .background(layerAccent(selectedLayer.id), in: Circle())
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isEnabled)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(direction == .previous ? "phrase-matrix-page-previous" : "phrase-matrix-page-next")
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    Color.clear
                        .frame(width: phraseColumnWidth, height: 52)

                    trackPageArrow(.previous)
                        .frame(width: matrixGutterWidth, height: 52)

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

                    trackPageArrow(.next)
                        .frame(width: matrixGutterWidth, height: 52)

                    Color.clear
                        .frame(width: actionColumnWidth, height: 52)
                }

                let selectedPhraseID = session.store.selectedPhraseID
                let selectedTrackID = session.store.selectedTrackID
                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: gridSpacing) {
                            let isOpen = phraseControlsState.openPhraseID == phrase.id
                            PhraseMatrixPhraseCell(
                                phrase: phrase,
                                isSelected: selectedPhraseID == phrase.id,
                                isPlaying: PhraseButtonControlPresentation.isPlayingBadgeVisible(
                                    phraseID: phrase.id,
                                    engineIsRunning: engineController.isRunning,
                                    currentPhraseID: engineController.currentPhraseID
                                ),
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                isOpen: isOpen
                            ) {
                                session.setSelectedPhraseID(phrase.id)
                                phraseControlsState.toggleControls(for: phrase.id)
                            }
                            .frame(width: phraseColumnWidth)

                            PhraseMatrixGutterCell()
                                .frame(width: matrixGutterWidth)

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

                            PhraseMatrixGutterCell()
                                .frame(width: matrixGutterWidth)

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

                        if phraseControlsState.openPhraseID == phrase.id {
                            PhraseButtonControlsPanel(
                                phrase: phrase,
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                stepOrderMaps: session.store.stepOrderMaps,
                                stepOrderToggleState: session.stepOrderToggleState(phraseID: phrase.id),
                                stepOrderDeletionStatus: { mapID in
                                    session.stepOrderMapDeletionStatus(id: mapID)
                                },
                                onChangeBarCount: { nextBarCount in
                                    session.setPhraseBarCount(nextBarCount, phraseID: phrase.id)
                                },
                                onChangeRepeatCount: { nextRepeatCount in
                                    session.setPhraseRepeatCount(nextRepeatCount, phraseID: phrase.id)
                                },
                                onToggleLoop: {
                                    session.setPhraseLoopEnabled(!phrase.loopEnabled, phraseID: phrase.id)
                                },
                                onCreateStepOrderMap: { name in
                                    let map = StepOrderMap(name: name)
                                    guard session.appendStepOrderMap(map) else {
                                        return nil
                                    }
                                    let enabled = phrase.stepOrderAssignment?.isEnabled ?? false
                                    session.setStepOrderAssignment(phraseID: phrase.id, mapID: map.id, isEnabled: enabled)
                                    return map.id
                                },
                                onRenameStepOrderMap: { mapID, name in
                                    session.renameStepOrderMap(id: mapID, name: name)
                                },
                                onSetStepOrderMapValues: { mapID, values in
                                    session.setStepOrderMapValues(id: mapID, values: values)
                                },
                                onAssignStepOrderMap: { mapID in
                                    let enabled = phrase.stepOrderAssignment?.isEnabled ?? false
                                    session.setStepOrderAssignment(phraseID: phrase.id, mapID: mapID, isEnabled: enabled)
                                },
                                onDeleteStepOrderMap: { mapID in
                                    session.deleteUnusedStepOrderMap(id: mapID)
                                },
                                onRequestStepOrderEnabled: { enabled in
                                    session.requestPhraseStepOrderEnabled(enabled, phraseID: phrase.id)
                                }
                            )
                            .frame(width: phraseControlsPanelWidth, alignment: .leading)
                        }
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

private struct PhraseMatrixGutterCell: View {
    var body: some View {
        Color.clear
            .accessibilityHidden(true)
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
    let isQueued: Bool
    let isOpen: Bool
    let onSelect: () -> Void

    private var presentation: PhraseButtonControlPresentation {
        PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: isSelected,
            isPlaying: isPlaying,
            isQueued: isQueued,
            isOpen: isOpen
        )
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phrase.name)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(phrase.name)
                        .layoutPriority(1)

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Text(presentation.collapsedSummary)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    if isSelected {
                        phraseBadge("Sel", accent: StudioTheme.violet)
                    }
                    if isPlaying {
                        phraseBadge("Play", accent: StudioTheme.success)
                    }
                    if isQueued {
                        phraseBadge("Queue", accent: StudioTheme.amber)
                    }
                    if phrase.loopEnabled {
                        phraseBadge("Loop", accent: StudioTheme.amber)
                    }
                }
                .frame(minHeight: 18, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
            .padding(10)
            .background(rowFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(rowStroke, lineWidth: isOpen ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint("Select phrase and toggle inline controls")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("phrase-button-\(phrase.id.uuidString)")
    }

    private var rowFill: Color {
        if phrase.loopEnabled {
            return StudioTheme.amber.opacity(isSelected ? StudioOpacity.selectedFill : StudioOpacity.subtleFill)
        }
        if isSelected || isOpen {
            return StudioTheme.violet.opacity(StudioOpacity.faintStroke)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var rowStroke: Color {
        if isPlaying {
            return StudioTheme.success.opacity(0.7)
        }
        if isQueued || phrase.loopEnabled {
            return StudioTheme.amber.opacity(StudioOpacity.mediumStroke)
        }
        return StudioTheme.violet.opacity(isSelected || isOpen ? 0.6 : 0.12)
    }

    private func phraseBadge(_ label: String, accent: Color) -> some View {
        Text(label.uppercased())
            .studioText(.microEmphasis)
            .lineLimit(1)
            .foregroundStyle(accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(accent.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
    }
}

private struct PhraseButtonControlsPanel: View {
    let phrase: PhraseModel
    let isQueued: Bool
    let stepOrderMaps: [StepOrderMap]
    let stepOrderToggleState: StepOrderToggleState
    let stepOrderDeletionStatus: (StepOrderMapID) -> StepOrderMapDeletionStatus
    let onChangeBarCount: (Int) -> Void
    let onChangeRepeatCount: (Int) -> Void
    let onToggleLoop: () -> Void
    let onCreateStepOrderMap: (String) -> StepOrderMapID?
    let onRenameStepOrderMap: (StepOrderMapID, String) -> Void
    let onSetStepOrderMapValues: (StepOrderMapID, [UInt8]) -> Void
    let onAssignStepOrderMap: (StepOrderMapID?) -> Void
    let onDeleteStepOrderMap: (StepOrderMapID) -> Void
    let onRequestStepOrderEnabled: (Bool) -> Void

    private var presentation: PhraseButtonControlPresentation {
        PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: false,
            isPlaying: false,
            isQueued: isQueued,
            isOpen: true
        )
    }

    private var stepOrderPresentation: StepOrderPhraseSurfacePresentation {
        StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: stepOrderMaps,
            toggleState: stepOrderToggleState
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(phrase.name)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(phrase.name)

                    Text(presentation.effectivePlaybackSummary)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 360, alignment: .leading)

                PhrasePolicyStepperControl(
                    title: "Bars",
                    valueLabel: presentation.barCountSummary,
                    decrementDisabled: phrase.lengthBars <= PhraseModel.lengthBarsRange.lowerBound,
                    incrementDisabled: phrase.lengthBars >= PhraseModel.lengthBarsRange.upperBound,
                    onDecrement: {
                        onChangeBarCount(PhraseModel.clampedLengthBars(phrase.lengthBars - 1))
                    },
                    onIncrement: {
                        onChangeBarCount(PhraseModel.clampedLengthBars(phrase.lengthBars + 1))
                    }
                )

                PhrasePolicyStepperControl(
                    title: "Repeat",
                    valueLabel: presentation.repeatValueLabel,
                    footnote: "0 is unlimited",
                    decrementDisabled: phrase.repeatCount <= PhraseModel.repeatCountRange.lowerBound,
                    incrementDisabled: phrase.repeatCount >= PhraseModel.repeatCountRange.upperBound,
                    onDecrement: {
                        onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount - 1))
                    },
                    onIncrement: {
                        onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount + 1))
                    }
                )

                Button(action: onToggleLoop) {
                    HStack(spacing: 8) {
                        Image(systemName: phrase.loopEnabled ? "repeat.circle.fill" : "repeat.circle")
                            .font(.system(size: 15, weight: .bold))
                        Text(presentation.loopStatusLabel)
                            .studioText(.labelBold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(phrase.loopEnabled ? StudioTheme.text : StudioTheme.mutedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 126)
                    .background(loopFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(loopStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(phrase.loopEnabled ? "Loop overrides repeat during playback and keeps the stored repeat count" : "Enable permanent loop for this phrase")
                .accessibilityLabel("\(phrase.name) \(presentation.loopStatusLabel)")
            }

            StepOrderPhraseWorkflowPanel(
                phrase: phrase,
                maps: stepOrderMaps,
                presentation: stepOrderPresentation,
                deletionStatus: stepOrderDeletionStatus,
                onCreateMap: onCreateStepOrderMap,
                onRenameMap: onRenameStepOrderMap,
                onSetMapValues: onSetStepOrderMapValues,
                onAssignMap: onAssignStepOrderMap,
                onDeleteMap: onDeleteStepOrderMap,
                onRequestEnabled: onRequestStepOrderEnabled
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke((phrase.loopEnabled ? StudioTheme.amber : StudioTheme.violet).opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("phrase-button-controls-\(phrase.id.uuidString)")
    }

    private var loopFill: Color {
        phrase.loopEnabled ? StudioTheme.amber.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var loopStroke: Color {
        phrase.loopEnabled ? StudioTheme.amber.opacity(0.7) : StudioTheme.border
    }
}

private struct PhrasePolicyStepperControl: View {
    let title: String
    let valueLabel: String
    var footnote: String? = nil
    let decrementDisabled: Bool
    let incrementDisabled: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .studioText(.microEmphasis)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 0) {
                stepButton(systemName: "minus", action: onDecrement, isDisabled: decrementDisabled)

                Text(valueLabel)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 86, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill))

                stepButton(systemName: "plus", action: onIncrement, isDisabled: incrementDisabled)
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(width: 142, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(valueLabel)")
    }

    private func stepButton(systemName: String, action: @escaping () -> Void, isDisabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke) : StudioTheme.text)
                .frame(width: 28, height: 30)
                .background(Color.white.opacity(isDisabled ? 0.015 : StudioOpacity.subtleFill))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct StepOrderPhraseWorkflowPanel: View {
    let phrase: PhraseModel
    let maps: [StepOrderMap]
    let presentation: StepOrderPhraseSurfacePresentation
    let deletionStatus: (StepOrderMapID) -> StepOrderMapDeletionStatus
    let onCreateMap: (String) -> StepOrderMapID?
    let onRenameMap: (StepOrderMapID, String) -> Void
    let onSetMapValues: (StepOrderMapID, [UInt8]) -> Void
    let onAssignMap: (StepOrderMapID?) -> Void
    let onDeleteMap: (StepOrderMapID) -> Void
    let onRequestEnabled: (Bool) -> Void

    @State private var editorMapID: StepOrderMapID?
    @State private var selectedOutputIndex = 0
    @State private var draftMapName = ""
    @State private var wrapFeedbackVisible = false

    private var rows: [StepOrderMapRowPresentation] {
        maps.map { map in
            StepOrderMapRowPresentation(
                map: map,
                deletionStatus: deletionStatus(map.id),
                currentPhraseAssignment: phrase.stepOrderAssignment
            )
        }
    }

    private var resolvedEditorMapID: StepOrderMapID? {
        if let editorMapID, maps.contains(where: { $0.id == editorMapID }) {
            return editorMapID
        }
        return presentation.editorMapID
    }

    private var editorMap: StepOrderMap? {
        guard let resolvedEditorMapID else { return nil }
        return maps.first { $0.id == resolvedEditorMapID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 14) {
                mapPicker
                    .frame(width: 260, alignment: .topLeading)

                editor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(stepOrderStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("step-order-phrase-workflow-\(phrase.id.uuidString)")
        .onAppear(perform: reconcileEditorState)
        .onChange(of: maps.map(\.id)) {
            reconcileEditorState()
        }
        .onChange(of: presentation.editorMapID) {
            reconcileEditorState()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Step Order")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)

                    Text(presentation.scopeLabel.uppercased())
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(StudioTheme.cyan.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(StudioTheme.cyan.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                        )
                        .accessibilityLabel("Scope Phrase, fixed Step Order version 1 scope")

                    Text(presentation.statusLabel.uppercased())
                        .studioText(.microEmphasis)
                        .foregroundStyle(statusAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusAccent.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(statusAccent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                        )
                }

                Text("\(presentation.activeMapName) - \(presentation.activeMapDetail). \(presentation.statusSummary)")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button {
                onRequestEnabled(presentation.nextToggleValue)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: toggleIconName)
                        .font(.system(size: 14, weight: .bold))
                    Text(presentation.statusLabel)
                        .studioText(.labelBold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(presentation.canToggle ? StudioTheme.text : StudioTheme.mutedText)
                .frame(width: 126, height: 34)
                .background(statusAccent.opacity(presentation.canToggle ? StudioOpacity.selectedFill : StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(statusAccent.opacity(presentation.canToggle ? 0.7 : StudioOpacity.ghostStroke), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!presentation.canToggle)
            .accessibilityLabel(presentation.toggleAccessibilityLabel)
            .accessibilityHint(toggleHint)
            .accessibilityIdentifier("step-order-toggle-\(phrase.id.uuidString)")
        }
    }

    private var mapPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Maps")
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                Button {
                    createMap()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 24, height: 24)
                        .background(StudioTheme.cyan.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Create identity Step Order map")
                .accessibilityLabel("Create Step Order map")
                .accessibilityIdentifier("step-order-create-map")
            }

            if rows.isEmpty {
                Text("No maps yet")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                    .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rows) { row in
                        mapRow(row)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("step-order-map-picker")
    }

    private func mapRow(_ row: StepOrderMapRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                editorMapID = row.id
                draftMapName = row.name
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(row.name)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if row.isAssignedToCurrentPhrase {
                        Text("ASSIGNED")
                            .studioText(.microEmphasis)
                            .foregroundStyle(StudioTheme.success)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityIdentifier("step-order-map-row-\(row.id.uuidString)")

            HStack(spacing: 7) {
                Text(row.usageLabel)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(row.detailLabel)
                    .studioText(.micro)
                    .foregroundStyle(row.detailLabel.hasPrefix("Invalid") ? StudioTheme.amber : StudioTheme.cyan)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                compactButton("Edit", systemImage: "slider.horizontal.3") {
                    editorMapID = row.id
                    draftMapName = row.name
                }

                compactButton("Assign", systemImage: "checkmark.circle") {
                    onAssignMap(row.id)
                }
                .disabled(row.isAssignedToCurrentPhrase)

                compactButton("Delete", systemImage: "trash") {
                    onDeleteMap(row.id)
                }
                .disabled(!row.canDelete)
                .help(row.deleteBlockedReason ?? "Delete unused Step Order map")
            }

            if let deleteBlockedReason = row.deleteBlockedReason {
                Text("Delete blocked: \(deleteBlockedReason)")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.amber)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(row.id == resolvedEditorMapID ? StudioTheme.cyan.opacity(StudioOpacity.faintStroke) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(row.isAssignedToCurrentPhrase ? StudioTheme.success.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                activeMapMenu

                Spacer(minLength: 8)

                Button {
                    resetEditorMapToIdentity()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Reset")
                            .studioText(.labelBold)
                    }
                    .foregroundStyle(editorMap == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .frame(width: 84, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(editorMap == nil)
                .accessibilityLabel("Reset Step Order map to identity")
            }

            renameRow

            if let editorMap {
                if editorMap.isValid {
                    editorGrid(editorMap)
                } else {
                    invalidEditorMessage(editorMap)
                }
            } else {
                Text("Create or select a map to edit output and source steps.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("step-order-map-editor")
    }

    private var activeMapMenu: some View {
        Menu {
            Button("Unassign current phrase") {
                onAssignMap(nil)
            }
            Divider()
            ForEach(maps) { map in
                Button(map.name) {
                    editorMapID = map.id
                    draftMapName = map.name
                    onAssignMap(map.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active map")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                    Text(presentation.activeMapName)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Active Step Order map \(presentation.activeMapName)")
        .accessibilityIdentifier("step-order-active-map-menu")
    }

    private var renameRow: some View {
        HStack(spacing: 8) {
            TextField("Map name", text: $draftMapName)
                .textFieldStyle(.plain)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
                .disabled(editorMap == nil)
                .accessibilityLabel("Step Order map name")

            Button {
                renameEditorMap()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(canRenameEditorMap ? StudioTheme.text : StudioTheme.mutedText)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canRenameEditorMap)
            .accessibilityLabel("Rename Step Order map")
        }
    }

    private func editorGrid(_ map: StepOrderMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(StepOrderPhraseSurfacePresentation.mapDetail(for: map))
                .studioText(.microEmphasis)
                .foregroundStyle(map.values == StepOrderMap.identityValues ? StudioTheme.success : StudioTheme.cyan)

            stepRow(
                title: "Output",
                values: StepOrderPhraseSurfacePresentation.stepCandidateValues(),
                selectedIndex: selectedOutputIndex,
                accessibilityLabel: { outputIndex in
                    StepOrderPhraseSurfacePresentation.outputStepAccessibilityLabel(
                        outputIndex: outputIndex,
                        sourceIndex: Int(map.values[outputIndex])
                    )
                }
            ) { outputIndex in
                selectedOutputIndex = outputIndex
                wrapFeedbackVisible = false
            }

            stepRow(
                title: "Source",
                values: StepOrderPhraseSurfacePresentation.stepCandidateValues(),
                selectedIndex: Int(map.values[selectedOutputIndex]),
                accessibilityLabel: { sourceIndex in
                    StepOrderPhraseSurfacePresentation.sourceStepAccessibilityLabel(
                        sourceIndex: sourceIndex,
                        selectedOutputIndex: selectedOutputIndex
                    )
                }
            ) { sourceIndex in
                assignSourceStep(sourceIndex, to: selectedOutputIndex, map: map)
            }

            HStack(spacing: 8) {
                Text(StepOrderPhraseSurfacePresentation.outputStepAccessibilityLabel(
                    outputIndex: selectedOutputIndex,
                    sourceIndex: Int(map.values[selectedOutputIndex])
                ))
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)

                if wrapFeedbackVisible {
                    Text("End reached - wrapped to step 1")
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.amber)
                }
            }
            .frame(minHeight: 18, alignment: .leading)
        }
    }

    private func stepRow(
        title: String,
        values: [Int],
        selectedIndex: Int,
        accessibilityLabel: @escaping (Int) -> String,
        action: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .studioText(.microEmphasis)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 48, alignment: .leading)

            ForEach(0..<StepOrderMap.stepCount, id: \.self) { index in
                let isSelected = index == selectedIndex
                Button {
                    action(index)
                } label: {
                    Text("\(values[index] + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .background((isSelected ? StudioTheme.cyan.opacity(StudioOpacity.selectedFill) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                .stroke(isSelected ? StudioTheme.cyan.opacity(0.7) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(index))
                .accessibilityIdentifier("step-order-\(title.lowercased())-\(index)")
            }
        }
    }

    private func invalidEditorMessage(_ map: StepOrderMap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(map.validationIssue.map(StepOrderPhraseSurfacePresentation.validationIssueLabel) ?? "Invalid map")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.amber)
            Text("Choose another map or reset this map to identity before assignment.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
    }

    private var stepOrderStroke: Color {
        switch presentation.status {
        case .on, .pendingOn:
            return StudioTheme.success.opacity(StudioOpacity.mediumStroke)
        case .pendingOff, .invalid, .unavailable:
            return StudioTheme.amber.opacity(StudioOpacity.mediumStroke)
        case .off, .unassigned:
            return StudioTheme.cyan.opacity(StudioOpacity.faintStroke)
        }
    }

    private var statusAccent: Color {
        switch presentation.status {
        case .on, .pendingOn:
            return StudioTheme.success
        case .pendingOff, .invalid, .unavailable:
            return StudioTheme.amber
        case .off, .unassigned:
            return StudioTheme.cyan
        }
    }

    private var toggleIconName: String {
        switch presentation.status {
        case .on, .pendingOn:
            return "power.circle.fill"
        case .pendingOff:
            return "clock.badge"
        case .off:
            return "power.circle"
        case .unassigned, .unavailable, .invalid:
            return "exclamationmark.circle"
        }
    }

    private var toggleHint: String {
        presentation.canToggle
            ? "Requests the phrase-scoped Step Order state"
            : "Assign a valid 16-step map before toggling Step Order"
    }

    private var canRenameEditorMap: Bool {
        guard let editorMap else { return false }
        let trimmed = draftMapName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != editorMap.name
    }

    private func compactButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .studioText(.microEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func createMap() {
        let name = StepOrderPhraseSurfacePresentation.newMapName(existingMaps: maps)
        guard let mapID = onCreateMap(name) else {
            return
        }
        editorMapID = mapID
        draftMapName = name
        selectedOutputIndex = 0
        wrapFeedbackVisible = false
    }

    private func renameEditorMap() {
        guard let editorMap else { return }
        let trimmed = draftMapName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRenameMap(editorMap.id, trimmed)
        draftMapName = trimmed
    }

    private func assignSourceStep(_ sourceIndex: Int, to outputIndex: Int, map: StepOrderMap) {
        var values = map.values
        values[outputIndex] = UInt8(sourceIndex)
        onSetMapValues(map.id, values)
        wrapFeedbackVisible = StepOrderPhraseSurfacePresentation.didWrapAfterEditing(outputIndex: outputIndex)
        selectedOutputIndex = StepOrderPhraseSurfacePresentation.advancedOutputIndex(after: outputIndex)
    }

    private func resetEditorMapToIdentity() {
        guard let editorMap else { return }
        onSetMapValues(editorMap.id, StepOrderMap.identityValues)
        selectedOutputIndex = 0
        wrapFeedbackVisible = false
    }

    private func reconcileEditorState() {
        let nextID = resolvedEditorMapID
        editorMapID = nextID
        if let map = nextID.flatMap({ id in maps.first { $0.id == id } }) {
            draftMapName = map.name
            selectedOutputIndex = min(selectedOutputIndex, max(0, map.values.count - 1))
        } else {
            draftMapName = ""
            selectedOutputIndex = 0
        }
        wrapFeedbackVisible = false
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
