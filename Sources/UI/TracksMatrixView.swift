import SwiftUI

#if DEBUG
/// Test probe for the invalidation-scope budget on the tracks page
/// (docs/audits/2026-06-12-architecture-verdict.md §2): tick-rate engine
/// publishes must re-evaluate playhead LEAF views only, never the page body.
/// Counters are bumped from view bodies (main thread) and read by
/// TracksPageInvalidationTests.
@MainActor
enum TracksPageInvalidationProbe {
    /// Whole-page body evaluations (TracksMatrixView.body — includes the
    /// StudioPanel content, which is built eagerly in init).
    static var pageBodyEvaluations = 0
    /// Per-card content evaluations (the LazyVGrid ForEach item closures —
    /// these run in the lazy container's update context, so a tick-rate read
    /// here re-builds every visible card without touching the page body).
    static var cardContentEvaluations = 0
    /// Playhead-leaf body evaluations (the only views allowed to read
    /// tick-rate transport state on this page).
    static var playheadLeafEvaluations = 0

    static func reset() {
        pageBodyEvaluations = 0
        cardContentEvaluations = 0
        playheadLeafEvaluations = 0
    }
}
#endif

enum TracksBasisPhraseResolver {
    static func resolveID(
        engineBasisPhraseID: UUID?,
        selectedPhraseID: UUID,
        phrases: [PhraseModel]
    ) -> UUID? {
        if let engineBasisPhraseID,
           phrases.contains(where: { $0.id == engineBasisPhraseID })
        {
            return engineBasisPhraseID
        }

        if phrases.contains(where: { $0.id == selectedPhraseID }) {
            return selectedPhraseID
        }

        return phrases.first?.id
    }

    static func resolvePhrase(
        engineBasisPhraseID: UUID?,
        selectedPhraseID: UUID,
        selectedPhrase: PhraseModel,
        phrases: [PhraseModel]
    ) -> PhraseModel {
        guard let resolvedID = resolveID(
            engineBasisPhraseID: engineBasisPhraseID,
            selectedPhraseID: selectedPhraseID,
            phrases: phrases
        ) else {
            return selectedPhrase
        }

        return phrases.first(where: { $0.id == resolvedID }) ?? selectedPhrase
    }
}

