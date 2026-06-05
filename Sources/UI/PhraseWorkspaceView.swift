import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0
    @State private var phraseControlsState = PhraseButtonControlsState()

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

    private var phraseControlsPanelWidth: CGFloat {
        let trackSlotsWidth = CGFloat(visibleTrackSlots.count) * trackColumnWidth
        let interiorSpacing = CGFloat(max(visibleTrackSlots.count, 1)) * gridSpacing
        return phraseColumnWidth + interiorSpacing + trackSlotsWidth
    }

    private var playbackPhraseIndex: Int? {
        guard engineController.isRunning else {
            return nil
        }

        return PhrasePlayhead.playbackPhraseIndex(
            transportTickIndex: engineController.transportTickIndex,
            phrases: phrases,
            stepsPerBar: selectedPhrase.stepsPerBar
        )
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
            phraseControlsState.reconcile(availablePhraseIDs: phrases.map(\.id))
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: gridSpacing) {
                            let isOpen = phraseControlsState.openPhraseID == phrase.id
                            PhraseMatrixPhraseCell(
                                phrase: phrase,
                                isSelected: selectedPhraseID == phrase.id,
                                isPlaying: playbackPhraseIndex == index,
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                isOpen: isOpen
                            ) {
                                session.setSelectedPhraseID(phrase.id)
                                phraseControlsState.toggleControls(for: phrase.id)
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

                        if phraseControlsState.openPhraseID == phrase.id {
                            PhraseButtonControlsPanel(
                                phrase: phrase,
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                onChangeBarCount: { nextBarCount in
                                    session.setPhraseBarCount(nextBarCount, phraseID: phrase.id)
                                },
                                onChangeRepeatCount: { nextRepeatCount in
                                    session.setPhraseRepeatCount(nextRepeatCount, phraseID: phrase.id)
                                },
                                onToggleLoop: {
                                    session.setPhraseLoopEnabled(!phrase.loopEnabled, phraseID: phrase.id)
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
    let onChangeBarCount: (Int) -> Void
    let onChangeRepeatCount: (Int) -> Void
    let onToggleLoop: () -> Void

    private var presentation: PhraseButtonControlPresentation {
        PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: false,
            isPlaying: false,
            isQueued: isQueued,
            isOpen: true
        )
    }

    var body: some View {
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
