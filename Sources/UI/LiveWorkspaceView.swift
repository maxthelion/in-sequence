import SwiftUI

struct LiveWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var collapseGroups = true

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

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

    private var visibleScopes: [LiveLaneScope] {
        var scopes: [LiveLaneScope] = []
        var emittedGroups: Set<TrackGroupID> = []
        let trackGroups = session.store.trackGroups

        for track in session.store.tracks {
            if collapseGroups,
               let groupID = track.groupID,
               let group = trackGroups.first(where: { $0.id == groupID }),
               !emittedGroups.contains(groupID)
            {
                emittedGroups.insert(groupID)
                let members = session.store.tracksInGroup(groupID)
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
               let group = trackGroups.first(where: { $0.id == groupID })
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

            // Macro knob row for the currently selected track.
            MacroKnobRow(
                document: $document,
                trackID: session.store.selectedTrackID
            )
        }
    }

    private var topBar: some View {
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
                    .fill(accent)
                    .frame(width: 28, height: 3)
                    .clipShape(Capsule())

                Text(layerSubtitle(selectedLayer))
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent.opacity(StudioOpacity.hoverFill), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.subtleStroke), lineWidth: 1)
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

            Text(editingPhrase.name)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.violet)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(StudioTheme.violet.opacity(StudioOpacity.faintStroke), in: Capsule())

            if !session.store.trackGroups.isEmpty {
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
            let seedValue = editingPhrase.resolvedValue(for: selectedLayer, trackID: trackIDs.first ?? session.store.selectedTrackID, stepIndex: currentStepIndexInPhrase)
            session.setPhraseCell(
                .single(cycleLiveValue(seedValue)),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case let .single(value):
            session.setPhraseCell(
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
            session.setPhraseCell(
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
            session.setPhraseCell(
                .steps(nextValues),
                layerID: selectedLayer.id,
                trackIDs: trackIDs,
                phraseID: editingPhraseID
            )
        case .curve:
            let seedValue = editingPhrase.resolvedValue(for: selectedLayer, trackID: trackIDs.first ?? session.store.selectedTrackID, stepIndex: currentStepIndexInPhrase)
            session.setPhraseCell(
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
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(scope.accent)

                Spacer()

                if isMixed {
                    Text("MIX")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
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
                metrics: .live
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(scope.accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
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