/// Legacy tracks-page mode vocabulary. The page itself now obeys the global
/// `WorkspaceMode` (setup ≙ edit, perform ≙ perform); this enum survives as
/// the capture-harness command/status vocabulary (`tracksMode=edit|perform`)
/// mapped onto the global mode by VisualScenarioCommandRunner.
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
    @Binding var selectedLayerID: String
    let onOpenTrack: () -> Void
    @Environment(SequencerDocumentSession.self) private var session

    var body: some View {
        // The page obeys the ONE global workspace mode (perform/setup split
        // slice 1): setup is the former edit mode, perform the former
        // perform mode. The top bar owns the switch; no local toggle.
        TracksMatrixView(
            document: $document,
            selectedLayerID: $selectedLayerID,
            isPerforming: session.workspaceMode == .perform,
            onOpenTrack: onOpenTrack
        )
        .padding(StudioMetrics.Spacing.section)
    }
}

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let isPerforming: Bool
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var isPresentingAddSliceTrack = false
    @State private var isPresentingAddDrumGroup = false
    @State private var performSelection = TrackPerformSelectionState()
    @State private var performRuntimeOverlay = TrackPerformRuntimeOverlayState()
    @State private var performLayerSelection = PerformanceLayerSelectionState()
    @State private var isPresentingPerformLayerSelection = false
    @State private var isPresentingPhraseCapture = false
    /// AC18: a linked drum kit collapses to ONE cell; an unlinked kit expands
    /// to its per-part cells (linked↔collapsed, unlinked↔expanded). The Expand
    /// affordance on a collapsed cell adds the group to this transient set,
    /// overriding collapse for display only — it never changes the link state.
    @State private var forceExpandedGroups: Set<TrackGroupID> = []

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

    /// One layer selection drives the matrix in both edit and perform; modes
    /// without a phrase layer fall back to the externally selected layer.
    private var activeMatrixLayer: PhraseLayerDefinition {
        guard let layerID = performLayerSelection.mode.phraseLayerID else {
            return selectedLayer
        }

        return session.store.layer(id: layerID) ?? selectedLayer
    }

    private var activePerformLayerLabel: String {
        performLayerSelection.activeLabel
    }

    private var editingPhrase: PhraseModel {
        let basisPhrase = TracksBasisPhraseResolver.resolvePhrase(
            engineBasisPhraseID: engineController.basisPhraseID,
            selectedPhraseID: session.store.selectedPhraseID,
            selectedPhrase: session.store.selectedPhrase,
            phrases: session.store.phrases
        )
        return session.phraseWithPerformOverlay(basisPhrase)
    }

    private var editingPhraseID: UUID {
        editingPhrase.id
    }

    /// Scoped Track/Kit Perform (AC22): when non-empty, only these track ids are
    /// shown so the reused perform surface presents a single track / one kit.
    /// Empty means unscoped (the whole project), preserving prior behaviour.
    private var performScope: Set<UUID> {
        session.performTrackScope
    }

    private func isInScope(_ trackID: UUID) -> Bool {
        performScope.isEmpty || performScope.contains(trackID)
    }

    private var groupedSections: [GroupedTrackSection] {
        session.store.trackGroups.compactMap { group in
            let members = session.store.tracksInGroup(group.id).filter { isInScope($0.id) }
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        session.store.tracks.filter { $0.groupID == nil && isInScope($0.id) }
    }

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.pageBodyEvaluations += 1 }()
        #endif
        let tracks = session.store.tracks
        let selectedTrackID = session.store.selectedTrackID
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1).
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: isPerforming ? StudioTheme.amber : StudioTheme.cyan,
                showsHeader: false
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    actionBar
                    if session.phrasePerformOverlay.isDirty {
                        performOverlayTransactionStrip
                    }

                    if tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            detail: "Create a mono, poly, slice, or drum-kit bundle to start building the matrix.",
                            accent: StudioTheme.cyan
                        )
                    } else {
                        if isPresentingPerformLayerSelection {
                            performLayerSelectionSurface
                        } else {
                            matrixSections(tracks: tracks, selectedTrackID: selectedTrackID)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(
                document: $document,
                onOpenTrack: onOpenTrack,
                onPickSliceTrack: {
                    isPresentingCreateTrack = false
                    isPresentingAddSliceTrack = true
                },
                onPickDrumGroup: {
                    isPresentingCreateTrack = false
                    isPresentingAddDrumGroup = true
                }
            )
        }
        .sheet(isPresented: $isPresentingAddSliceTrack) {
            AddSliceTrackSheet(
                library: .shared,
                sampleEngine: engineController.sampleEngineSink,
                pooledSampleIDs: Set(
                    session.store.assetPool.filter { $0.kind == .sample }.map(\.assetID)
                ),
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
                pooledKitIDs: Set(
                    session.store.assetPool.filter { $0.kind == .drumKit }.map(\.assetID)
                ),
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
        .sheet(isPresented: $isPresentingPhraseCapture) {
            PhrasePerformCaptureSheet(
                phrases: session.store.phrases,
                basisPhraseID: session.phrasePerformOverlay.basisPhraseID,
                stagedCellCount: session.phrasePerformOverlay.stagedCellCount,
                onCaptureExisting: { phraseID in
                    _ = session.capturePhrasePerformOverlay(to: phraseID)
                    isPresentingPhraseCapture = false
                },
                onCaptureNew: {
                    _ = session.capturePhrasePerformOverlayToNewPhrase()
                    isPresentingPhraseCapture = false
                },
                onCancel: {
                    isPresentingPhraseCapture = false
                }
            )
            .presentationBackground(.clear)
        }
        .onChange(of: tracks.map(\.id)) { _, trackIDs in
            performSelection.reconcile(availableTrackIDs: trackIDs)
            performRuntimeOverlay.reconcile(availableTrackIDs: trackIDs)
        }
        .onChange(of: isPerforming) { _, isNowPerforming in
            if !isNowPerforming {
                isPresentingPerformLayerSelection = false
                cleanupPerformRuntime()
                // Leaving perform also drops any scoped Track/Kit Perform set
                // (AC22) so the next entry starts unscoped (whole project).
                session.performTrackScope = []
            }
        }
        .onChange(of: performLayerSelection.mode) { oldValue, newValue in
            if oldValue == .noteRepeat, newValue != .noteRepeat {
                cleanupNoteRepeatRuntime()
            }
            performLayerSelection.reconcileVariant()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackPerformVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyTrackPerformVisualCommand(command)
        }
        .onAppear {
            // Follow a layer chosen elsewhere (Live page) when it maps to a
            // selectable mode, so both pages name the same active layer.
            if let mode = TrackPerformLayerMode.allCases.first(where: { $0.phraseLayerID == selectedLayerID }),
               performLayerSelection.mode != mode {
                performLayerSelection.select(mode, variantLabel: nil)
            }
        }
        .onDisappear {
            cleanupPerformRuntime()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            layerControl
            basisPhrasePill
            Spacer()
            if isPerforming {
                if !performScope.isEmpty {
                    performScopeChip
                }
                performSelectionSummary
                if performLayerSelection.mode != .noteRepeat {
                    performLatchModeControl
                }
            }
        }
    }

    /// Scoped Track/Kit Perform (AC22): names the active scope and lets the
    /// player drop back to the whole project without leaving perform.
    private var performScopeChip: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PERFORM SCOPE")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(performScopeText)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Button {
                session.performTrackScope = []
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                    .overlay(Circle().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perform-scope-clear")
            .help("Perform all tracks")
        }
        .frame(width: 170, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.cyan.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("perform-scope")
    }

    private var performScopeText: String {
        let scopedGroup = session.store.trackGroups.first { group in
            let memberIDs = Set(session.store.tracksInGroup(group.id).map(\.id))
            return !memberIDs.isEmpty && memberIDs == performScope
        }
        if let scopedGroup {
            return scopedGroup.name
        }
        if performScope.count == 1,
           let trackID = performScope.first,
           let track = session.store.tracks.first(where: { $0.id == trackID }) {
            return track.name
        }
        return "\(performScope.count) tracks"
    }

    // One layer changer for both modes: the perform-mode selector button is
    // the component (it opens the shared layer matrix), so edit mode no
    // longer carries a parallel chevron-cycler UI.
    private var layerControl: some View {
        performLayerControl
    }

    private var performLayerControl: some View {
        Button {
            isPresentingPerformLayerSelection = true
        } label: {
            HStack(spacing: 8) {
                // Bold-flat pass: solid accent circle with dark glyph.
                Image(systemName: performLayerSelection.mode.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 28, height: 28)
                    .background(performLayerSelection.mode.selectorAccent, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("TRACK LAYER")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)

                    Text(activePerformLayerLabel.uppercased())
                        .studioText(.labelBold)
                        .foregroundStyle(performLayerSelection.mode.selectorAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Image(systemName: isPresentingPerformLayerSelection ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 210, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(performLayerSelection.mode.selectorAccent.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("track-perform-layer-button")
        .help("Choose the Tracks performance layer")
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
        // Bold-flat pass: outline-only chip; the violet value text carries
        // the accent — no tinted wash.
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var performOverlayTransactionStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.amber)

                VStack(alignment: .leading, spacing: 2) {
                    Text("UNSAVED PERFORM EDITS")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.amber)

                    Text(performOverlayStatusText)
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                isPresentingPhraseCapture = true
            } label: {
                Text("Capture")
                    .studioText(.labelBold)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.amber)
            .disabled(!canSavePhrasePerformOverlay)
            .help(canSavePhrasePerformOverlay ? "Choose a phrase slot for the staged perform edits" : "Basis phrase is no longer available")

            Button {
                session.revertPhrasePerformOverlay()
            } label: {
                Text("Revert")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
            .help("Discard staged perform edits")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Bold-flat pass: outline-only alert strip on the ground.
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.amber, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-perform-overlay-transaction")
    }

    private var canSavePhrasePerformOverlay: Bool {
        guard let phraseID = session.phrasePerformOverlay.basisPhraseID else {
            return false
        }
        return session.store.phrases.contains(where: { $0.id == phraseID })
    }

    private var performOverlayStatusText: String {
        let count = session.phrasePerformOverlay.stagedCellCount
        let phraseName = session.phrasePerformOverlay.basisPhraseID
            .flatMap { phraseID in session.store.phrases.first(where: { $0.id == phraseID })?.name }
            ?? "missing phrase"
        return "\(count) edit\(count == 1 ? "" : "s") on \(phraseName)"
    }

    private var performSelectionSummary: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EDIT SET")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(performSelectionSummaryText)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if !performSelection.isEmpty {
                Button {
                    performSelection.clear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                }
                .buttonStyle(.plain)
                .help("Clear edit set")
            }
        }
        .frame(width: 150, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // Bold-flat pass: outline-only chip; the amber value text carries
        // the accent — no tinted wash.
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var performSelectionSummaryText: String {
        let selectedTracks = session.store.tracks.filter { performSelection.contains($0.id) }
        guard !selectedTracks.isEmpty else {
            return "None selected"
        }

        let names = selectedTracks.prefix(2).map(\.name).joined(separator: ", ")
        if selectedTracks.count <= 2 {
            return "\(selectedTracks.count): \(names)"
        }
        return "\(selectedTracks.count): \(names) +\(selectedTracks.count - 2)"
    }

    private var performLatchModeControl: some View {
        TrackPerformLatchModePicker(selection: $performRuntimeOverlay.latchMode)
    }

    private var performLayerSelectionSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("CHOOSE TRACK LAYER")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)

                Spacer(minLength: 8)

                Button {
                    isPresentingPerformLayerSelection = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                }
                .buttonStyle(.plain)
                .help("Return to track cards")
            }

            LazyVGrid(columns: performLayerSelectionColumns, alignment: .leading, spacing: 10) {
                ForEach(PerformanceLayerOption.all) { option in
                    PerformanceLayerOptionCell(
                        option: option,
                        isSelected: performLayerSelection.mode == option.mode
                            && performLayerSelection.variantLabel == option.variantLabel
                    ) {
                        choosePerformLayer(option)
                    }
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        // Bold-flat pass: the selector sits on the ground behind a solid
        // amber outline — no tinted wash.
        .background(StudioTheme.background, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(StudioTheme.amber, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("track-perform-layer-selection-surface")
    }

    private var performLayerSelectionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 84, maximum: 190), spacing: 10), count: 8)
    }

    private func choosePerformLayer(_ option: PerformanceLayerOption) {
        let isAlreadySelected = performLayerSelection.mode == option.mode
            && performLayerSelection.variantLabel == option.variantLabel
        if isAlreadySelected, option.variantLabel != nil {
            // Variant cells toggle: off returns to normal pattern playback.
            performLayerSelection.select(.pattern, variantLabel: nil)
        } else {
            performLayerSelection.select(option.mode, variantLabel: option.variantLabel)
        }
        syncSelectedLayerIDToPerformSelection()
        isPresentingPerformLayerSelection = false
    }

    /// Idempotent variant used by visual automation commands: always selects,
    /// never toggles off.
    private func setPerformLayer(_ mode: TrackPerformLayerMode, variantLabel: String?) {
        performLayerSelection.select(mode, variantLabel: variantLabel)
        syncSelectedLayerIDToPerformSelection()
        isPresentingPerformLayerSelection = false
    }

    /// Keeps the externally shared layer binding (Live page) following the
    /// matrix selection whenever the chosen mode maps to a phrase layer.
    private func syncSelectedLayerIDToPerformSelection() {
        if let layerID = performLayerSelection.mode.phraseLayerID,
           session.store.layer(id: layerID) != nil {
            selectedLayerID = layerID
        }
    }

    private var performOverviewDashboard: some View {
        PerformOverviewDashboard(
            phrase: editingPhrase,
            rows: PerformOverviewRowModel.rows(
                tracks: session.store.tracks,
                groups: session.store.trackGroups
            ),
            muteLayer: TrackPerformLayerMode.mute.phraseLayerID.flatMap { session.store.layer(id: $0) },
            patternLayer: session.store.patternLayer,
            activeLayerMode: performLayerSelection.mode,
            activeVariantLabel: performLayerSelection.variantLabel,
            latchMode: performRuntimeOverlay.latchMode,
            selection: performSelection,
            selectedTrackID: session.store.selectedTrackID,
            orderedTrackIDs: session.store.tracks.map(\.id),
            runtimeControlState: { trackIDs, control in
                runtimeControlState(forRow: trackIDs, control: control)
            },
            isCellDirty: { layer, trackIDs in
                trackIDs.contains { trackID in
                    session.performOverlayCell(phraseID: editingPhraseID, layerID: layer.id, trackID: trackID) != nil
                }
            },
            isQuantiseCueLive: session.isQuantisedPerformToggleArmingActive,
            onSelectRow: { trackID in
                session.setSelectedTrackID(trackID)
            },
            onToggleRowSelection: { trackIDs in
                toggleRowPerformSelection(trackIDs)
            },
            onCycleCell: { layer, sourceTrackID, recipientTrackIDs in
                session.setSelectedTrackID(sourceTrackID)
                performCycleTap(
                    layer: layer,
                    sourceTrackID: sourceTrackID,
                    recipientTrackIDs: recipientTrackIDs
                )
            },
            onActivateRuntimeControl: { control, sourceTrackID, recipientTrackIDs in
                session.setSelectedTrackID(sourceTrackID)
                activateRuntimeControl(
                    control,
                    sourceTrackID: sourceTrackID,
                    recipientTrackIDs: recipientTrackIDs
                )
            },
            onReleaseRuntimeControl: { control, sourceTrackID in
                releaseRuntimeControl(control, sourceTrackID: sourceTrackID)
            },
            onCueRuntimeControl: session.isQuantisedPerformToggleArmingActive
                ? { control, sourceTrackID, recipientTrackIDs in
                    cueRuntimeControl(
                        control,
                        sourceTrackID: sourceTrackID,
                        recipientTrackIDs: recipientTrackIDs
                    )
                }
                : nil
        )
    }

    /// Row edit-set toggle: a kit row joins/leaves the set as one unit (all
    /// member parts together).
    private func toggleRowPerformSelection(_ trackIDs: [UUID]) {
        let allSelected = trackIDs.allSatisfy { performSelection.contains($0) }
        for trackID in trackIDs {
            if allSelected {
                performSelection.remove(trackID)
            } else {
                performSelection.add(trackID)
            }
        }
    }

    /// Row-aggregated overlay control state (kit rows fold their members):
    /// page-owned gesture/overlay state only — engine-side repeat activity
    /// stays in the runtime-control leaf.
    private func runtimeControlState(forRow trackIDs: [UUID], control: TrackPerformBinaryControl) -> TrackPerformRuntimeControlState {
        let isAvailable = control == .noteRepeat
            ? trackIDs.contains { session.isNoteRepeatAvailable(trackID: $0) }
            : true
        return TrackPerformRuntimeControlState(
            control: control,
            isAvailable: isAvailable,
            isActive: trackIDs.contains { performRuntimeOverlay.isActive(control, trackID: $0) },
            isLatched: trackIDs.contains { performRuntimeOverlay.isLatched(control, trackID: $0) },
            isMomentaryPressed: trackIDs.contains { performRuntimeOverlay.isMomentaryPressed(control, trackID: $0) }
        )
    }

    private func matrixSections(tracks: [StepSequenceTrack], selectedTrackID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !ungroupedTracks.isEmpty {
                tracksGrid(ungroupedTracks, group: nil, selectedTrackID: selectedTrackID)
            }

            ForEach(groupedSections) { section in
                let isCollapsed = isGroupCollapsed(section.group)
                GroupSectionView(
                    section: section,
                    isCollapsed: isCollapsed,
                    onCollapse: isCollapsed ? nil : { collapseGroup(section.group) },
                    grid: {
                        if isCollapsed {
                            collapsedKitCell(section: section, selectedTrackID: selectedTrackID)
                        } else {
                            tracksGrid(section.members, group: section.group, selectedTrackID: selectedTrackID)
                        }
                    }
                )
            }
        }
    }

    /// A linked kit collapses to one cell unless the user has transiently
    /// forced it expanded via the Expand affordance (AC18). An unlinked kit is
    /// always expanded to its per-part cells.
    private func isGroupCollapsed(_ group: TrackGroup) -> Bool {
        group.isPatternLinked && !forceExpandedGroups.contains(group.id)
    }

    private func expandGroup(_ group: TrackGroup) {
        forceExpandedGroups.insert(group.id)
    }

    private func collapseGroup(_ group: TrackGroup) {
        forceExpandedGroups.remove(group.id)
    }

    @ViewBuilder
    private func collapsedKitCell(section: GroupedTrackSection, selectedTrackID: UUID) -> some View {
        let representativeTrackID = section.members.first?.id
        let isFocused = representativeTrackID.map { id in section.members.contains { $0.id == id && $0.id == selectedTrackID } } ?? false
        LazyVGrid(columns: columns, spacing: 14) {
            CollapsedKitCell(
                group: section.group,
                memberCount: section.members.count,
                patternSlotLabel: collapsedKitPatternSlotLabel(section),
                destinationLabel: section.group.sharedDestination?.summary ?? "Own bus",
                isFocused: section.members.contains { $0.id == selectedTrackID },
                onOpenKit: {
                    if let representativeTrackID {
                        session.setSelectedTrackID(representativeTrackID)
                        if !isPerforming {
                            onOpenTrack()
                        }
                    }
                },
                onExpand: { expandGroup(section.group) }
            )
        }
    }

    /// The kit's representative pattern slot: when linked all parts share one
    /// slot, so the first member's selected slot stands for the whole kit.
    private func collapsedKitPatternSlotLabel(_ section: GroupedTrackSection) -> String {
        guard let firstMemberID = section.members.first?.id else {
            return "P1"
        }
        return "P\(session.store.selectedPatternIndex(for: firstMemberID) + 1)"
    }

    @ViewBuilder
    private func tracksGrid(_ tracks: [StepSequenceTrack], group: TrackGroup?, selectedTrackID: UUID) -> some View {
        let layer = activeMatrixLayer
        // The selected layer mode drives the cards in both modes; runtime
        // trigger surfaces stay perform-only via runtimeControlState below.
        let activePerformLayer: TrackPerformLayerMode? = performLayerSelection.mode
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                #if DEBUG
                let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                #endif
                // Card inputs are document/selection state only. Anything
                // that varies at tick/meter rate (playhead-resolved values,
                // audio-input runtime, engine repeat activity) is read by
                // leaf views INSIDE the card, so a transport tick never
                // re-builds the cards (architecture verdict §2).
                let cell = editingPhrase.cell(for: layer.id, trackID: track.id)
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: session.store.selectedPatternIndex(for: track.id),
                    phrase: editingPhrase,
                    layer: layer,
                    activePerformLayer: activePerformLayer,
                    activePerformVariantLabel: performLayerSelection.variantLabel,
                    cell: cell,
                    isDirty: session.performOverlayCell(
                        phraseID: editingPhraseID,
                        layerID: layer.id,
                        trackID: track.id
                    ) != nil,
                    isFocused: track.id == selectedTrackID,
                    isPerformSelected: performSelection.contains(track.id),
                    isPerforming: isPerforming,
                    latchMode: performRuntimeOverlay.latchMode,
                    runtimeControlState: isPerforming
                        ? activePerformLayer?.binaryControl.map {
                            runtimeControlState(for: track.id, control: $0)
                        }
                        : nil,
                    onTogglePerformSelection: {
                        performSelection.toggle(track.id)
                    },
                    onActivateRuntimeControl: { control in
                        session.setSelectedTrackID(track.id)
                        activateRuntimeControl(control, sourceTrackID: track.id)
                    },
                    onReleaseRuntimeControl: { control in
                        releaseRuntimeControl(control, sourceTrackID: track.id)
                    },
                    onCueRuntimeControl: session.isQuantisedPerformToggleArmingActive
                        ? { control in cueRuntimeControl(control, sourceTrackID: track.id) }
                        : nil
                ) {
                    session.setSelectedTrackID(track.id)
                    if isPerforming {
                        performPrimaryAction(trackID: track.id)
                    } else {
                        onOpenTrack()
                    }
                }
            }

            if group == nil, !isPerforming {
                addTrackCard
            }
        }
    }

    // Same footprint as TrackMatrixCard (minHeight 210 + comfortable padding)
    // so the add cell sits flush in the grid (ux-canon rule 5); the "+" alone
    // carries the affordance, with the action named in help/accessibility.
    private var addTrackCard: some View {
        StudioAddCard(label: "", minHeight: 210, help: "Add a track") {
            isPresentingCreateTrack = true
        }
    }

    /// Overlay-derived control state only (page-owned gesture state).
    /// Engine-side repeat activity is read by the runtime-control LEAF —
    /// the page must not observe engine runtime state per card.
    private func runtimeControlState(for trackID: UUID, control: TrackPerformBinaryControl) -> TrackPerformRuntimeControlState {
        let isAvailable = control == .noteRepeat ? session.isNoteRepeatAvailable(trackID: trackID) : true
        return TrackPerformRuntimeControlState(
            control: control,
            isAvailable: isAvailable,
            isActive: performRuntimeOverlay.isActive(control, trackID: trackID),
            isLatched: performRuntimeOverlay.isLatched(control, trackID: trackID),
            isMomentaryPressed: performRuntimeOverlay.isMomentaryPressed(control, trackID: trackID)
        )
    }

    private var currentStepIndexInPhrase: Int {
        PhrasePlayhead(phrase: editingPhrase, transportTickIndex: engineController.transportTickIndex).stepIndex
    }

    private var currentBarIndexInPhrase: Int {
        PhrasePlayhead(phrase: editingPhrase, transportTickIndex: engineController.transportTickIndex).barIndex
    }

    private func performPrimaryAction(trackID: UUID) {
        if isPerforming, let control = performLayerSelection.mode.binaryControl {
            if performRuntimeOverlay.latchMode == .latched {
                activateRuntimeControl(control, sourceTrackID: trackID)
            }
            return
        }

        let recipientTrackIDs = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: trackID,
            orderedTrackIDs: session.store.tracks.map(\.id),
            selection: performSelection
        )
        performCycleTap(
            layer: activeMatrixLayer,
            sourceTrackID: trackID,
            recipientTrackIDs: recipientTrackIDs
        )
    }

    /// One perform tap on a phrase-layer cell (pattern/mute rows, legacy
    /// card taps): cycles the source track's value and stages it across the
    /// recipients — except quantise-armed mutes, which ARM for the next bar
    /// instead (slice 2 grammar).
    private func performCycleTap(
        layer: PhraseLayerDefinition,
        sourceTrackID: UUID,
        recipientTrackIDs: [UUID]
    ) {
        let address = phraseCellAddress(for: sourceTrackID, layerID: layer.id)
        let cell = editingPhrase.cell(at: address)

        // Quantised perform toggles (slice 2): with Q:BAR and the transport
        // running, a mute tap ARMS for the next bar boundary instead of
        // landing immediately; tapping again while armed cancels. Q:OFF (or
        // transport stopped) falls through to the immediate staging below —
        // exactly today's behaviour.
        if layer.id == TrackPerformLayerMode.mute.phraseLayerID,
           session.isQuantisedPerformToggleArmingActive {
            session.toggleQuantisedMute(
                trackIDs: recipientTrackIDs,
                basisPhrase: editingPhrase,
                layer: layer,
                stepIndex: currentStepIndexInPhrase
            )
            return
        }

        switch cell {
        case .inheritDefault:
            let seedValue = editingPhrase.resolvedValue(for: layer, at: address)
            session.stagePhrasePerformCell(
                .single(cycledValue(seedValue, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .single(value):
            session.stagePhrasePerformCell(
                .single(cycledValue(value, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .bars(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentBarIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: layer)
            session.stagePhrasePerformCell(
                .bars(nextValues),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case let .steps(values):
            guard !values.isEmpty else { return }
            var nextValues = values
            let index = min(currentStepIndexInPhrase, nextValues.count - 1)
            nextValues[index] = cycledValue(nextValues[index], for: layer)
            session.stagePhrasePerformCell(
                .steps(nextValues),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        case .curve:
            let seedValue = editingPhrase.resolvedValue(for: layer, at: address)
            session.stagePhrasePerformCell(
                .single(cycledValue(seedValue, for: layer)),
                layerID: layer.id,
                trackIDs: recipientTrackIDs,
                basisPhraseID: editingPhraseID
            )
        }
    }

    private func phraseCellAddress(for trackID: UUID, layerID: String) -> PhraseCellAddress {
        PhraseCellAddress(
            phraseID: editingPhraseID,
            layerID: layerID,
            trackID: trackID,
            stepIndex: currentStepIndexInPhrase
        )
    }

    /// `recipientTrackIDs` nil = the card/legacy path (edit-set fanout from
    /// the source); the overview rows pass their own recipients (kit rows
    /// fan out to members).
    private func activateRuntimeControl(
        _ control: TrackPerformBinaryControl,
        sourceTrackID: UUID,
        recipientTrackIDs: [UUID]? = nil
    ) {
        let recipientTrackIDs = recipientTrackIDs ?? TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: session.store.tracks.map(\.id),
            selection: performSelection
        )

        switch control {
        case .fill:
            performRuntimeOverlay.activate(
                control: control,
                sourceTrackID: sourceTrackID,
                recipientTrackIDs: recipientTrackIDs
            )
        case .noteRepeat:
            let supportedTrackIDs = recipientTrackIDs.filter { session.isNoteRepeatAvailable(trackID: $0) }
            guard !supportedTrackIDs.isEmpty else {
                return
            }

            // The layer header's variant (e.g. "NOTE REPEAT - 1/8") is the
            // rate; engagement writes it to the track so the engine captures it.
            if let variant = performLayerSelection.variantLabel,
               let interval = NoteRepeatInterval(rawValue: variant) {
                for trackID in supportedTrackIDs
                where session.store.tracks.first(where: { $0.id == trackID })?.noteRepeatInterval != interval {
                    session.setTrackNoteRepeatInterval(interval, trackID: trackID)
                }
            }

            let latchedBefore = Set(supportedTrackIDs.filter { performRuntimeOverlay.isLatched(control, trackID: $0) })
            performRuntimeOverlay.activate(
                control: control,
                sourceTrackID: sourceTrackID,
                recipientTrackIDs: supportedTrackIDs
            )
            if performRuntimeOverlay.latchMode == .latched {
                for trackID in supportedTrackIDs {
                    let latchedNow = performRuntimeOverlay.isLatched(control, trackID: trackID)
                    if latchedNow, !latchedBefore.contains(trackID) {
                        session.engageNoteRepeat(trackID: trackID)
                    } else if !latchedNow, latchedBefore.contains(trackID) {
                        session.releaseNoteRepeat(trackID: trackID)
                    }
                }
            } else {
                supportedTrackIDs.forEach { session.engageNoteRepeat(trackID: $0) }
            }
        }
    }

    /// Fill's quantised next-cycle cue (rytm-study §5, third gesture): a
    /// plain tap in MOM mode with Q:BAR arms fill for the next bar across
    /// the edit set; tapping while armed cancels. Note repeat keeps its
    /// existing gestures — cue quantise for repeat is a later slice.
    private func cueRuntimeControl(
        _ control: TrackPerformBinaryControl,
        sourceTrackID: UUID,
        recipientTrackIDs: [UUID]? = nil
    ) {
        guard control == .fill else {
            return
        }
        let recipientTrackIDs = recipientTrackIDs ?? TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: session.store.tracks.map(\.id),
            selection: performSelection
        )
        session.toggleQuantisedFillCue(trackIDs: recipientTrackIDs)
    }

    private func releaseRuntimeControl(_ control: TrackPerformBinaryControl, sourceTrackID: UUID) {
        if control == .noteRepeat {
            let activeTrackIDs = performRuntimeOverlay.momentaryRecipientTrackIDs(
                control: control,
                sourceTrackID: sourceTrackID
            )
            activeTrackIDs.forEach { session.releaseNoteRepeat(trackID: $0) }
        }
        performRuntimeOverlay.releaseMomentary(control: control, sourceTrackID: sourceTrackID)
    }

    private func cleanupPerformRuntime() {
        cleanupNoteRepeatRuntime()
        performSelection.clear()
        performRuntimeOverlay.cleanupRuntime()
    }

    private func cleanupNoteRepeatRuntime() {
        let overlayActiveTrackIDs = performRuntimeOverlay
            .activeTrackIDs(.noteRepeat, orderedTrackIDs: session.store.tracks.map(\.id))
        let engineActiveTrackIDs = session.store.tracks.compactMap { track in
            engineController.noteRepeatRuntimeSnapshot(for: track.id) == nil ? nil : track.id
        }
        let activeTrackIDs = Array(Set(overlayActiveTrackIDs + engineActiveTrackIDs))
        activeTrackIDs.forEach { session.releaseNoteRepeat(trackID: $0) }
        performRuntimeOverlay.clearRuntime(control: .noteRepeat, trackIDs: activeTrackIDs)
        performRuntimeOverlay.releaseAllMomentary(control: .noteRepeat)
    }

    private func applyTrackPerformVisualCommand(_ command: String) {
        if command == "open-layer-selector" {
            isPresentingPerformLayerSelection = true
            return
        }

        if command == "close-layer-selector" {
            isPresentingPerformLayerSelection = false
            return
        }

        if command == "open-phrase-capture" {
            isPresentingPhraseCapture = session.phrasePerformOverlay.hasLiveCopy
            return
        }

        if command == "close-phrase-capture" {
            isPresentingPhraseCapture = false
            return
        }

        if let rawMode = command.removingPrefix("select-layer:"),
           let mode = TrackPerformLayerMode(rawValue: rawMode) {
            setPerformLayer(mode, variantLabel: nil)
            return
        }

        if let rawSelection = command.removingPrefix("select-variant:") {
            let parts = rawSelection.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let mode = TrackPerformLayerMode(rawValue: parts[0])
            else { return }
            setPerformLayer(mode, variantLabel: parts[1])
            return
        }

        if let rawMode = command.removingPrefix("layer:"),
           let mode = TrackPerformLayerMode(rawValue: rawMode) {
            setPerformLayer(mode, variantLabel: nil)
            return
        }

        if let rawTrackID = command.removingPrefix("press:"),
           let trackID = UUID(uuidString: rawTrackID) {
            performLayerSelection.select(.noteRepeat, variantLabel: performLayerSelection.variantLabel)
            activateRuntimeControl(.noteRepeat, sourceTrackID: trackID)
            return
        }

        if let rawTrackID = command.removingPrefix("release:"),
           let trackID = UUID(uuidString: rawTrackID) {
            releaseRuntimeControl(.noteRepeat, sourceTrackID: trackID)
            return
        }

        if command == "clear-note-repeat" {
            cleanupNoteRepeatRuntime()
            performRuntimeOverlay.releaseAllMomentary(control: .noteRepeat)
        }
    }

}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

private struct GroupSectionView<Grid: View>: View {
    let section: GroupedTrackSection
    /// AC18: true when the linked kit is showing its single collapsed cell.
    var isCollapsed: Bool = false
    /// Non-nil only when expanded AND the kit is linked, so the user can fold
    /// the per-part cells back to one cell without changing the link state.
    var onCollapse: (() -> Void)? = nil
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
                            .background(accent, in: Capsule())
                            .foregroundStyle(StudioTheme.background)

                        if section.group.isPatternLinked {
                            Text("LINKED")
                                .studioText(.micro)
                                .tracking(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(Capsule().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                                .foregroundStyle(accent)
                        }
                    }

                    Text(section.group.sharedDestination?.summary ?? "Shared destination not assigned")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let onCollapse {
                    Button(action: onCollapse) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 10, weight: .bold))
                            Text("COLLAPSE")
                                .studioText(.micro)
                                .tracking(0.8)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kit-collapse")
                    .help("Collapse \(section.group.name) back to one cell")
                }
            }

            grid
        }
        .padding(StudioMetrics.Spacing.roomy)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
    }
}

/// AC18: the single cell a LINKED drum kit collapses to in the track/perform
/// matrix. Tapping the body opens the kit matrix (kit-first, same as selecting
/// a member); the Expand control is a separate affordance that reveals the
/// per-part cells without changing the link state. Styled to match
/// `TrackMatrixCard` (same minHeight + outline grammar).
private struct CollapsedKitCell: View {
    let group: TrackGroup
    let memberCount: Int
    let patternSlotLabel: String
    let destinationLabel: String
    let isFocused: Bool
    let onOpenKit: () -> Void
    let onExpand: () -> Void

    private var accent: Color {
        Color(hex: group.color) ?? StudioTheme.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 28, height: 28)
                    .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 6) {
                        Text("KIT")
                        Text("\(memberCount) PARTS")
                        Text(patternSlotLabel)
                    }
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }

            Text(destinationLabel.uppercased())
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
                )
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onExpand) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text("Expand")
                        .studioText(.labelBold)
                }
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kit-expand")
            .help("Expand \(group.name) to its per-part cells")
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(Color.white.opacity(StudioOpacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    isFocused ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border,
                    lineWidth: isFocused ? 2 : StudioMetrics.borderWidth
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture(perform: onOpenKit)
        .accessibilityIdentifier("kit-collapsed-cell")
    }
}

