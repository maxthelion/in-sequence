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
    /// AC18: a linked drum kit collapses to ONE cell; an unlinked kit expands
    /// to its per-part cells (linked↔collapsed, unlinked↔expanded). The Expand
    /// affordance on a collapsed cell adds the group to this transient set,
    /// overriding collapse for display only — it never changes the link state.
    @State private var forceExpandedGroups: Set<TrackGroupID> = []

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 112, maximum: 190), spacing: 12),
        count: 8
    )

    /// The card grid shows a pattern preview in both modes (navigation +
    /// selection): the matrix is no longer a layer surface, so there is one
    /// fixed preview layer (the pattern layer), not a selectable one.
    private var previewLayer: PhraseLayerDefinition {
        let layers = session.store.layers
        return session.store.patternLayer
            ?? session.store.layer(id: selectedLayerID)
            ?? layers.first!
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
        .onChange(of: tracks.map(\.id)) { _, trackIDs in
            performSelection.reconcile(availableTrackIDs: trackIDs)
        }
        .onChange(of: isPerforming) { _, isNowPerforming in
            if !isNowPerforming {
                performSelection.clear()
                // Leaving perform also drops any scoped Track/Kit Perform set
                // (AC22) so the next entry starts unscoped (whole project).
                session.performTrackScope = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackPerformVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyTrackPerformVisualCommand(command)
        }
    }

    // The tracks Perform view is navigation + selection (not a layer surface):
    // the action bar names the basis phrase and, while performing, surfaces the
    // multi-select "Edit Set" plus the Perform launcher that opens the scoped
    // Track/Kit Perform overlay (which reuses phrase perform) for the selection.
    private var actionBar: some View {
        HStack(spacing: 12) {
            basisPhrasePill
            Spacer()
            if isPerforming {
                if !performScope.isEmpty {
                    performScopeChip
                }
                performSelectionSummary
                performLaunchButton
            }
        }
    }

    /// AC3: launch the existing scoped Track/Kit Perform overlay for the
    /// current selection (single track, multi-select, or — when a whole kit is
    /// selected — the kit). Selection is transient runtime state; entering
    /// scoped perform records it in `session.performTrackScope` and flips the
    /// global mode to perform. No bespoke layer UI is built here.
    private var performLaunchButton: some View {
        Button {
            launchScopedPerform()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Perform")
                    .studioText(.labelBold)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.amber)
        .disabled(performLaunchTrackIDs.isEmpty)
        .accessibilityIdentifier("track-perform-launch")
        .help(performLaunchTrackIDs.isEmpty
            ? "Select one or more cards to perform"
            : "Perform the selected track(s) — opens scoped Track/Kit Perform")
    }

    /// Ordered track ids the Perform launcher will scope to: the multi-select
    /// edit set when non-empty, otherwise the focused track.
    private var performLaunchTrackIDs: [UUID] {
        let ordered = session.store.tracks.map(\.id)
        let selected = ordered.filter { performSelection.contains($0) }
        if !selected.isEmpty {
            return selected
        }
        let focused = session.store.selectedTrackID
        return ordered.contains(focused) ? [focused] : []
    }

    private func launchScopedPerform() {
        let trackIDs = performLaunchTrackIDs
        guard !trackIDs.isEmpty else { return }
        session.enterScopedPerform(trackIDs: trackIDs)
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
        // The card grid is navigation + selection in both modes: a fixed
        // pattern preview (never a selectable layer) plus, while performing, a
        // per-card mute toggle and the multi-select "Edit Set" checkbox.
        let layer = previewLayer
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                #if DEBUG
                let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                #endif
                // Card inputs are document/selection state only. Anything
                // that varies at tick/meter rate (playhead-resolved values,
                // audio-input runtime) is read by leaf views INSIDE the card,
                // so a transport tick never re-builds the cards
                // (architecture verdict §2).
                let cell = editingPhrase.cell(for: layer.id, trackID: track.id)
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: session.store.selectedPatternIndex(for: track.id),
                    phrase: editingPhrase,
                    layer: layer,
                    cell: cell,
                    isMuted: track.mix.isMuted,
                    isFocused: track.id == selectedTrackID,
                    isPerformSelected: performSelection.contains(track.id),
                    isPerforming: isPerforming,
                    onTogglePerformSelection: {
                        performSelection.toggle(track.id)
                    },
                    onToggleMute: {
                        session.toggleTrackMute(trackID: track.id)
                    }
                ) {
                    // Click opens that track's single-track detail in BOTH
                    // modes (navigation): perform is launched from the action
                    // bar's Perform button on the selection, not per card.
                    session.setSelectedTrackID(track.id)
                    onOpenTrack()
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

    /// The tracks Perform view is navigation + selection now, so the bespoke
    /// layer-perform visual commands (open/close the TRACK LAYER selector,
    /// select a layer/variant, press/release note-repeat, phrase capture) are
    /// retired — they drove the removed layer surface. The QA runner no longer
    /// posts them; this handler stays as a deliberate no-op so any stale
    /// notification is ignored rather than crashing.
    private func applyTrackPerformVisualCommand(_ command: String) {
        // Retired: track-perform layer surface removed (tracks-perform =
        // navigation + selection; layer perform launches scoped from the
        // selection via the action-bar Perform button).
        _ = command
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
    let cell: PhraseCell
    let isMuted: Bool
    let isFocused: Bool
    let isPerformSelected: Bool
    let isPerforming: Bool
    let onTogglePerformSelection: () -> Void
    let onToggleMute: () -> Void
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
        layerAccent(layer.id)
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
                    // Per-card mute toggle (prototype 03): document-truth track
                    // mute, not a phrase-perform layer cell.
                    Button(action: onToggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isMuted ? StudioTheme.background : StudioTheme.mutedText)
                            .frame(width: 28, height: 28)
                            .background(
                                isMuted ? StudioTheme.amber : Color.white.opacity(StudioOpacity.subtleFill),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(isMuted ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("track-card-mute")
                    .help(isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")

                    Button(action: onTogglePerformSelection) {
                        Image(systemName: isPerformSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isPerformSelected ? StudioTheme.amber : StudioTheme.mutedText)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                            .overlay(Circle().stroke(isPerformSelected ? StudioTheme.amber.opacity(0.7) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("track-card-select")
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

            // The card shows a fixed PATTERN PREVIEW in both modes (the
            // tracks view is navigation + selection, not a layer surface).
            TrackCardCellPreviewLeaf(
                phrase: phrase,
                layer: layer,
                trackID: track.id,
                cell: cell,
                accent: layerAccentColor,
                contentOpacity: layerContentOpacity
            )
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
                isFocused: isFocused,
                isPerformSelected: isPerformSelected,
                isPerforming: isPerforming,
                focusAccent: accent,
                layerAccentColor: layerAccentColor
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            onTap()
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
                        lineWidth: isFocused || isPerformSelected || isPerforming ? 2 : StudioMetrics.borderWidth
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
