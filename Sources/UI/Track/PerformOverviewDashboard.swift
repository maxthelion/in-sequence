import SwiftUI

/// The perform-mode tracks dashboard (wireframes §9): one row per track —
/// pattern, fill, repeat, mute — with the macro rack strip beneath. This IS
/// the perform-mode tracks surface (decision: §1 and §9 are one surface,
/// not two). Row bodies read document/selection state only; anything that
/// varies at tick/meter rate (playhead-resolved values, quantised pending
/// mirrors, engine repeat/audio-in runtime) lives in leaf views so a
/// transport tick never re-builds the rows (TracksPageInvalidationTests).
struct PerformOverviewDashboard: View {
    let phrase: PhraseModel
    let rows: [PerformOverviewRowModel]
    let muteLayer: PhraseLayerDefinition?
    let patternLayer: PhraseLayerDefinition?
    let activeLayerMode: TrackPerformLayerMode
    let activeVariantLabel: String?
    let latchMode: TrackPerformLatchMode
    let selection: TrackPerformSelectionState
    let selectedTrackID: UUID
    let orderedTrackIDs: [UUID]
    let runtimeControlState: ([UUID], TrackPerformBinaryControl) -> TrackPerformRuntimeControlState
    let isCellDirty: (PhraseLayerDefinition, [UUID]) -> Bool
    let isQuantiseCueLive: Bool
    let onSelectRow: (UUID) -> Void
    let onToggleRowSelection: ([UUID]) -> Void
    /// Cycle a phrase-layer cell (mute taps): layer, source track,
    /// recipients. The host owns quantised-vs-immediate routing.
    let onCycleCell: (PhraseLayerDefinition, UUID, [UUID]) -> Void
    /// Set a phrase-layer cell to a SPECIFIC value (pattern mini-grid taps):
    /// layer, value, source track, recipients. Routed through the same staged
    /// perform path as `onCycleCell`, but addresses one slot directly instead
    /// of advancing by one.
    let onSetCellValue: (PhraseLayerDefinition, PhraseCellValue, UUID, [UUID]) -> Void
    let onActivateRuntimeControl: (TrackPerformBinaryControl, UUID, [UUID]) -> Void
    let onReleaseRuntimeControl: (TrackPerformBinaryControl, UUID) -> Void
    let onCueRuntimeControl: ((TrackPerformBinaryControl, UUID, [UUID]) -> Void)?