struct TrackPerformRuntimeControlState: Equatable, Identifiable {
    let control: TrackPerformBinaryControl
    let isAvailable: Bool
    let isActive: Bool
    let isLatched: Bool
    let isMomentaryPressed: Bool

    var id: TrackPerformBinaryControl { control }
}

private struct TrackPerformPlaceholderLayerCard: View {
    let mode: TrackPerformLayerMode
    let variantLabel: String?
    let accent: Color

    private var title: String {
        let suffix = variantLabel.map { " \($0)" } ?? ""
        return "\(mode.compactLabel)\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 28, height: 28)
                    .background(accent, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("SELECTED LAYER")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Text(placeholderDetail)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var placeholderDetail: String {
        switch mode {
        case .stepOrder:
            return "Map selection is visible here; map authoring remains outside this perform slice."
        case .pan:
            return "Pan is selected for the matrix; live pan controls are not wired in this slice."
        case .mute, .pattern, .fill, .noteRepeat, .volume:
            return "\(mode.label) is selected."
        }
    }
}

struct PhrasePerformCaptureSheet: View {
    let phrases: [PhraseModel]
    let basisPhraseID: UUID?
    let stagedCellCount: Int
    let onCaptureExisting: (UUID) -> Void
    let onCaptureNew: () -> Void
    let onCancel: () -> Void

    private enum Slot: Identifiable {
        case phrase(PhraseModel)
        case new
        case empty(Int)

        var id: String {
            switch self {
            case .phrase(let phrase):
                return phrase.id.uuidString
            case .new:
                return "new"
            case .empty(let index):
                return "empty-\(index)"
            }
        }
    }

    private var slots: [Slot] {
        var result = phrases.prefix(15).map(Slot.phrase)
        result.append(.new)
        while result.count < 16 {
            result.append(.empty(result.count))
        }
        return result
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(104), spacing: 10), count: 4)
    }

