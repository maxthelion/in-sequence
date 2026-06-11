import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding private var visualControlsOpenIndex: Int?
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0
    @State private var performanceLayerSelection = PerformanceLayerSelectionState()
    @State private var isPresentingPerformanceLayerSelection = false
    @State private var scalarDragBase: (phraseID: UUID, trackID: UUID, value: Double)?

    private let phraseColumnWidth: CGFloat = 118
    private let trackColumnWidth: CGFloat = 126
    private let actionColumnWidth: CGFloat = 100
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

    private var activeMatrixLayer: PhraseLayerDefinition? {
        guard let layerID = performanceLayerSelection.mode.phraseLayerID else {
            return nil
        }

        return matrixSelectableLayers.first { $0.id == layerID }
            ?? layers.first { $0.id == layerID }
    }

    private var activeLayerAccent: Color {
        activeMatrixLayer.map { layerAccent($0.id) } ?? performanceLayerSelection.mode.selectorAccent
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

    var body: some View {
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1).
        StudioPanel(
            title: "Phrase Matrix",
            accent: activeLayerAccent,
            showsHeader: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                layerBar
                if isPresentingPerformanceLayerSelection {
                    performanceLayerSelectionSurface
                } else {
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
            for command in VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands() {
                applyMatrixVisualCommand(command)
            }
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
        .onChange(of: performanceLayerSelection.mode) {
            if let layerID = performanceLayerSelection.mode.phraseLayerID,
               matrixSelectableLayers.contains(where: { $0.id == layerID }) {
                selectedLayerID = layerID
            }
            performanceLayerSelection.reconcileVariant()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: performanceLayerSelection.variantLabel) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phraseMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            // Receiving live proves this view is mounted; the pending copy
            // would otherwise replay stale on a later remount.
            VisualScenarioCommandRunner.pendingPhraseMatrixCommands = []
            applyMatrixVisualCommand(command)
        }
    }

    private func reconcileSelectedLayer() {
        if matrixSelectableLayers.contains(where: { $0.id == selectedLayerID }) {
            return
        }
        selectedLayerID = matrixSelectableLayers.first?.id ?? session.store.patternLayer?.id ?? layers.first?.id ?? "pattern"
    }

    /// Phrase bar/repeat controls are always visible now; the visual command
    /// keeps working by selecting the requested phrase.
    private func applyVisualControlsOpenIndex() {
        guard let visualControlsOpenIndex,
              phrases.indices.contains(visualControlsOpenIndex)
        else {
            return
        }

        session.setSelectedPhraseID(phrases[visualControlsOpenIndex].id)
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
        Button {
            isPresentingPerformanceLayerSelection = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: performanceLayerSelection.mode.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 28, height: 28)
                    .background(activeLayerAccent.opacity(StudioOpacity.selectedFill), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("PHRASE LAYER")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)

                    Text(performanceLayerSelection.activeLabel.uppercased())
                        .studioText(.labelBold)
                        .foregroundStyle(activeLayerAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(performanceLayerSelection.mode.subtitle)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isPresentingPerformanceLayerSelection ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(activeLayerAccent.opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
        .accessibilityIdentifier("phrase-layer-selector")
        .help("Choose the Phrase performance layer")
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
        if command == "open-layer-selector" {
            isPresentingPerformanceLayerSelection = true
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command == "close-layer-selector" {
            isPresentingPerformanceLayerSelection = false
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command.hasPrefix("select-layer:") {
            let rawMode = String(command.dropFirst("select-layer:".count))
            if let mode = TrackPerformLayerMode(rawValue: rawMode) {
                setPerformanceLayer(mode, variantLabel: nil)
            }
            return
        }

        if command.hasPrefix("select-variant:") {
            let rawSelection = String(command.dropFirst("select-variant:".count))
            let parts = rawSelection.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let mode = TrackPerformLayerMode(rawValue: parts[0])
            else { return }
            setPerformanceLayer(mode, variantLabel: parts[1])
            return
        }

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
                if let mode = TrackPerformLayerMode.allCases.first(where: { $0.phraseLayerID == layerID }) {
                    performanceLayerSelection.select(mode, variantLabel: nil)
                }
            }
            return
        }

        if command.hasPrefix("layer-index:"),
           let rawIndex = command.split(separator: ":").last,
           let index = Int(rawIndex),
           matrixSelectableLayers.indices.contains(index) {
            selectedLayerID = matrixSelectableLayers[index].id
            if let mode = TrackPerformLayerMode.allCases.first(where: { $0.phraseLayerID == selectedLayerID }) {
                performanceLayerSelection.select(mode, variantLabel: nil)
            }
        }
    }

    private func postRenderedMatrixVisualState(isVisible: Bool) {
        let layout = matrixLayout
        let activeLayer = activeMatrixLayer
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
                "selectedLayerID": isVisible ? activeLayer?.id ?? "virtual" : "none",
                "selectedLayerName": isVisible ? performanceLayerSelection.activeLabel : "none",
                "selectorWidth": isVisible ? PhraseLayerSelectorPresentation.fixedOuterWidth : 0,
                "trackGridWidth": isVisible ? trackGridWidth : 0,
                "performLayerMode": isVisible ? performanceLayerSelection.mode.rawValue : "none",
                "performLayerSelectorVisible": isVisible && isPresentingPerformanceLayerSelection,
                "performLayerVariant": isVisible ? performanceLayerSelection.variantLabel ?? "none" : "none",
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

        guard activeMatrixLayer?.valueType == .boolean else {
            return
        }

        if NSEvent.modifierFlags.contains(.shift) {
            cascadeBooleanValue(phraseID: phraseID, trackID: trackID)
        } else {
            toggleBooleanCell(phraseID: phraseID, trackID: trackID)
        }
    }

    /// Shift-click: toggle the value, write it into the layer default for the
    /// track, and convert this and every following phrase's cell to inherit it.
    /// A plain click stays a single explicit value on the clicked cell.
    private func cascadeBooleanValue(phraseID: UUID, trackID: UUID) {
        guard let layer = activeMatrixLayer,
              layer.valueType == .boolean,
              let startIndex = phrases.firstIndex(where: { $0.id == phraseID })
        else {
            return
        }

        let phrase = phrases[startIndex]
        let resolvedValue = phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: 0)
        let toggledValue = toggledBooleanValue(resolvedValue, for: layer)

        session.setPhraseLayerDefault(toggledValue, layerID: layer.id, trackID: trackID)
        for followingPhrase in phrases[startIndex...] {
            session.setPhraseCell(
                .inheritDefault,
                layerID: layer.id,
                trackIDs: [trackID],
                phraseID: followingPhrase.id
            )
        }
    }

    /// Vertical drag on a scalar cell edits its value in place, the same way
    /// velocity bars edit on the step sequencer. Dragging an inherited cell
    /// converts it to a single explicit value.
    private func scalarDragGesture(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition?
    ) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                guard let layer, layer.valueType == .scalar else {
                    return
                }
                let span = layer.maxValue - layer.minValue
                guard span > 0 else {
                    return
                }

                if scalarDragBase?.phraseID != phrase.id || scalarDragBase?.trackID != track.id {
                    let base: Double
                    switch phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0) {
                    case let .scalar(value):
                        base = value
                    case let .index(index):
                        base = Double(index)
                    case let .bool(isOn):
                        base = isOn ? layer.maxValue : layer.minValue
                    }
                    scalarDragBase = (phrase.id, track.id, base)
                }

                guard let dragBase = scalarDragBase else {
                    return
                }
                let next = dragBase.value + Double(-drag.translation.height) / 120 * span
                let clamped = min(max(next, layer.minValue), layer.maxValue)
                session.mutatePhrase(id: phrase.id) { mutablePhrase in
                    mutablePhrase.setCell(.single(.scalar(clamped)), for: layer.id, trackID: track.id)
                }
            }
            .onEnded { _ in
                scalarDragBase = nil
            }
    }

    private func openCellEditor(phraseID: UUID, trackID: UUID) {
        guard let activeMatrixLayer else { return }
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)
        editingCellTarget = PhraseCellEditorTarget(
            phraseID: phraseID,
            trackID: trackID,
            layerID: activeMatrixLayer.id
        )
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
                        .background(activeLayerAccent, in: Circle())
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
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                let activeLayer = activeMatrixLayer
                let accent = activeLayerAccent
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
                                        accent: track.groupID == nil ? accent : StudioTheme.success
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
                        // A fixed row height lets every cell stretch to the
                        // same bounds, keeping the strip aligned (ux-canon 9).
                        HStack(alignment: .top, spacing: gridSpacing) {
                            PhraseMatrixPhraseCell(
                                phrase: phrase,
                                isSelected: selectedPhraseID == phrase.id,
                                isPlaying: PhraseButtonControlPresentation.isPlayingBadgeVisible(
                                    phraseID: phrase.id,
                                    engineIsRunning: engineController.isRunning,
                                    currentPhraseID: engineController.currentPhraseID
                                ),
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                onSelect: {
                                    session.setSelectedPhraseID(phrase.id)
                                },
                                onChangeBarCount: { nextBarCount in
                                    session.setPhraseBarCount(nextBarCount, phraseID: phrase.id)
                                },
                                onChangeRepeatCount: { nextRepeatCount in
                                    session.setPhraseRepeatCount(nextRepeatCount, phraseID: phrase.id)
                                }
                            )
                            .frame(width: phraseColumnWidth)

                            PhraseMatrixGutterCell()
                                .frame(width: matrixGutterWidth)

                            ForEach(Array(visibleTrackSlots.enumerated()), id: \.offset) { _, track in
                                Group {
                                    if let track {
                                        Group {
                                            if let activeLayer {
                                                PhraseGridCell(
                                                    layer: activeLayer,
                                                    cell: phrase.cell(for: activeLayer.id, trackID: track.id),
                                                    phrase: phrase,
                                                    track: track,
                                                    isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                                    accent: accent
                                                )
                                            } else {
                                                PhrasePerformancePlaceholderCell(
                                                    selection: performanceLayerSelection,
                                                    phrase: phrase,
                                                    track: track,
                                                    isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                                    accent: accent
                                                )
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(
                                            TapGesture(count: 2)
                                                .exclusively(before: TapGesture())
                                                .onEnded { value in
                                                    switch value {
                                                    case .first:
                                                        if activeLayer != nil {
                                                            openCellEditor(phraseID: phrase.id, trackID: track.id)
                                                        }
                                                    case .second:
                                                        handleSingleTap(on: phrase.id, trackID: track.id)
                                                    }
                                                }
                                        )
                                        .simultaneousGesture(
                                            scalarDragGesture(phrase: phrase, track: track, layer: activeLayer)
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
                        .frame(height: PhraseMatrixLayoutPresentation.matrixRowHeight)

                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .frame(minHeight: 280)
    }

    private func toggleBooleanCell(phraseID: UUID, trackID: UUID) {
        guard let selectedLayer = activeMatrixLayer, selectedLayer.valueType == .boolean else {
            assertionFailure("toggleBooleanCell called without an active boolean phrase layer")
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

    private var performanceLayerSelectionSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("CHOOSE PHRASE LAYER")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)

                Spacer(minLength: 8)

                StudioCircleIconButton(
                    systemName: "xmark",
                    help: "Return to phrase rows"
                ) {
                    isPresentingPerformanceLayerSelection = false
                    postRenderedMatrixVisualState(isVisible: true)
                }
            }

            LazyVGrid(columns: performanceLayerSelectionColumns, alignment: .leading, spacing: 10) {
                ForEach(PerformanceLayerOption.all) { option in
                    PerformanceLayerOptionCell(
                        option: option,
                        isSelected: performanceLayerSelection.mode == option.mode
                            && performanceLayerSelection.variantLabel == option.variantLabel
                    ) {
                        choosePerformanceLayer(option)
                    }
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.subtleStroke), lineWidth: 1)
        )
        .accessibilityIdentifier("phrase-performance-layer-selection-surface")
    }

    private var performanceLayerSelectionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 84, maximum: 190), spacing: 10), count: 8)
    }

    private func choosePerformanceLayer(_ option: PerformanceLayerOption) {
        let isAlreadySelected = performanceLayerSelection.mode == option.mode
            && performanceLayerSelection.variantLabel == option.variantLabel
        if isAlreadySelected, option.variantLabel != nil {
            // Variant cells toggle: off returns to normal pattern playback.
            performanceLayerSelection.select(.pattern, variantLabel: nil)
        } else {
            performanceLayerSelection.select(option.mode, variantLabel: option.variantLabel)
        }
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        isPresentingPerformanceLayerSelection = false
        postRenderedMatrixVisualState(isVisible: true)
    }

    /// Idempotent variant used by visual automation commands: always selects,
    /// never toggles off.
    private func setPerformanceLayer(_ mode: TrackPerformLayerMode, variantLabel: String?) {
        performanceLayerSelection.select(mode, variantLabel: variantLabel)
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        isPresentingPerformanceLayerSelection = false
        postRenderedMatrixVisualState(isVisible: true)
    }
}