    static let nameColumnWidth: CGFloat = 158
    static let rowCellHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let placeholderNote {
                Text(placeholderNote)
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            columnHeader

            ForEach(rows) { row in
                #if DEBUG
                let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                #endif
                PerformOverviewRowView(
                    row: row,
                    phrase: phrase,
                    muteLayer: muteLayer,
                    patternLayer: patternLayer,
                    latchMode: latchMode,
                    isFocused: row.trackIDs.contains(selectedTrackID),
                    isInEditSet: row.trackIDs.allSatisfy { selection.contains($0) } && !selection.isEmpty,
                    runtimeControlState: runtimeControlState,
                    isCellDirty: isCellDirty,
                    recipients: recipients(for: row),
                    onSelectRow: onSelectRow,
                    onToggleRowSelection: onToggleRowSelection,
                    onCycleCell: onCycleCell,
                    onSetCellValue: onSetCellValue,
                    onActivateRuntimeControl: onActivateRuntimeControl,
                    onReleaseRuntimeControl: onReleaseRuntimeControl,
                    onCueRuntimeControl: onCueRuntimeControl
                )
            }

            PerformOverviewMacroRack()
                .padding(.top, 6)
        }
        .accessibilityIdentifier("perform-overview-dashboard")
    }

    private func recipients(for row: PerformOverviewRowModel) -> [UUID] {
        PerformOverviewRowModel.recipientTrackIDs(
            rowTrackIDs: row.trackIDs,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )
    }

    /// Layers without a dashboard column (volume / step order / pan) keep
    /// their selector entries but have no row surface this slice.
    private var placeholderNote: String? {
        switch activeLayerMode {
        case .volume:
            return "VOLUME is selected — per-track volume cells are not on the overview rows in this slice."
        case .stepOrder:
            return "STEP ORDER is selected — map selection lives on the Phrase page; the rows carry pattern, fill, repeat, and mute."
        case .pan:
            return "PAN is selected — live pan controls are not wired in this slice."
        case .mute, .pattern, .fill, .noteRepeat:
            return nil
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            // Mirrors the row leading: edit-set toggle (28) + name column.
            Text("TRACK")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: Self.nameColumnWidth + 28 + 8, alignment: .leading)

            columnHeaderLabel("PATTERN", mode: .pattern)
            columnHeaderLabel("FILL", mode: .fill)
            columnHeaderLabel(
                activeVariantLabel.map { "REPEAT \($0)" } ?? "REPEAT",
                mode: .noteRepeat
            )
            columnHeaderLabel("MUTE", mode: .mute)
        }
    }

    /// The layer selector highlights its column here — the at-a-glance
    /// answer to "which layer is active" now that every row carries all
    /// four controls (ux-canon rule 11).
    private func columnHeaderLabel(_ title: String, mode: TrackPerformLayerMode) -> some View {
        let isActive = activeLayerMode == mode
        return VStack(spacing: 3) {
            Text(title)
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(isActive ? mode.selectorAccent : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Rectangle()
                .fill(isActive ? mode.selectorAccent : Color.clear)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

struct PerformOverviewRowView: View {
    let row: PerformOverviewRowModel
    let phrase: PhraseModel
    let muteLayer: PhraseLayerDefinition?
    let patternLayer: PhraseLayerDefinition?
    let latchMode: TrackPerformLatchMode
    let isFocused: Bool
    let isInEditSet: Bool
    let runtimeControlState: ([UUID], TrackPerformBinaryControl) -> TrackPerformRuntimeControlState
    let isCellDirty: (PhraseLayerDefinition, [UUID]) -> Bool
    let recipients: [UUID]
    let onSelectRow: (UUID) -> Void
    let onToggleRowSelection: ([UUID]) -> Void
    let onCycleCell: (PhraseLayerDefinition, UUID, [UUID]) -> Void
    let onSetCellValue: (PhraseLayerDefinition, PhraseCellValue, UUID, [UUID]) -> Void
    let onActivateRuntimeControl: (TrackPerformBinaryControl, UUID, [UUID]) -> Void
    let onReleaseRuntimeControl: (TrackPerformBinaryControl, UUID) -> Void
    let onCueRuntimeControl: ((TrackPerformBinaryControl, UUID, [UUID]) -> Void)?

    private var kindLabel: String {
        switch row.kind {
        case .kit:
            return "KIT · \(row.parts.count) PARTS"
        case .audioInput:
            return "AUDIO IN"
        case .instrument:
            return row.trackType?.label.uppercased() ?? "TRACK"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                editSetToggle
                nameBlock

                switch row.kind {
                case .instrument, .kit:
                    patternCell
                    runtimeCell(.fill)
                    runtimeCell(.noteRepeat)
                    muteCell
                case .audioInput:
                    monitorCell
                    placeholderCell
                    placeholderCell
                    muteCell
                }
            }

            if row.kind == .kit, !row.parts.isEmpty {
                partStrip
            }
        }
        .padding(8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(rowStroke, lineWidth: isFocused || isInEditSet ? 2 : StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("perform-overview-row-\(row.id)")
    }

    private var rowStroke: Color {
        if isInEditSet {
            return StudioTheme.amber.opacity(StudioOpacity.accentFill)
        }
        if isFocused {
            return row.accent.opacity(StudioOpacity.accentFill)
        }
        return StudioTheme.border
    }

    private var editSetToggle: some View {
        Button {
            onToggleRowSelection(row.trackIDs)
        } label: {
            Image(systemName: isInEditSet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isInEditSet ? StudioTheme.amber : StudioTheme.mutedText)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isInEditSet ? "Remove from edit set" : "Add to edit set")
    }

    private var nameBlock: some View {
        Button {
            onSelectRow(row.primaryTrackID)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // One identity accent per row — the kit's six part
                    // colours collapse into this single line (wireframes §1).
                    Text(kindLabel)
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(row.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: PerformOverviewDashboard.nameColumnWidth, alignment: .leading)
        .help("Select \(row.title)")
    }

    private var patternCell: some View {
        Group {
            if let patternLayer {
                PerformOverviewPatternCellLeaf(
                    phrase: phrase,
                    layer: patternLayer,
                    trackIDs: row.trackIDs,
                    isDirty: isCellDirty(patternLayer, row.trackIDs)
                ) { slotIndex in
                    // Each slot in the mini grid sets THAT pattern directly via
                    // the staged perform path — no whole-cell cycle.
                    onSetCellValue(patternLayer, .index(slotIndex), row.primaryTrackID, recipients)
                }
            } else {
                placeholderCell
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func runtimeCell(_ control: TrackPerformBinaryControl) -> some View {
        let mode: TrackPerformLayerMode = control == .fill ? .fill : .noteRepeat
        return TrackPerformRuntimeLayerControl(
            mode: mode,
            trackIDs: row.trackIDs,
            state: runtimeControlState(row.trackIDs, control),
            latchMode: latchMode,
            accent: mode.selectorAccent,
            layout: .row,
            onActivate: { onActivateRuntimeControl(control, row.primaryTrackID, recipients) },
            onRelease: { onReleaseRuntimeControl(control, row.primaryTrackID) },
            onCue: control == .fill
                ? onCueRuntimeControl.map { cue in { cue(control, row.primaryTrackID, recipients) } }
                : nil
        )
        .frame(maxWidth: .infinity)
        .frame(height: PerformOverviewDashboard.rowCellHeight)
    }

    private var muteCell: some View {
        Group {
            if let muteLayer {
                PerformOverviewMuteCellLeaf(
                    phrase: phrase,
                    layer: muteLayer,
                    trackIDs: row.trackIDs,
                    isDirty: isCellDirty(muteLayer, row.trackIDs)
                ) {
                    onCycleCell(muteLayer, row.primaryTrackID, recipients)
                }
            } else {
                placeholderCell
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var monitorCell: some View {
        PerformOverviewMonitorCellLeaf(trackID: row.primaryTrackID, accent: row.accent)
            .frame(maxWidth: .infinity)
    }

    /// Audio-in rows keep the column rhythm with inert slots — fill/repeat
    /// (and pattern, pre-§4) are not playable on audio-in this slice.
    private var placeholderCell: some View {
        Text("—")
            .studioText(.labelBold)
            .foregroundStyle(StudioTheme.mutedText.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: PerformOverviewDashboard.rowCellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: StudioMetrics.borderWidth)
            )
    }

    private var partStrip: some View {
        HStack(spacing: 6) {
            Text("PARTS")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            ForEach(row.parts) { part in
                PerformOverviewPartToggleLeaf(
                    phrase: phrase,
                    layer: muteLayer,
                    part: part,
                    accent: row.accent,
                    isDirty: muteLayer.map { isCellDirty($0, [part.id]) } ?? false
                ) {
                    guard let muteLayer else { return }
                    // Part dots address ONE part — never the edit set.
                    onCycleCell(muteLayer, part.id, [part.id])
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, PerformOverviewDashboard.nameColumnWidth + 28 + 16)
    }
}

// MARK: - Leaves (the only views here that may read engine runtime state)

/// Pattern mini-grid leaf: resolves the playing pattern (playhead-dependent
/// for bar/step-varying cells) and renders a 4×4 matrix of pattern slots, the
/// active slot lit in its identity colour. Each slot is individually tappable
/// and sets THAT pattern directly via the staged perform path — no whole-cell
/// cycle (reuses the `PatternIndexCellPreview` grammar).
struct PerformOverviewPatternCellLeaf: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition
    let trackIDs: [UUID]
    let isDirty: Bool
    /// Set the pattern for this row to a specific slot index.
    let onSetIndex: (Int) -> Void

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 4
    )

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        let indices = resolvedPatternIndices
        let uniformIndex: Int? = indices.dropFirst().allSatisfy { $0 == indices.first } ? indices.first ?? nil : nil
        let activeIndex = uniformIndex
        LazyVGrid(columns: Self.columns, spacing: 2) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slot in
                slotButton(slot, isActive: slot == activeIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PerformOverviewDashboard.rowCellHeight)
        .padding(4)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(isDirty ? StudioTheme.amber : StudioTheme.border, lineWidth: isDirty ? 2 : StudioMetrics.borderWidth)
        )
        .accessibilityLabel(uniformIndex.map { "Pattern \($0 + 1)" } ?? "Mixed patterns")
    }

    private func slotButton(_ slot: Int, isActive: Bool) -> some View {
        let fill = isActive ? StudioTheme.patternColor(slot) : Color.clear
        let stroke = isActive ? StudioTheme.patternColor(slot) : StudioTheme.border.opacity(StudioOpacity.softStroke)
        return Button {
            onSetIndex(slot)
        } label: {
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                .fill(fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(stroke, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Set pattern \(slot + 1)")
        .accessibilityLabel("Set pattern \(slot + 1)")
    }

    /// One resolved index per track (kit rows aggregate members). The
    /// playhead dependency registers only when a cell actually varies.
    private var resolvedPatternIndices: [Int?] {
        let needsPlayhead = trackIDs.contains { phrase.cell(for: layer.id, trackID: $0).dependsOnPlayhead }
        let stepIndex = needsPlayhead
            ? PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex).stepIndex
            : 0
        return trackIDs.map { trackID in
            if case let .index(index) = phrase
                .resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
                .normalized(for: layer)
            {
                return index
            }
            return nil
        }
    }
}

/// Mute cell leaf: quantise-aware (slice 2) — armed mutes render the dashed
/// amber pending grammar until the bar boundary; this leaf is the only row
/// view reading the pending mirror.
struct PerformOverviewMuteCellLeaf: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition
    let trackIDs: [UUID]
    let isDirty: Bool
    let onTap: () -> Void

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        let mutedStates = resolvedMutedStates
        let mutedCount = mutedStates.filter { $0 }.count
        let isMuted = mutedCount == mutedStates.count && !mutedStates.isEmpty
        let isPartial = mutedCount > 0 && !isMuted
        let pendingTarget = trackIDs.compactMap { engineController.quantisedPendingMuteTarget(for: $0) }.first

        Button(action: onTap) {
            HStack(spacing: 5) {
                if pendingTarget != nil {
                    Image(systemName: QuantisedTogglePresentation.pendingGlyphSystemName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.amber)
                }
                Text(label(isMuted: isMuted, isPartial: isPartial, pendingTarget: pendingTarget))
                    .studioText(.labelBold)
                    .foregroundStyle(foreground(isMuted: isMuted, pendingTarget: pendingTarget))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PerformOverviewDashboard.rowCellHeight)
            .background(
                isMuted && pendingTarget == nil
                    ? TrackPerformLayerMode.mute.selectorAccent
                    : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isDirty ? StudioTheme.amber.opacity(0.95) : pendingTarget != nil ? StudioTheme.amber.opacity(0.9) : strokeColor(isMuted: isMuted, isPartial: isPartial),
                        style: QuantisedTogglePresentation.strokeStyle(
                            isPending: pendingTarget != nil,
                            lineWidth: isDirty || pendingTarget != nil || isMuted ? 2 : StudioMetrics.borderWidth
                        )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Toggle mute")
        .accessibilityLabel(accessibilityLabel(isMuted: isMuted, pendingTarget: pendingTarget))
    }

    private var resolvedMutedStates: [Bool] {
        let needsPlayhead = trackIDs.contains { phrase.cell(for: layer.id, trackID: $0).dependsOnPlayhead }
        let stepIndex = needsPlayhead
            ? PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex).stepIndex
            : 0
        return trackIDs.map { trackID in
            if case let .bool(isMuted) = phrase
                .resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
                .normalized(for: layer)
            {
                return isMuted
            }
            return false
        }
    }

    private func label(isMuted: Bool, isPartial: Bool, pendingTarget: Bool?) -> String {
        if let pendingTarget {
            return pendingTarget ? "MUTE NEXT BAR" : "UNMUTE NEXT BAR"
        }
        if isMuted {
            return "MUTED"
        }
        if isPartial {
            return "PARTIAL"
        }
        return "MUTE"
    }

    private func foreground(isMuted: Bool, pendingTarget: Bool?) -> Color {
        if pendingTarget != nil {
            return StudioTheme.amber
        }
        return isMuted ? StudioTheme.background : StudioTheme.mutedText
    }

    private func strokeColor(isMuted: Bool, isPartial: Bool) -> Color {
        if isMuted {
            return TrackPerformLayerMode.mute.selectorAccent
        }
        if isPartial {
            return TrackPerformLayerMode.mute.selectorAccent.opacity(StudioOpacity.accentStroke)
        }
        return StudioTheme.border
    }

    private func accessibilityLabel(isMuted: Bool, pendingTarget: Bool?) -> String {
        if let pendingTarget {
            return pendingTarget ? "Mute armed for next bar" : "Unmute armed for next bar"
        }
        return isMuted ? "Muted" : "Mute"
    }
}

/// Audio-in monitor readout leaf — the only row view reading audio-input
/// runtime state (capture-rate publisher; budgeted like the card badge).
struct PerformOverviewMonitorCellLeaf: View {
    @Environment(EngineController.self) private var engineController
    let trackID: UUID
    let accent: Color

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        let runtime = engineController.audioInputRuntime(for: trackID)
        let label = PerformOverviewRowModel.monitorLabel(runtime?.monitorMode)
        let suffix: String? = {
            switch runtime?.armState {
            case .recording:
                return "REC"
            case .armed:
                return "ARM"
            case .idle, .hasLoop, nil:
                return nil
            }
        }()

        HStack(spacing: 6) {
            Text(label)
                .studioText(.labelBold)
                .foregroundStyle(runtime == nil ? StudioTheme.mutedText : accent)
            if let suffix {
                Text(suffix)
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PerformOverviewDashboard.rowCellHeight)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(runtime == nil ? StudioTheme.border : accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityLabel("Monitor \(label)")
    }
}

/// Kit part on/off dot (intent §6: the kit perform facet). ON = playing,
/// OFF (outline) = muted; armed quantised changes pulse the dashed amber
/// pending ring. Mute-layer backed, so it shares the row's quantise path.
struct PerformOverviewPartToggleLeaf: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition?
    let part: PerformOverviewPartModel
    let accent: Color
    let isDirty: Bool
    let onTap: () -> Void

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        let isMuted = resolvedMuted
        let pendingTarget = engineController.quantisedPendingMuteTarget(for: part.id)
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isMuted ? Color.clear : accent)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(isMuted ? StudioTheme.border : accent, lineWidth: StudioMetrics.borderWidth))

                Text(part.name.uppercased())
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(isMuted ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                Capsule().stroke(
                    isDirty ? StudioTheme.amber.opacity(0.95) : pendingTarget != nil ? StudioTheme.amber.opacity(0.9) : StudioTheme.border.opacity(StudioOpacity.softStroke),
                    style: QuantisedTogglePresentation.strokeStyle(
                        isPending: pendingTarget != nil,
                        lineWidth: isDirty || pendingTarget != nil ? 2 : StudioMetrics.borderWidth
                    )
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute \(part.name)" : "Mute \(part.name)")
        .accessibilityLabel("\(part.name) \(isMuted ? "off" : "on")")
    }

    private var resolvedMuted: Bool {
        guard let layer else { return false }
        let cell = phrase.cell(for: layer.id, trackID: part.id)
        let stepIndex = cell.dependsOnPlayhead
            ? PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex).stepIndex
            : 0
        if case let .bool(isMuted) = phrase
            .resolvedValue(for: layer, trackID: part.id, stepIndex: stepIndex)
            .normalized(for: layer)
        {
            return isMuted
        }
        return false
    }
}

// MARK: - Macro rack

/// The macro rack strip (wireframes §9/§7 surface): the active scene's
/// macros as 4-up rotaries — the scenes-perform grammar. The full global
/// macro model is deferred; this is the rack SURFACE over today's per-scene
/// data. Assignment stays a SETUP act, so empty slots are dashed and inert.
struct PerformOverviewMacroRack: View {
    @Environment(SequencerDocumentSession.self) private var session

    var body: some View {
        let masterBus = session.store.masterBus
        let scene = masterBus.scenes.first { $0.id == masterBus.activeSceneID }
        let hasEmptySlots = (scene?.macroBindings.count ?? 0) < MasterSceneMacroBinding.slotCount

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MACRO RACK")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)

                Text(scene?.name.uppercased() ?? "NO SCENE")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                if scene == nil || hasEmptySlots {
                    Text("· ASSIGN IN SETUP")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 58), spacing: 8), count: 4),
                spacing: 10
            ) {
                ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                    PerformOverviewMacroSlotLeaf(scene: scene, slotIndex: slotIndex)
                }
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("perform-overview-macro-rack")
    }
}

/// One rack slot. Live override values are engine state — read here, in the
/// slot leaf, so knob drags never re-build the dashboard.
struct PerformOverviewMacroSlotLeaf: View {
    @Environment(EngineController.self) private var engineController
    let scene: MasterBusScene?
    let slotIndex: Int

    var body: some View {
        let macro = scene?.macroBindings.first { $0.slotIndex == slotIndex }
        MacroSlotKnob(
            slotIndex: slotIndex,
            descriptor: macro.map {
                MacroSlotKnobDescriptor(displayName: $0.name, valueRange: $0.target.valueRange)
            },
            value: macro.flatMap { resolvedValue($0) },
            accent: StudioTheme.amber,
            // The rack header carries the one "assign in setup" hint;
            // repeating it under every dashed slot is noise (ux-canon rule 1).
            emptyLabel: "",
            onAssign: nil,
            onChange: { value in
                guard let scene, let macro else { return }
                engineController.setMasterSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: value)
            }
        )
        .help(macro == nil ? "Assign macros in Setup mode (Scenes page)" : "")
    }

    private func resolvedValue(_ macro: MasterSceneMacroBinding) -> Double? {
        guard let scene else { return nil }
        let authoredValue = macro.value(in: scene) ?? macro.target.valueRange.lowerBound
        return engineController.masterSceneMacroOverride(sceneID: scene.id, macroID: macro.id) ?? authoredValue
    }
}