    private var basisName: String {
        basisPhraseID.flatMap { basisID in
            phrases.first(where: { $0.id == basisID })?.name
        } ?? "missing phrase"
    }

    var body: some View {
        StudioModal(
            title: "Save Phrase Copy",
            subtitle: "\(stagedCellCount) change\(stagedCellCount == 1 ? "" : "s") on \(basisName)",
            accent: StudioTheme.amber,
            minWidth: 500,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose where in the phrase matrix this live phrase copy should be saved.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(slots) { slot in
                        slotView(slot)
                    }
                }
            }
        }
        .accessibilityIdentifier("phrase-perform-capture-sheet")
        .onAppear {
            NotificationCenter.default.post(
                name: .trackPerformCaptureRenderedVisualState,
                object: nil,
                userInfo: ["visible": true]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: .trackPerformCaptureRenderedVisualState,
                object: nil,
                userInfo: ["visible": false]
            )
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Slot) -> some View {
        switch slot {
        case .phrase(let phrase):
            Button {
                onCaptureExisting(phrase.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.name)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(phrase.id == basisPhraseID ? "basis" : "\(phrase.lengthBars) bars")
                        .studioText(.micro)
                        .foregroundStyle(phrase.id == basisPhraseID ? StudioTheme.amber : StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(phrase.id == basisPhraseID ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .help("Capture edits to \(phrase.name)")

        case .new:
            Button(action: onCaptureNew) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("+ New")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.background)

                    Text("phrase")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.background.opacity(0.82))
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(.horizontal, 10)
                .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Create a new phrase from these edits")

        case .empty:
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 5]))
                .frame(minHeight: 58)
                .accessibilityHidden(true)
        }
    }
}