private struct PhraseRowActions: View {
    let canRemove: Bool
    let onInsertBelow: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void

    // The three row actions sit in one bordered container so they read as a
    // single control cluster rather than loose buttons (ux-canon rule 9).
    var body: some View {
        HStack(spacing: 6) {
            actionButton(systemImage: "plus", action: onInsertBelow)
            actionButton(systemImage: "plus.square.on.square", action: onDuplicate)
            actionButton(systemImage: "trash", action: onRemove, isDisabled: !canRemove)
        }
        .padding(6)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void, isDisabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
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
                .studioText(.microEmphasis)
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
            .fill(StudioTheme.inset)
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
    let onSelect: () -> Void
    let onChangeBarCount: (Int) -> Void
    let onChangeRepeatCount: (Int) -> Void

    private var presentation: PhraseButtonControlPresentation {
        PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: isSelected,
            isPlaying: isPlaying,
            isQueued: isQueued
        )
    }

    // Bars and repeat edit in place, always visible: no collapsed summary
    // duplicating the stepper values, no SEL badge (selection is the cell
    // chrome), no loop toggle (transport Song/Free owns that decision).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phrase.name)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(phrase.name)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    if isPlaying {
                        phraseBadge("Play", accent: StudioTheme.success)
                    }
                    if isQueued {
                        phraseBadge("Queue", accent: StudioTheme.amber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityHint("Select phrase")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("phrase-button-\(phrase.id.uuidString)")

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
                decrementDisabled: phrase.repeatCount <= PhraseModel.repeatCountRange.lowerBound,
                incrementDisabled: phrase.repeatCount >= PhraseModel.repeatCountRange.upperBound,
                onDecrement: {
                    onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount - 1))
                },
                onIncrement: {
                    onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount + 1))
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.compact)
        .background(rowFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("phrase-button-controls-\(phrase.id.uuidString)")
    }

    private var rowFill: Color {
        if phrase.loopEnabled {
            return StudioTheme.amber.opacity(isSelected ? StudioOpacity.selectedFill : StudioOpacity.subtleFill)
        }
        if isSelected {
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
        return StudioTheme.violet.opacity(isSelected ? 0.6 : 0.12)
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

private struct PhrasePolicyStepperControl: View {
    let title: String
    let valueLabel: String
    var footnote: String? = nil
    let decrementDisabled: Bool
    let incrementDisabled: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    // No label above the stepper: the value text carries the meaning and the
    // title lives in the tooltip and accessibility label (ux-canon rule 3).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                stepButton(systemName: "minus", action: onDecrement, isDisabled: decrementDisabled)

                Text(valueLabel)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 30)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(title)
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

private struct PhraseGridCell: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    // Inherited cells are a muted variant of explicit ones — no
    // "SINGLE"/"INHERIT" chip repeated in every cell (ux-canon rules 1/3).
    private var isInherited: Bool {
        cell.editMode == .inheritDefault
    }

    var body: some View {
        PhraseCellPreview(
            layer: layer,
            cell: cell,
            resolvedValue: phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0),
            accent: accent,
            summary: valueLabel(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0), layer: layer),
            metrics: .matrix
        )
        .opacity(isInherited ? StudioOpacity.inheritedContent : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.compact)
        .background((isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    accent.opacity(isSelected ? 0.6 : 0.12),
                    style: StrokeStyle(lineWidth: 1, dash: isInherited ? StudioAddCard.dashPattern : [])
                )
        )
        .help(isInherited ? "Follows the layer default. Click to set its own value; shift-click to push a value into this and the following phrases." : "")
    }
}

private struct PhrasePerformancePlaceholderCell: View {
    let selection: PerformanceLayerSelectionState
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    private var detail: String {
        switch selection.mode {
        case .noteRepeat:
            return "Repeat target"
        case .stepOrder:
            return "Step map"
        case .pan:
            return "Pan target"
        case .mute, .pattern, .fill, .volume:
            return "\(phrase.name) / \(track.name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The active layer is named once in the matrix header; cells only
            // carry the layer icon and their own target identity.
            Image(systemName: selection.mode.symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)

            Text(detail)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.compact)
        .background((isSelected ? accent.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill)), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.18), lineWidth: 1)
        )
        .accessibilityLabel("\(phrase.name), \(track.name), \(selection.activeLabel), selection only")
    }
}

private struct PhraseGridEmptyCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            .fill(StudioTheme.inset)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
