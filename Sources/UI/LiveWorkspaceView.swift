import SwiftUI

struct LiveWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    /// AC18: a LINKED kit collapses to one cell in Song mode; an unlinked kit
    /// expands to per-part cells (linked↔collapsed, unlinked↔expanded). The
    /// Expand affordance on a collapsed cell adds the group here for display
    /// only — it never changes the link state.
    @State private var forceExpandedGroups: Set<TrackGroupID> = []

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
        TracksBasisPhraseResolver.resolvePhrase(
            engineBasisPhraseID: engineController.basisPhraseID,
            selectedPhraseID: session.store.selectedPhraseID,
            selectedPhrase: session.store.selectedPhrase,
            phrases: session.store.phrases
        )
    }

    private var editingPhraseID: UUID {
        editingPhrase.id
    }

    /// A linked kit collapses to one cell unless the user has transiently
    /// forced it expanded via the Expand affordance (AC18). An unlinked kit is
    /// always expanded to its per-part cells.
    private func isGroupCollapsed(_ group: TrackGroup) -> Bool {
        group.isPatternLinked && !forceExpandedGroups.contains(group.id)
    }

    private var visibleScopes: [LiveLaneScope] {
        var scopes: [LiveLaneScope] = []
        var emittedGroups: Set<TrackGroupID> = []
        let trackGroups = session.store.trackGroups

        for track in session.store.tracks {
            if let groupID = track.groupID,
               let group = trackGroups.first(where: { $0.id == groupID }),
               isGroupCollapsed(group),
               !emittedGroups.contains(groupID)
            {
                emittedGroups.insert(groupID)
                let members = session.store.tracksInGroup(groupID)
                scopes.append(
                    LiveLaneScope(
                        kind: .group(group.id),
                        title: group.name,
                        subtitle: "\(members.count) parts • \(group.sharedDestination?.kindLabel ?? "Own bus")",
                        trackIDs: members.map(\.id),
                        accent: StudioTheme.groupAccent(for: group)
                    )
                )
                continue
            }

            let subtitle: String
            let laneAccent: Color
            if let groupID = track.groupID,
               let group = trackGroups.first(where: { $0.id == groupID })
            {
                subtitle = "\(group.name) • \(track.trackType.shortLabel)"
                laneAccent = StudioTheme.groupAccent(for: group)
            } else {
                subtitle = "\(track.trackType.shortLabel) • \(track.destination.kindLabel)"
                laneAccent = accent
            }

            scopes.append(
                LiveLaneScope(
                    kind: .track(track.id),
                    title: track.name,
                    subtitle: subtitle,
                    trackIDs: [track.id],
                    accent: laneAccent
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
                            isMixed: sharedCell(for: scope) == nil,
                            onExpandKit: expandAction(for: scope)
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
            StudioCircleIconButton(
                systemName: "chevron.left",
                size: StudioMetrics.ControlSize.large
            ) {
                cycleLayer(by: -1)
            }

            HStack(spacing: 10) {
                Text(selectedLayer.name.uppercased())
                    .studioText(.bodyBold)
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)

                Text(layerSubtitle(selectedLayer))
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                Text("\(selectedLayerIndex + 1) / \(max(layers.count, 1))")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent, in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
            )

            StudioCircleIconButton(
                systemName: "chevron.right",
                size: StudioMetrics.ControlSize.large
            ) {
                cycleLayer(by: 1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("BASIS PHRASE")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(editingPhrase.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.phraseAccent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Colour identifies, it never floods (ux-canon rule 12): the
            // basis-phrase chip stays neutral; violet lives in the outline
            // and the phrase name.
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.phraseAccent, lineWidth: StudioMetrics.borderWidth)
            )
        }
    }

    /// Non-nil only for a collapsed (linked) kit cell: the Expand affordance
    /// reveals the kit's per-part cells without changing the link state (AC18).
    private func expandAction(for scope: LiveLaneScope) -> (() -> Void)? {
        guard case let .group(groupID) = scope.kind else {
            return nil
        }
        return { forceExpandedGroups.insert(groupID) }
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
            return StudioTheme.phraseAccent
        case .patternIndex:
            return StudioTheme.phraseAccent
        case .scalar:
            return StudioTheme.phraseAccent
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
    /// Non-nil for a collapsed (linked) kit cell: shows an Expand affordance
    /// revealing the per-part cells (AC18).
    var onExpandKit: (() -> Void)? = nil

    private var isCollapsedKit: Bool {
        onExpandKit != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text((isCollapsedKit ? "KIT" : modeLabel).uppercased())
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(scope.accent)

                Spacer()

                if isCollapsedKit {
                    Text("LINKED")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(scope.accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                        .foregroundStyle(scope.accent)
                } else if isMixed {
                    Text("MIX")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(StudioTheme.borderSubtleFill, in: Capsule())
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

            if let onExpandKit {
                Button(action: onExpandKit) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("Expand")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(scope.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(scope.accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("kit-expand")
                .help("Expand \(scope.title) to its per-part cells")
            } else {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(scope.accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier(isCollapsedKit ? "kit-collapsed-cell" : "live-scope-card")
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