private struct TrackPerformLatchModePicker: View {
    @Binding var selection: TrackPerformLatchMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrackPerformLatchMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .bold))

                        Text(mode.actionBarLabel)
                            .studioText(.micro)
                            .tracking(0.8)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == mode ? StudioTheme.background : StudioTheme.text.opacity(0.68))
                    .frame(width: 74, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .fill(selection == mode ? StudioTheme.amber : StudioTheme.inset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(selection == mode ? Color.clear : Color.white.opacity(StudioOpacity.borderFaint), lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.label))
                .accessibilityHint(Text(mode.helpText))
                .help(mode.helpText)
            }
        }
        .padding(3)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("track-perform-latch-mode")
        .help("Runtime Fill and Repeat mode")
    }
}

private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
    let patternIndex: Int
    /// The phrase the leaves resolve against. The card itself never reads
    /// the playhead — bar/step/curve cells resolve in
    /// `TrackCardCellPreviewLeaf` / `TrackCardStrokeOverlay` so tick-rate
    /// invalidation stops at those leaves.
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition
    let activePerformLayer: TrackPerformLayerMode?
    let activePerformVariantLabel: String?
    let cell: PhraseCell
    let isDirty: Bool
    let isFocused: Bool
    let isPerformSelected: Bool
    let isPerforming: Bool
    let latchMode: TrackPerformLatchMode
    let runtimeControlState: TrackPerformRuntimeControlState?
    let onTogglePerformSelection: () -> Void
    let onActivateRuntimeControl: (TrackPerformBinaryControl) -> Void
    let onReleaseRuntimeControl: (TrackPerformBinaryControl) -> Void
    /// Non-nil when quantise arming is live: a plain tap on a runtime
    /// trigger surface arms the next-bar cue instead of being a zero-length
    /// hold. MOM (hold) and LATCH interactions are unchanged.
    let onCueRuntimeControl: ((TrackPerformBinaryControl) -> Void)?
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
        case .audioInput:
            return StudioTheme.success
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
        if let activePerformLayer {
            return activePerformLayer.selectorAccent
        }
        return layerAccent(layer.id)
    }

    /// True only when the card renders a live trigger surface (perform mode
    /// with a runtime layer); in edit mode the whole card stays tappable.
    private var isRuntimeLayerCard: Bool {
        runtimeControlState != nil && activePerformLayer?.binaryControl != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TrackTypeBadge(trackType: track.trackType, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .studioText(.subtitle)
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

                if track.trackType == .audioInput {
                    AudioInputRuntimeBadge(trackID: track.id, accent: accent)
                }

                if isPerforming {
                    Button(action: onTogglePerformSelection) {
                        Image(systemName: isPerformSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isPerformSelected ? StudioTheme.amber : StudioTheme.mutedText)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                            .overlay(Circle().stroke(isPerformSelected ? StudioTheme.amber.opacity(0.7) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .help(isPerformSelected ? "Remove from edit set" : "Add to edit set")
                }
            }

            if let group {
                // Bold-flat pass: outline-only chip with accent text.
                Text(group.name.uppercased())
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule()
                            .stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth)
                    )
                    .lineLimit(1)
            }

            activeLayerContent
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            TrackCardStrokeOverlay(
                phrase: phrase,
                layer: layer,
                trackID: track.id,
                cell: cell,
                isDirty: isDirty,
                isFocused: isFocused,
                isPerformSelected: isPerformSelected,
                isPerforming: isPerforming,
                focusAccent: accent,
                layerAccentColor: layerAccentColor
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            if !isRuntimeLayerCard {
                onTap()
            }
        }
    }

    @ViewBuilder
    private var activeLayerContent: some View {
        if let activePerformLayer,
           let runtimeControlState,
           let control = activePerformLayer.binaryControl {
            TrackPerformRuntimeLayerControl(
                mode: activePerformLayer,
                trackIDs: [track.id],
                state: runtimeControlState,
                latchMode: latchMode,
                accent: layerAccentColor,
                onActivate: { onActivateRuntimeControl(control) },
                onRelease: { onReleaseRuntimeControl(control) },
                onCue: control == .fill
                    ? onCueRuntimeControl.map { cueHandler in { cueHandler(control) } }
                    : nil
            )
        } else if let activePerformLayer, activePerformLayer.phraseLayerID == nil {
            TrackPerformPlaceholderLayerCard(
                mode: activePerformLayer,
                variantLabel: activePerformVariantLabel,
                accent: layerAccentColor
            )
        } else {
            // The action-bar layer control already names the active layer, the
            // edit-set chrome already marks linked cards, and inherit/single
            // shows as a muted variant — no per-card chips (ux-canon rule 1).
            TrackCardCellPreviewLeaf(
                phrase: phrase,
                layer: layer,
                trackID: track.id,
                cell: cell,
                accent: layerAccentColor,
                contentOpacity: layerContentOpacity
            )
        }
    }

    private var layerContentOpacity: Double {
        if cell.editMode == .inheritDefault {
            return StudioOpacity.inheritedContent
        }
        return isPerforming ? 1 : 0.82
    }

    /// Colour identifies, it never floods (ux-canon rule 12): the card body is
    /// always the neutral step above ground; state/identity lives in the
    /// outline (`TrackCardStrokeOverlay`) and the solid pattern chip.
    private var cardFill: Color {
        Color.white.opacity(StudioOpacity.subtleFill)
    }
}

