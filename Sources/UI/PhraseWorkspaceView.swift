import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0

    private let phraseColumnWidth: CGFloat = 118
    private let trackColumnWidth: CGFloat = 126
    private let actionColumnWidth: CGFloat = 92
    private let gridSpacing: CGFloat = 10
    private let trackPageSize = 8

    private var phrases: [PhraseModel] { document.model.phrases }
    private var tracks: [StepSequenceTrack] { document.model.tracks }
    private var layers: [PhraseLayerDefinition] { document.model.layers }
    private var selectedPhrase: PhraseModel { document.model.selectedPhrase }
    private var selectedTrack: StepSequenceTrack { document.model.selectedTrack }

    private var selectedLayer: PhraseLayerDefinition {
        document.model.layer(id: selectedLayerID)
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
                document: $document,
                target: target,
                accent: layerAccent(target.layerID)
            )
        }
        .onAppear {
            if document.model.layer(id: selectedLayerID) == nil {
                selectedLayerID = document.model.patternLayer?.id ?? layers.first?.id ?? "pattern"
            }
            clampTrackPage()
        }
        .onChange(of: document.model.selectedTrackID) {
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
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(selectedLayer.name.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)

                Rectangle()
                    .fill(layerAccent(selectedLayer.id))
                    .frame(width: 28, height: 3)
                    .clipShape(Capsule())

                Text(layerSubtitle(selectedLayer))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(layerAccent(selectedLayer.id))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(layerAccent(selectedLayer.id).opacity(0.16), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(layerAccent(selectedLayer.id).opacity(0.28), lineWidth: 1)
            )

            Button {
                cycleLayer(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                trackPageButton(systemImage: "chevron.left", action: { cycleTrackPage(by: -1) }, isEnabled: trackPage > 0)

                Text("Tracks \(trackPage + 1) / \(trackPageCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04), in: Capsule())

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
        guard let selectedIndex = tracks.firstIndex(where: { $0.id == document.model.selectedTrackID }) else {
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
        document.model.selectPhrase(id: phraseID)
        document.model.selectTrack(id: trackID)

        if selectedLayer.valueType == .boolean {
            toggleBooleanCell(phraseID: phraseID, trackID: trackID)
        }
    }

    private func openCellEditor(phraseID: UUID, trackID: UUID) {
        document.model.selectPhrase(id: phraseID)
        document.model.selectTrack(id: trackID)
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
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.04), in: Circle())
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
                                    document.model.selectTrack(id: track.id)
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

                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        PhraseMatrixPhraseCell(
                            phrase: phrase,
                            isSelected: document.model.selectedPhraseID == phrase.id,
                            isPlaying: playbackPhraseIndex == index
                        ) {
                            document.model.selectPhrase(id: phrase.id)
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
                                        isSelected: phrase.id == document.model.selectedPhraseID && track.id == document.model.selectedTrackID,
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
                                document.model.insertPhrase(below: phrase.id)
                            },
                            onDuplicate: {
                                document.model.duplicatePhrase(id: phrase.id)
                            },
                            onRemove: {
                                document.model.removePhrase(id: phrase.id)
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

        document.model.updatePhrase(id: phraseID) { phrase in
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
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(0.55) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct LiveWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController
    @State private var collapseGroups = true
    @State private var selectedBarPage = 0

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    private var selectedLayer: PhraseLayerDefinition {
        document.model.layer(id: selectedLayerID)
            ?? document.model.patternLayer
            ?? document.model.layers.first!
    }

    private var layers: [PhraseLayerDefinition] {
        document.model.layers
    }

    private var selectedLayerIndex: Int {
        layers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var editingPhrase: PhraseModel {
        document.model.phrases.first(where: { $0.id == editingPhraseID }) ?? document.model.selectedPhrase
    }

    private var editingPhraseID: UUID {
        guard engineController.transportMode == .song,
              engineController.isRunning,
              let playbackPhraseIndex
        else {
            return document.model.selectedPhraseID
        }

        return document.model.phrases[playbackPhraseIndex].id
    }

    private var playbackPhraseIndex: Int? {
        let phrases = document.model.phrases
        guard engineController.isRunning, !phrases.isEmpty else {
            return nil
        }

        let totalBars = phrases.reduce(0) { $0 + max(1, $1.lengthBars) }
        guard totalBars > 0 else {
            return nil
        }

        let absoluteBar = Int(engineController.transportTickIndex) / max(1, document.model.selectedPhrase.stepsPerBar)
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

    private var visibleScopes: [LiveLaneScope] {
        var scopes: [LiveLaneScope] = []
        var emittedGroups: Set<TrackGroupID> = []

        for track in document.model.tracks {
            if collapseGroups,
               let groupID = track.groupID,
               let group = document.model.trackGroups.first(where: { $0.id == groupID }),
               !emittedGroups.contains(groupID)
            {
                emittedGroups.insert(groupID)
                let members = document.model.tracksInGroup(groupID)
                scopes.append(
                    LiveLaneScope(
                        kind: .group(group.id),
                        title: group.name,
                        subtitle: "\(members.count) tracks • \(group.sharedDestination?.kindLabel ?? "No sink")",
                        trackIDs: members.map(\.id),
                        accent: StudioTheme.success
                    )
                )
                continue
            }

            let subtitle: String
            if let groupID = track.groupID,
               let group = document.model.trackGroups.first(where: { $0.id == groupID })
            {
                subtitle = "\(group.name) • \(track.trackType.shortLabel)"
            } else {
                subtitle = "\(track.trackType.shortLabel) • \(track.destination.kindLabel)"
            }

            scopes.append(
                LiveLaneScope(
                    kind: .track(track.id),
                    title: track.name,
                    subtitle: subtitle,
                    trackIDs: [track.id],
                    accent: track.groupID == nil ? accent : StudioTheme.success
                )
            )
        }

        return scopes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visibleScopes) { scope in
                    Button {
                        performPrimaryAction(on: scope)
                    } label: {
                        LiveScopeCard(
                            scope: scope,
                            layer: selectedLayer,
                            cell: editableCell(for: scope),
                            modeLabel: currentMode(for: scope)?.label ?? "Mixed",
                            summary: liveValueLabel(for: scope),
                            isMixed: sharedCell(for: scope) == nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                cycleLayer(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(selectedLayer.name.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)

                Rectangle()
                    .fill(accent)
                    .frame(width: 28, height: 3)
                    .clipShape(Capsule())

                Text(layerSubtitle(selectedLayer))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.16), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )

            Button {
                cycleLayer(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.04), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(editingPhrase.name)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(StudioTheme.violet.opacity(0.14), in: Capsule())

            if !document.model.trackGroups.isEmpty {
                Toggle("Collapse groups", isOn: $collapseGroups)
                    .toggleStyle(.switch)
                    .labelsHidden()
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

    @ViewBuilder
    private func liveEditor(for scope: LiveLaneScope, cell: PhraseCell) -> some View {
        switch cell {
        case .inheritDefault:
            StudioPlaceholderTile(
                title: "Using Layer Default",
                detail: "This lane is inheriting the default \(selectedLayer.name.lowercased()) value. Pick a mode or change a value to author it directly.",
                accent: scope.accent
            )
        case let .single(value):
            liveSingleValueEditor(value: value, scope: scope)
        case let .bars(values):
            liveBarsEditor(values: values, scope: scope)
        case let .steps(values):
            liveStepsEditor(values: values, scope: scope)
        case let .curve(points):
            liveCurveEditor(points: points, scope: scope)
        }
    }

    @ViewBuilder
    private func liveSingleValueEditor(value: PhraseCellValue, scope: LiveLaneScope) -> some View {
        switch selectedLayer.valueType {
        case .boolean:
            Toggle("Enabled", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: selectedLayer) { return isOn }
                    return false
                },
                set: { newValue in
                    document.model.setPhraseCell(
                        .single(.bool(newValue)),
                        layerID: selectedLayer.id,
                        trackIDs: scope.trackIDs,
                        phraseID: editingPhraseID
                    )
                }
            ))
            .toggleStyle(.switch)
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: selectedLayer) { return index }
                        return 0
                    },
                    set: { newIndex in
                        document.model.setPhraseCell(
                            .single(.index(newIndex)),
                            layerID: selectedLayer.id,
                            trackIDs: scope.trackIDs,
                            phraseID: editingPhraseID
                        )
                    }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: selectedLayer.name,
                range: selectedLayer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: selectedLayer) { return scalar }
                        return selectedLayer.minValue
                    },
                    set: { newValue in
                        document.model.setPhraseCell(
                            .single(.scalar(newValue)),
                            layerID: selectedLayer.id,
                            trackIDs: scope.trackIDs,
                            phraseID: editingPhraseID
                        )
                    }
                )
            )
        }
    }

    private func liveBarsEditor(values: [PhraseCellValue], scope: LiveLaneScope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 12) {
                    Text("Bar \(index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .frame(width: 44, alignment: .leading)

                    liveValueEditor(for: value) { newValue in
                        var nextValues = values
                        nextValues[index] = newValue
                        document.model.setPhraseCell(
                            .bars(nextValues),
                            layerID: selectedLayer.id,
                            trackIDs: scope.trackIDs,
                            phraseID: editingPhraseID
                        )
                    }
                }
            }
        }
    }

    private func liveStepsEditor(values: [PhraseCellValue], scope: LiveLaneScope) -> some View {
        let pageCount = max(1, editingPhrase.lengthBars)
        let activePage = min(selectedBarPage, pageCount - 1)
        let start = activePage * editingPhrase.stepsPerBar
        let end = min(start + editingPhrase.stepsPerBar, values.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Button {
                        selectedBarPage = index
                    } label: {
                        Text("Bar \(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                index == activePage ? scope.accent.opacity(0.2) : Color.white.opacity(0.04),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(start..<end, id: \.self) { stepIndex in
                    Button {
                        var nextValues = values
                        nextValues[stepIndex] = cycleLiveValue(nextValues[stepIndex])
                        document.model.setPhraseCell(
                            .steps(nextValues),
                            layerID: selectedLayer.id,
                            trackIDs: scope.trackIDs,
                            phraseID: editingPhraseID
                        )
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(stepIndex - start + 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                            Text(valueLabel(values[stepIndex], layer: selectedLayer))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(scope.accent.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func liveCurveEditor(points: [Double], scope: LiveLaneScope) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PhraseCurvePreset.allCases, id: \.self) { preset in
                    Button(preset.label) {
                        document.model.setPhraseCell(
                            .curve(preset.points(in: selectedLayer.scalarRange)),
                            layerID: selectedLayer.id,
                            trackIDs: scope.trackIDs,
                            phraseID: editingPhraseID
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }

            PhraseCurvePreview(points: points, range: selectedLayer.scalarRange, accent: scope.accent)
                .frame(height: 120)
        }
    }

    @ViewBuilder
    private func liveValueEditor(
        for value: PhraseCellValue,
        onChange: @escaping (PhraseCellValue) -> Void
    ) -> some View {
        switch selectedLayer.valueType {
        case .boolean:
            Toggle("", isOn: Binding(
                get: {
                    if case let .bool(isOn) = value.normalized(for: selectedLayer) { return isOn }
                    return false
                },
                set: { onChange(.bool($0)) }
            ))
            .labelsHidden()
        case .patternIndex:
            PatternIndexPicker(
                selectedIndex: Binding(
                    get: {
                        if case let .index(index) = value.normalized(for: selectedLayer) { return index }
                        return 0
                    },
                    set: { onChange(.index($0)) }
                )
            )
        case .scalar:
            ScalarValueEditor(
                title: nil,
                range: selectedLayer.scalarRange,
                value: Binding(
                    get: {
                        if case let .scalar(scalar) = value.normalized(for: selectedLayer) { return scalar }
                        return selectedLayer.minValue
                    },
                    set: { onChange(.scalar($0)) }
                )
            )
        }
    }

    private var currentStepIndexInPhrase: Int {
        let stepCount = max(1, editingPhrase.stepCount)
        return Int(engineController.transportTickIndex) % stepCount
    }

    private var currentBarIndexInPhrase: Int {
        min(max(0, currentStepIndexInPhrase / max(1, editingPhrase.stepsPerBar)), max(editingPhrase.lengthBars - 1, 0))
    }

    private func performPrimaryAction(on scope: LiveLaneScope) {
        let cell = editableCell(for: scope)
        let trackIDs = scope.trackIDs

        switch cell {
        case .inheritDefault:
            let seedValue = editingPhrase.resolvedValue(for: selectedLayer, trackID: trackIDs.first ?? document.model.selectedTrackID, stepIndex: currentStepIndexInPhrase)
            document.model.setPhraseCell(
                .single(cycleLiveValue(seedValue)),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case let .single(value):
            document.model.setPhraseCell(
                .single(cycleLiveValue(value)),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case let .bars(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentBarIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycleLiveValue(nextValues[index])
            document.model.setPhraseCell(
                .bars(nextValues),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case let .steps(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentStepIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycleLiveValue(nextValues[index])
            document.model.setPhraseCell(
                .steps(nextValues),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case .curve:
            let seedValue = editingPhrase.resolvedValue(for: selectedLayer, trackID: trackIDs.first ?? document.model.selectedTrackID, stepIndex: currentStepIndexInPhrase)
            document.model.setPhraseCell(
                .single(cycleLiveValue(seedValue)),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        }
    }

    private func sharedCell(for scope: LiveLaneScope) -> PhraseCell? {
        let cells = scope.trackIDs.map { editingPhrase.cell(for: selectedLayer.id, trackID: $0) }
        guard let first = cells.first else {
            return nil
        }
        return cells.dropFirst().allSatisfy { $0 == first } ? first : nil
    }

    private func currentMode(for scope: LiveLaneScope) -> PhraseCellEditMode? {
        let modes = Set(scope.trackIDs.map { editingPhrase.cellMode(for: selectedLayer.id, trackID: $0) })
        guard modes.count == 1 else {
            return nil
        }
        return modes.first
    }

    private func editableCell(for scope: LiveLaneScope) -> PhraseCell {
        if let shared = sharedCell(for: scope) {
            return shared
        }

        guard let seedTrackID = scope.trackIDs.first else {
            return .inheritDefault
        }

        let firstCell = editingPhrase.cell(for: selectedLayer.id, trackID: seedTrackID)
        if firstCell != .inheritDefault {
            return firstCell
        }

        let mode = currentMode(for: scope) ?? .single
        return PhraseCell.makeDefault(
            mode: mode,
            layer: selectedLayer,
            defaultValue: selectedLayer.defaultValue(for: seedTrackID),
            stepCount: editingPhrase.stepCount,
            barCount: editingPhrase.lengthBars
        )
    }

    private func liveValueLabel(for scope: LiveLaneScope) -> String {
        guard let cell = sharedCell(for: scope) else {
            return "Mixed"
        }

        switch cell {
        case .inheritDefault:
            return "Default"
        case let .single(value):
            return valueLabel(value, layer: selectedLayer)
        case let .bars(values):
            return "\(values.count) bars"
        case let .steps(values):
            return "\(values.count) steps"
        case let .curve(points):
            return "\(points.count) pt curve"
        }
    }

    private func cycleLiveValue(_ value: PhraseCellValue) -> PhraseCellValue {
        cycledValue(value, for: selectedLayer)
    }

    private var accent: Color {
        switch selectedLayer.valueType {
        case .boolean:
            return StudioTheme.success
        case .patternIndex:
            return StudioTheme.violet
        case .scalar:
            return StudioTheme.cyan
        }
    }

}

private struct LiveLaneScope: Identifiable, Equatable {
    enum Kind: Equatable {
        case track(UUID)
        case group(TrackGroupID)
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let trackIDs: [UUID]
    let accent: Color

    var id: String {
        switch kind {
        case let .track(trackID):
            return Self.trackID(trackID)
        case let .group(groupID):
            return "group:\(groupID.uuidString)"
        }
    }

    static func trackID(_ trackID: UUID) -> String {
        "track:\(trackID.uuidString)"
    }
}

private struct LiveScopeCard: View {
    let scope: LiveLaneScope
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let modeLabel: String
    let summary: String
    let isMixed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(modeLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(scope.accent)

                Spacer()

                if isMixed {
                    Text("MIX")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Text(scope.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)

            Text(scope.subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(2)

            PhraseCellPreview(
                layer: layer,
                cell: cell,
                resolvedValue: resolvedValue,
                accent: scope.accent,
                summary: summary,
                isMixed: isMixed,
                style: .live
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(scope.accent.opacity(0.16), lineWidth: 1)
        )
    }

    private var resolvedValue: PhraseCellValue {
        switch cell {
        case .inheritDefault:
            return layer.defaultValue(for: scope.trackIDs.first ?? UUID())
        case let .single(value):
            return value
        case let .bars(values):
            return values.first ?? layer.defaultValue(for: scope.trackIDs.first ?? UUID())
        case let .steps(values):
            return values.first ?? layer.defaultValue(for: scope.trackIDs.first ?? UUID())
        case let .curve(points):
            return .scalar(points.first ?? layer.minValue)
        }
    }

}

private struct PhraseMatrixTrackHeaderCell: View {
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
            Text(track.trackType.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background((isSelected ? accent.opacity(0.15) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }
}

private struct PhraseMatrixEmptyTrackHeaderCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.015))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
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
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                Text("\(phrase.lengthBars) bars")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)

                if isPlaying {
                    Text("Playing")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.success)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((isSelected ? StudioTheme.violet.opacity(0.14) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
                style: .matrix
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((isSelected ? accent.opacity(0.15) : Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.6 : 0.12), lineWidth: 1)
        )
    }
}

private struct PhraseGridEmptyCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.015))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
    }
}

private func layerAccent(_ layerID: String) -> Color {
    switch layerID {
    case "pattern", "brightness", "register":
        return StudioTheme.violet
    case "mute", "fill-flag":
        return StudioTheme.success
    case "tension", "transpose":
        return StudioTheme.amber
    default:
        return StudioTheme.cyan
    }
}

private func layerFill(_ layer: PhraseLayerDefinition, isSelected: Bool) -> Color {
    let accent = layerAccent(layer.id)
    return isSelected ? accent.opacity(0.16) : accent.opacity(0.05)
}

private func layerSubtitle(_ layer: PhraseLayerDefinition) -> String {
    switch layer.target {
    case .patternIndex:
        return "pattern slot"
    case .mute:
        return "track mute"
    case let .macroRow(name):
        return name
    case .blockParam:
        return "block param"
    case .voiceRouteOverride:
        return "voice route"
    }
}