extension PhraseCell {
    /// True when the rendered value varies with the transport step. Only
    /// these cells' leaves may register a dependency on the tick-rate
    /// transport mirror; single/inherit cells resolve statically.
    var dependsOnPlayhead: Bool {
        switch self {
        case .bars, .steps, .curve:
            return true
        case .single, .inheritDefault:
            return false
        }
    }
}

/// The cell-content leaf — with the stroke overlay, the only tracks-page
/// views allowed to read the transport playhead. Bar/step/curve cells
/// re-resolve when `transportTickIndex` publishes; single/inherit cells
/// never register the dependency. `PhraseCellPreview` sits behind an
/// Equatable guard so per-tick re-evaluations that resolve to the same
/// value stop here (the meter-bank displayState dedupe shape).
private struct TrackCardCellPreviewLeaf: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition
    let trackID: UUID
    let cell: PhraseCell
    let accent: Color
    let contentOpacity: Double

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        let resolvedValue = phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: playheadStepIndex)
        PhraseCellPreview(
            layer: layer,
            cell: cell,
            resolvedValue: resolvedValue,
            accent: accent,
            summary: valueLabel(resolvedValue, layer: layer),
            metrics: .matrix
        )
        .equatable()
        .opacity(contentOpacity)
    }

    private var playheadStepIndex: Int {
        guard cell.dependsOnPlayhead else {
            return 0
        }
        return PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex).stepIndex
    }
}

/// Card outline leaf. In perform mode with the pattern layer the stroke
/// takes the playing pattern's identity colour, which for bar/step-varying
/// cells follows the playhead — so the stroke (not the whole card) owns
/// that tick-rate read. In edit mode it reads no engine state at all.
private struct TrackCardStrokeOverlay: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel
    let layer: PhraseLayerDefinition
    let trackID: UUID
    let cell: PhraseCell
    let isDirty: Bool
    let isFocused: Bool
    let isPerformSelected: Bool
    let isPerforming: Bool
    let focusAccent: Color
    let layerAccentColor: Color

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        // Armed quantised mute (wireframes §2): dashed amber outline + the
        // pending glyph until the change lands at the bar boundary. The
        // pending mirror publishes at gesture/bar rate (never tick rate),
        // and only this leaf reads it.
        let pendingMuteTarget = isPerforming && layer.id == TrackPerformLayerMode.mute.phraseLayerID
            ? engineController.quantisedPendingMuteTarget(for: trackID)
            : nil
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    pendingMuteTarget != nil ? StudioTheme.amber.opacity(0.9) : strokeColor,
                    style: QuantisedTogglePresentation.strokeStyle(
                        isPending: pendingMuteTarget != nil,
                        lineWidth: isFocused || isPerformSelected || isPerforming || isDirty ? 2 : StudioMetrics.borderWidth
                    )
                )
            if let pendingMuteTarget {
                HStack(spacing: 4) {
                    Image(systemName: QuantisedTogglePresentation.pendingGlyphSystemName)
                        .font(.system(size: 10, weight: .bold))
                    Text(pendingMuteTarget ? "MUTE NEXT BAR" : "UNMUTE NEXT BAR")
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                }
                .foregroundStyle(StudioTheme.amber)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(StudioTheme.background, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        StudioTheme.amber.opacity(0.9),
                        style: QuantisedTogglePresentation.strokeStyle(isPending: true, lineWidth: StudioMetrics.borderWidth)
                    )
                )
                .padding(8)
                .accessibilityLabel(pendingMuteTarget ? "Mute armed for next bar" : "Unmute armed for next bar")
            }
        }
        // Chrome only — the card underneath keeps the whole hit target.
        .allowsHitTesting(false)
    }

    private var strokeColor: Color {
        if isPerformSelected {
            return StudioTheme.amber.opacity(StudioOpacity.accentFill)
        }
        if isDirty {
            return StudioTheme.amber.opacity(0.92)
        }
        if isPerforming, let activePatternColor {
            return activePatternColor.opacity(StudioOpacity.accentFill)
        }
        if isPerforming {
            return layerAccentColor.opacity(StudioOpacity.accentFill)
        }
        if isFocused {
            return focusAccent.opacity(StudioOpacity.accentFill)
        }
        return StudioTheme.border
    }

    /// The active pattern's identity colour when the pattern layer drives
    /// this card; the outline takes the colour of the playing pattern.
    private var activePatternColor: Color? {
        guard layer.valueType == .patternIndex else {
            return nil
        }
        let stepIndex = cell.dependsOnPlayhead
            ? PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex).stepIndex
            : 0
        guard case let .index(index) = phrase
            .resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
            .normalized(for: layer)
        else {
            return nil
        }
        return StudioTheme.patternColor(index)
    }
}

/// Audio-input badge leaf: the only tracks-page view that reads audio-input
/// runtime state. `audioInputRuntimeRevision` bumps at capture-progress
/// rate while recording, so page/card bodies must not observe it.
private struct AudioInputRuntimeBadge: View {
    @Environment(EngineController.self) private var engineController
    let trackID: UUID
    let accent: Color

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        if let label {
            // Bold-flat pass: live runtime state is a solid accent block
            // with dark text.
            Text(label)
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(accent, in: Capsule())
                .lineLimit(1)
        }
    }

    private var label: String? {
        guard let runtime = engineController.audioInputRuntime(for: trackID) else {
            return nil
        }

        switch runtime.armState {
        case .armed:
            return "ARM"
        case .recording:
            return "REC"
        case .idle, .hasLoop:
            return "IN"
        }
    }
}

/// Runtime trigger leaf. Engine-side repeat activity (the engaged snapshot
/// with captured step/rate) is read HERE, keyed to the narrow
/// `noteRepeatRuntimeUIRevision` publisher — the page passes only its own
/// overlay gesture state, so engage/release never re-builds the page.
struct TrackPerformRuntimeLayerControl: View {
    /// Card cells fill the matrix card; row cells are the dense overview
    /// rows (wireframes §9) — smaller type, no card-height floor.
    enum Layout {
        case card
        case row
    }

    @Environment(EngineController.self) private var engineController
    let mode: TrackPerformLayerMode
    /// Engine runtime is watched for every track the surface speaks for
    /// (kit rows fold their members; cards pass one).
    let trackIDs: [UUID]
    let state: TrackPerformRuntimeControlState
    let latchMode: TrackPerformLatchMode
    let accent: Color
    var layout: Layout = .card
    let onActivate: () -> Void
    let onRelease: () -> Void
    /// Quantised next-cycle cue (fill's third gesture). Non-nil only when
    /// quantise arming is live for this control: a plain tap (sub-threshold
    /// press) in MOM mode arms/cancels the cue; holds keep behaving as MOM.
    var onCue: (() -> Void)?

    /// A momentary press that ends within this window counts as the plain
    /// tap that arms the cue — today that press is a zero-length hold.
    static let cueTapThreshold: TimeInterval = 0.25

    @State private var isTrackingMomentaryPress = false
    @State private var momentaryPressStartedAt: Date?

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.playheadLeafEvaluations += 1 }()
        #endif
        // Engine reads happen here, in this leaf's body context (not inside
        // the GeometryReader closure below, whose evaluation context SwiftUI
        // does not document).
        let activeRepeatSnapshot = mode == .noteRepeat
            ? trackIDs.lazy.compactMap({ engineController.noteRepeatRuntimeSnapshot(for: $0) }).first
            : nil
        let cuePresentation = QuantisedFillCuePresentation(
            isPending: mode == .fill && trackIDs.contains { engineController.hasQuantisedPendingFillCue(for: $0) },
            isCueBarActive: mode == .fill && trackIDs.contains { engineController.quantisedFillCueActiveTrackIDs.contains($0) }
        )
        let isActive = state.isActive || activeRepeatSnapshot != nil || cuePresentation.isCueBarActive
        triggerSurface(
            isActive: isActive,
            activeRepeatSnapshot: activeRepeatSnapshot,
            cuePresentation: cuePresentation
        )
        .help(helpText)
    }

    @ViewBuilder
    private func triggerSurface(
        isActive: Bool,
        activeRepeatSnapshot: EngineController.NoteRepeatRuntimeSnapshot?,
        cuePresentation: QuantisedFillCuePresentation
    ) -> some View {
        let label = label(
            isActive: isActive,
            activeRepeatSnapshot: activeRepeatSnapshot,
            cuePresentation: cuePresentation
        )
        if !state.isAvailable {
            label
                .opacity(0.68)
        } else {
            switch latchMode {
            case .latched:
                Button {
                    onActivate()
                } label: {
                    label
                }
                .buttonStyle(.plain)
            case .momentary:
                GeometryReader { proxy in
                    label
                        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    let isInside = CGRect(origin: .zero, size: proxy.size).contains(value.location)
                                    if isInside, !isTrackingMomentaryPress {
                                        isTrackingMomentaryPress = true
                                        momentaryPressStartedAt = Date()
                                        onActivate()
                                    } else if !isInside, isTrackingMomentaryPress {
                                        isTrackingMomentaryPress = false
                                        momentaryPressStartedAt = nil
                                        onRelease()
                                    }
                                }
                                .onEnded { _ in
                                    // A sub-threshold press is the plain TAP:
                                    // with quantise live it arms/cancels the
                                    // next-bar cue. Longer presses stay pure
                                    // MOM holds (interaction unchanged).
                                    let wasCueTap = onCue != nil
                                        && isTrackingMomentaryPress
                                        && momentaryPressStartedAt.map {
                                            Date().timeIntervalSince($0) < Self.cueTapThreshold
                                        } == true
                                    endMomentaryPressIfNeeded()
                                    if wasCueTap {
                                        onCue?()
                                    }
                                }
                        )
                }
                .frame(minHeight: layout == .card ? 96 : 0)
                .onDisappear {
                    endMomentaryPressIfNeeded()
                }
            }
        }
    }

    // The layer header already names the layer; the cell is just the on/off
    // state (plus the captured step/rate while engaged), filling the card.
    private func label(
        isActive: Bool,
        activeRepeatSnapshot: EngineController.NoteRepeatRuntimeSnapshot?,
        cuePresentation: QuantisedFillCuePresentation
    ) -> some View {
        let foreground = labelForeground(isActive: isActive, isCuePending: cuePresentation.isPending)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                if cuePresentation.isPending {
                    // The pending glyph from the armed-toggle grammar
                    // (wireframes §2): lands at the bar boundary.
                    Image(systemName: QuantisedTogglePresentation.pendingGlyphSystemName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StudioTheme.amber)
                }
                Text(cuePresentation.stateLabel ?? stateLabel(isActive: isActive))
                    .studioText(layout == .card ? .title : .labelBold)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let cueDetailLabel = cuePresentation.detailLabel {
                Text(cueDetailLabel)
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let capturedInfoLabel = capturedInfoLabel(isActive: isActive, activeRepeatSnapshot: activeRepeatSnapshot) {
                Text(capturedInfoLabel)
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(foreground)
        .padding(layout == .card ? StudioMetrics.Spacing.comfortable : StudioMetrics.Spacing.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(labelBackground, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(
                    labelStroke(cuePresentation: cuePresentation, isActive: isActive),
                    style: QuantisedTogglePresentation.strokeStyle(
                        isPending: cuePresentation.usesDashedStroke,
                        lineWidth: state.isMomentaryPressed || cuePresentation.isPending || cuePresentation.isCueBarActive
                            ? 2
                            : StudioMetrics.borderWidth
                    )
                )
        )
    }

    /// When repeat is engaged: the captured step (the one being repeated)
    /// and the rate it repeats at. Cleared when the repeat releases.
    private func capturedInfoLabel(
        isActive: Bool,
        activeRepeatSnapshot: EngineController.NoteRepeatRuntimeSnapshot?
    ) -> String? {
        guard mode == .noteRepeat, isActive, let snapshot = activeRepeatSnapshot else {
            return nil
        }
        guard let capturedStep = snapshot.capturedStep else {
            return snapshot.interval.rawValue
        }
        return "STEP \(capturedStep.stepIndex % 16 + 1) · \(snapshot.interval.rawValue)"
    }

    private func stateLabel(isActive: Bool) -> String {
        if !state.isAvailable {
            if mode == .noteRepeat {
                return "No Clip"
            }
            return "UNAVAILABLE"
        }
        if state.isMomentaryPressed {
            return "HELD"
        }
        if state.isLatched {
            return "LATCHED"
        }
        if isActive {
            return "ACTIVE"
        }
        return "READY"
    }

    private func labelForeground(isActive: Bool, isCuePending: Bool) -> Color {
        guard state.isAvailable else {
            return StudioTheme.mutedText
        }
        if isCuePending || state.isMomentaryPressed {
            return StudioTheme.amber
        }
        if state.isLatched {
            return accent
        }
        return isActive ? StudioTheme.text : StudioTheme.mutedText
    }

    /// Colour identifies, it never floods (ux-canon rule 12): the trigger
    /// surface stays on the neutral step; engaged state reads from the accent
    /// outline (`labelStroke`) and accent state text.
    private var labelBackground: Color {
        Color.white.opacity(StudioOpacity.subtleFill)
    }

    private func labelStroke(cuePresentation: QuantisedFillCuePresentation, isActive: Bool) -> Color {
        if !state.isAvailable {
            return StudioTheme.border
        }
        // Armed = dashed amber; applies-at-boundary = solid amber for the
        // cued bar (the armed-toggle grammar, wireframes §2).
        if cuePresentation.isPending || cuePresentation.isCueBarActive {
            return StudioTheme.amber.opacity(0.9)
        }
        if state.isMomentaryPressed {
            return StudioTheme.amber.opacity(0.9)
        }
        if state.isLatched {
            return accent.opacity(0.7)
        }
        return StudioTheme.border
    }

    private var helpText: String {
        if !state.isAvailable {
            return "\(mode.label) is available for clip-backed tracks only in v1."
        }
        return "\(mode.label) \(latchMode.label)"
    }

    private func endMomentaryPressIfNeeded() {
        guard isTrackingMomentaryPress else {
            return
        }

        isTrackingMomentaryPress = false
        momentaryPressStartedAt = nil
        onRelease()
    }
}

private extension TrackPerformLayerMode {
    /// Single-word label that fits the ~112pt matrix cards without truncation.
    var compactLabel: String {
        switch self {
        case .mute:
            return "MUTE"
        case .pattern:
            return "PATTERN"
        case .fill:
            return "FILL"
        case .noteRepeat:
            return "REPEAT"
        case .stepOrder:
            return "ORDER"
        case .volume:
            return "VOL"
        case .pan:
            return "PAN"
        }
    }
}

private extension TrackPerformLatchMode {
    var actionBarLabel: String {
        switch self {
        case .momentary:
            return "MOM"
        case .latched:
            return "LATCH"
        }
    }

    var symbolName: String {
        switch self {
        case .momentary:
            return "hand.tap"
        case .latched:
            return "lock"
        }
    }

    var helpText: String {
        switch self {
        case .momentary:
            return "Momentary runtime controls release on pointer up"
        case .latched:
            return "Latch runtime controls toggle until changed"
        }
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
        case .audioInput:
            return "dot.radiowaves.left.and.right"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(StudioTheme.background)
            .frame(width: 30, height: 30)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SequencerDocumentSession.self) private var session
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void
    let onPickSliceTrack: () -> Void
    let onPickDrumGroup: () -> Void

    var body: some View {
        StudioModal(
            title: "Create Track",
            subtitle: "Choose the kind of track to append to the matrix.",
            minWidth: 560,
            onClose: { dismiss() }
        ) {
            HStack(spacing: 12) {
                createButton(title: "Mono", detail: "Single melodic lane", accent: StudioTheme.cyan) {
                    appendAndOpen(.monoMelodic)
                }
                createButton(title: "Poly", detail: "Chord-capable lane", accent: StudioTheme.amber) {
                    appendAndOpen(.polyMelodic)
                }
                createButton(title: "Slice", detail: "Sample/slice trigger lane", accent: StudioTheme.violet) {
                    onPickSliceTrack()
                }
                createButton(
                    title: "Input",
                    detail: session.canAppendAudioInputTrack ? "Audio input lane" : "Already in project",
                    accent: StudioTheme.success,
                    isEnabled: session.canAppendAudioInputTrack,
                    disabledHelp: "One audio input track is available in this version"
                ) {
                    appendAndOpen(.audioInput)
                }
                createButton(title: "Drum Group", detail: "Grouped drum part tracks", accent: StudioTheme.amber) {
                    onPickDrumGroup()
                }
            }
        }
    }

    private func appendAndOpen(_ type: TrackType) {
        session.appendTrack(trackType: type)
        dismiss()
        onOpenTrack()
    }

    private func createButton(
        title: String,
        detail: String,
        accent: Color,
        isEnabled: Bool = true,
        disabledHelp: String = "",
        action: @escaping () -> Void
    ) -> some View {
        StudioOptionButton(
            title: title,
            detail: detail,
            accent: accent,
            minHeight: 120,
            isEnabled: isEnabled,
            disabledHelp: disabledHelp,
            action: action
        )
    }
}

private struct AddSliceTrackSheet: View {
    let library: AudioSampleLibrary
    let sampleEngine: SamplePlaybackSink
    /// Project-pool sample IDs — pooled loops list first.
    var pooledSampleIDs: Set<UUID> = []
    let onCreate: (AudioSample) -> Void
    let onCancel: () -> Void

    @State private var previewingSampleID: UUID?

    /// Breaks and recordings both feed the slicer; pooled loops on top,
    /// then global, each name-sorted.
    private var samples: [AudioSample] {
        let loops = library.samples(in: .breaks) + library.samples(in: .recordings)
        return loops.sorted { lhs, rhs in
            let lhsPooled = pooledSampleIDs.contains(lhs.id)
            let rhsPooled = pooledSampleIDs.contains(rhs.id)
            if lhsPooled != rhsPooled {
                return lhsPooled
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
            .padding(StudioMetrics.Spacing.page)
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
                    .overlay(Circle().stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth))
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

                    if pooledSampleIDs.contains(sample.id) {
                        Text("IN PROJECT")
                            .studioText(.microEmphasis)
                            .tracking(0.6)
                            .foregroundStyle(StudioTheme.success)
                    }
                }

                Spacer(minLength: 6)

                Button {
                    togglePreview(sample)
                } label: {
                    Image(systemName: previewingSampleID == sample.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudioTheme.background)
                        .frame(width: 28, height: 28)
                        .background(StudioTheme.violet, in: Circle())
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
                    .foregroundStyle(StudioTheme.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.violet, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
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
