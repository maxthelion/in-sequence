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

    var body: some View {
        // The tracks view is a plain NAVIGATOR: a matrix of track tiles you
        // click to open the single-track detail, plus an add-track tile. It is
        // no longer a perform surface — layer perform lives in phrase perform
        // and on the single-track detail page. There is no Edit/Perform split.
        TracksMatrixView(
            document: $document,
            selectedLayerID: $selectedLayerID,
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
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var isPresentingAddSliceTrack = false
    @State private var isPresentingAddDrumGroup = false
    /// Drives the delete confirmation for the selection-action bar.
    @State private var isConfirmingSelectionDelete = false
    /// AC18: a linked drum kit collapses to ONE cell; an unlinked kit expands
    /// to its per-part cells (linked↔collapsed, unlinked↔expanded). The Expand
    /// affordance on a collapsed cell adds the group to this transient set,
    /// overriding collapse for display only — it never changes the link state.
    @State private var forceExpandedGroups: Set<TrackGroupID> = []

    private let columns = StudioMetrics.Grid.matrixColumns(spacing: 12, minimum: 112, maximum: 190)

    private var groupedSections: [GroupedTrackSection] {
        session.store.trackGroups.compactMap { group in
            let members = session.store.tracksInGroup(group.id)
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        session.store.tracks.filter { $0.groupID == nil }
    }

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.pageBodyEvaluations += 1 }()
        #endif
        let tracks = session.store.tracks
        let selectedTrackID = session.store.selectedTrackID
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1). This is a plain navigator —
        // tap a tile to open it (selection OFF), or build a multi-selection
        // for the actions nav (selection ON). No perform chrome lives here.
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: StudioTheme.cyan,
                showsHeader: false
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    selectionTopBar(trackCount: tracks.count)

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
        .onAppear {
            // Drain any command applied while this view was still mounting
            // (workspace-switch race) so the sheet still opens for the capture.
            for command in VisualScenarioCommandRunner.drainPendingTracksMatrixCommands() {
                applyModalVisualCommand(command)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tracksMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            // Receiving live proves this view is mounted; clear the pending
            // copy so a later remount doesn't replay a stale command.
            VisualScenarioCommandRunner.pendingTracksMatrixCommands = []
            applyModalVisualCommand(command)
        }
    }

    /// Capture-harness hook: open/close the creation modals on command. The
    /// runner owns the reported `tracks*ModalVisible` status (set when the
    /// command is applied); this just flips the @State so the sheet renders.
    private func applyModalVisualCommand(_ command: String) {
        switch command {
        case "create-track-modal:open":
            isPresentingAddDrumGroup = false
            isPresentingAddSliceTrack = false
            isPresentingCreateTrack = true
        case "create-track-modal:close":
            isPresentingCreateTrack = false
        case "add-drum-group-modal:open":
            isPresentingCreateTrack = false
            isPresentingAddSliceTrack = false
            isPresentingAddDrumGroup = true
        case "add-drum-group-modal:close":
            isPresentingAddDrumGroup = false
        case "add-slice-track-modal:open":
            isPresentingCreateTrack = false
            isPresentingAddDrumGroup = false
            isPresentingAddSliceTrack = true
        case "add-slice-track-modal:close":
            isPresentingAddSliceTrack = false
        default:
            break
        }
    }

    /// A single horizontal bar with the Select toggle. With selection mode ON
    /// and ≥1 track selected, the Clear control and the action buttons (By
    /// Track / By Value / Create performance group) appear inline — there
    /// is no separate actions section and no "N selected" text.
    private func selectionTopBar(trackCount: Int) -> some View {
        let isOn = session.tracksSelectionMode
        let hasSelection = !session.tracksSelection.isEmpty
        return HStack(spacing: 10) {
            Button {
                session.toggleTracksSelectionMode()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 12, weight: .bold))
                    Text(isOn ? "Selecting" : "Select")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                }
                .foregroundStyle(isOn ? StudioTheme.background : StudioTheme.text)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(
                    isOn ? StudioTheme.cyan : Color.white.opacity(StudioOpacity.subtleFill),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isOn ? StudioTheme.cyan : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .disabled(trackCount == 0)
            .accessibilityIdentifier("tracks-select-toggle")
            .help(isOn ? "Exit selection mode" : "Select tracks to perform together")

            if isOn, hasSelection {
                clearButton

                Divider()
                    .frame(height: 22)

                selectionActionButton(
                    title: "By Track",
                    accent: StudioTheme.violet,
                    identifier: "tracks-action-by-track"
                ) { requestPhrasePerform(mode: .byTrack) }

                selectionActionButton(
                    title: "By Value",
                    accent: StudioTheme.cyan,
                    identifier: "tracks-action-by-value"
                ) { requestPhrasePerform(mode: .byValue) }

                deferredGroupButton

                deleteSelectionButton
            }

            Spacer(minLength: 0)
        }
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $isConfirmingSelectionDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = session.tracksSelection
                isConfirmingSelectionDelete = false
                session.removeTracks(ids: ids)
            }
            Button("Cancel", role: .cancel) {
                isConfirmingSelectionDelete = false
            }
        } message: {
            Text("This removes the selected track\(session.tracksSelection.count == 1 ? "" : "s") from the project. This cannot be undone.")
        }
    }

    private var deleteConfirmTitle: String {
        let count = session.tracksSelection.count
        return "Delete \(count) track\(count == 1 ? "" : "s")?"
    }

    /// Selection-action Delete: removes the selected tracks after a
    /// confirmation. Styled with the amber destructive accent.
    private var deleteSelectionButton: some View {
        Button {
            isConfirmingSelectionDelete = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                Text("Delete")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
            }
            .foregroundStyle(StudioTheme.background)
            .frame(height: 32)
            .padding(.horizontal, 14)
            .background(StudioTheme.amber.opacity(StudioOpacity.accentFill), in: Capsule())
            .overlay(Capsule().stroke(StudioTheme.amber.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tracks-action-delete")
        .help("Delete the selected tracks")
    }

    private var clearButton: some View {
        Button {
            session.tracksSelection.removeAll()
        } label: {
            Text("CLEAR")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tracks-select-clear")
        .help("Clear selection")
    }

    /// A compact selection action button. By Track / By Value navigate to the
    /// phrase Layers surface with the selected tracks preloaded as scope.
    private func selectionActionButton(
        title: String,
        accent: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.microEmphasis)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.background)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(accent.opacity(StudioOpacity.accentFill), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .help(title)
    }

    /// Create performance group is intentionally disabled: the durable
    /// performance-group object is deferred until its own spec lands.
    private var deferredGroupButton: some View {
        HStack(spacing: 6) {
            Text("Create performance group")
                .studioText(.microEmphasis)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Text("SOON")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(StudioTheme.mutedText, in: Capsule())
        }
        .frame(height: 32)
        .padding(.horizontal, 14)
        .overlay(
            Capsule()
                .stroke(StudioTheme.border, style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [4, 4]))
        )
        .opacity(0.55)
        .accessibilityIdentifier("tracks-action-create-group")
        .help("Performance groups are coming soon")
    }

    /// By Track / By Value: stash the current selection as the phrase layer
    /// scope and queue navigation into Phrase -> Layers.
    private func requestPhrasePerform(mode: PhraseLayerEditMode) {
        session.requestPhrasePerform(
            tab: .layers,
            layerEditMode: mode,
            trackIDs: session.tracksSelection
        )
    }

    /// One flat navigator grid: ungrouped track cells, then each kit (a single
    /// kit cell when collapsed, or the kit cell followed inline by its per-part
    /// cells when expanded), then the add-track tile. Kit cells reuse the same
    /// cell chrome + footprint as normal track cells — no surrounding wrapper
    /// section. The expand/collapse affordance lives ON the kit cell itself.
    private func matrixSections(tracks: [StepSequenceTrack], selectedTrackID: UUID) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(ungroupedTracks, id: \.id) { track in
                #if DEBUG
                let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                #endif
                trackCell(track, group: nil, selectedTrackID: selectedTrackID)
            }

            ForEach(groupedSections) { section in
                kitCell(section: section, selectedTrackID: selectedTrackID)

                if !isGroupCollapsed(section.group) {
                    ForEach(section.members, id: \.id) { member in
                        #if DEBUG
                        let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                        #endif
                        trackCell(member, group: section.group, selectedTrackID: selectedTrackID)
                    }
                }
            }

            addTrackCard
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

    /// The kit's single navigator cell — same chrome/footprint as a normal
    /// track cell (`KitMatrixCard`). When collapsed it carries an Expand
    /// affordance and a thumbnail strip of its contained parts; when expanded
    /// it carries a Collapse affordance and the parts render as sibling cells
    /// following it in the grid. Selecting/opening speaks for the whole kit.
    @ViewBuilder
    private func kitCell(section: GroupedTrackSection, selectedTrackID: UUID) -> some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
        #endif
        let representativeTrackID = section.members.first?.id
        let memberIDs = section.members.map(\.id)
        // A grouped kit tile selects (or deselects) all its members at once so
        // the actions nav speaks for the whole kit.
        let kitSelected = !memberIDs.isEmpty && memberIDs.allSatisfy { session.tracksSelection.contains($0) }
        let isCollapsed = isGroupCollapsed(section.group)
        KitMatrixCard(
            group: section.group,
            partNames: section.members.map(\.name),
            patternSlotLabel: collapsedKitPatternSlotLabel(section),
            isCollapsed: isCollapsed,
            isFocused: section.members.contains { $0.id == selectedTrackID },
            isSelectionMode: session.tracksSelectionMode,
            isSelected: kitSelected,
            onOpenKit: {
                if session.tracksSelectionMode {
                    session.toggleTracksSelected(memberIDs)
                } else if let representativeTrackID {
                    session.setSelectedTrackID(representativeTrackID)
                    onOpenTrack()
                }
            },
            onToggleExpand: {
                if isCollapsed {
                    expandGroup(section.group)
                } else {
                    collapseGroup(section.group)
                }
            }
        )
    }

    @ViewBuilder
    private func trackCell(_ track: StepSequenceTrack, group: TrackGroup?, selectedTrackID: UUID) -> some View {
        TrackMatrixCard(
            track: track,
            group: group,
            isMuted: track.mix.isMuted,
            isFocused: track.id == selectedTrackID,
            isSelectionMode: session.tracksSelectionMode,
            isSelected: session.tracksSelection.contains(track.id),
            onToggleMute: {
                session.toggleTrackMute(trackID: track.id)
            }
        ) {
            if session.tracksSelectionMode {
                session.toggleTrackSelected(track.id)
            } else {
                session.setSelectedTrackID(track.id)
                onOpenTrack()
            }
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

    // Same footprint as TrackMatrixCard (minHeight 132 + comfortable padding)
    // so the add tile sits flush in the grid (ux-canon rule 5); the "+" alone
    // carries the affordance, with the action named in help/accessibility.
    private var addTrackCard: some View {
        StudioAddCard(label: "", minHeight: 132, help: "Add a track") {
            isPresentingCreateTrack = true
        }
    }

}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

/// A drum kit's navigator cell. It sits in the same flat grid as normal track
/// cells (matching `TrackMatrixCard`'s footprint + outline grammar) — there is
/// no surrounding wrapper section. Tapping the body opens the kit matrix
/// (kit-first, same as selecting a member). The expand/collapse affordance
/// lives ON the cell: collapsed, it shows a thumbnail strip of the contained
/// parts as small cells inside this cell ("for indication purposes") plus an
/// Expand control; expanded, the parts render as sibling cells following this
/// one in the grid and the control becomes Collapse.
private struct KitMatrixCard: View {
    let group: TrackGroup
    let partNames: [String]
    let patternSlotLabel: String
    let isCollapsed: Bool
    let isFocused: Bool
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onOpenKit: () -> Void
    let onToggleExpand: () -> Void

    // Identity hue shared with this kit's member parts (bug 20260629-100436).
    private var accent: Color {
        group.identityColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 30, height: 30)
                    .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))

                Spacer(minLength: 0)

                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? accent : StudioTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .accessibilityIdentifier("kit-card-select-mark")
                } else {
                    // The expand/collapse affordance lives ON the cell.
                    Button(action: onToggleExpand) {
                        Image(systemName: isCollapsed
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                            .overlay(Circle().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(isCollapsed ? "kit-expand" : "kit-collapse")
                    .help(isCollapsed
                        ? "Expand \(group.name) to its per-part cells"
                        : "Collapse \(group.name) back to one cell")
                }
            }

            // The contained parts shown as small cells inside the kit cell, for
            // indication, while collapsed. When expanded they live in the grid
            // as sibling cells instead, so the strip is hidden.
            if isCollapsed, !partNames.isEmpty {
                partThumbnailStrip
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 6) {
                    Text("KIT")
                    Text("\(partNames.count) PARTS")
                    Text(patternSlotLabel)
                }
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(isSelected ? accent.opacity(StudioOpacity.accentFill) : Color.white.opacity(StudioOpacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    isSelected ? accent : (isFocused ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border),
                    lineWidth: (isSelected || isFocused) ? 2 : StudioMetrics.borderWidth
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture(perform: onOpenKit)
        .accessibilityIdentifier("kit-collapsed-cell")
    }

    /// The contained part tracks rendered as small nested cells inside the kit
    /// cell — an indication of membership, not interactive (tapping the kit
    /// opens the kit matrix). Caps the count with a "+N" overflow chip.
    private var partThumbnailStrip: some View {
        let maxShown = 4
        let shown = Array(partNames.prefix(maxShown))
        let overflow = partNames.count - shown.count
        return HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous).stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(accent.opacity(StudioOpacity.accentFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            }
        }
        .accessibilityIdentifier("kit-part-thumbnails")
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

/// A single navigator tile: the track's type/instrument icon + its name, with
/// a tiny mute toggle. No pattern/layer preview and no perform chrome — the
/// tracks view is a plain navigator. Tapping the tile opens the single-track
/// detail (kit members route via the surrounding section/collapsed cell).
private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
    let isMuted: Bool
    let isFocused: Bool
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onToggleMute: () -> Void
    let onTap: () -> Void

    // Identity hue (bug 20260629-100436): a grouped part shares its kit's hue so
    // they read as one group; an ungrouped track gets a stable per-track palette
    // colour derived from its id. Selection is encoded by the outline, not the
    // hue, so identity and selection no longer collide.
    private var accent: Color {
        if let group {
            return group.identityColor
        }
        return Color(hex: TrackPalette.identityHex(for: track.id)) ?? StudioTheme.cyan
    }

    private var typeLabel: String {
        track.trackType.label.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TrackTypeBadge(trackType: track.trackType, accent: accent)

                Spacer(minLength: 0)

                if isSelectionMode {
                    // In selection mode the tile carries a checkbox instead of
                    // the mute toggle — the whole tile toggles membership.
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? accent : StudioTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .accessibilityIdentifier("track-card-select-mark")
                } else {
                    // A tiny mute toggle is the only control on the tile.
                    Button(action: onToggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isMuted ? StudioTheme.background : StudioTheme.mutedText)
                            .frame(width: 26, height: 26)
                            .background(
                                isMuted ? StudioTheme.amber : Color.white.opacity(StudioOpacity.subtleFill),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(isMuted ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("track-card-mute")
                    .help(isMuted ? "Unmute \(track.name)" : "Mute \(track.name)")
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(typeLabel)
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(isSelected ? accent.opacity(StudioOpacity.accentFill) : Color.white.opacity(StudioOpacity.subtleFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            onTap()
        }
    }

    private var strokeColor: Color {
        if isSelected { return accent }
        if isFocused { return accent.opacity(StudioOpacity.accentFill) }
        return StudioTheme.border
    }

    private var strokeWidth: CGFloat {
        (isSelected || isFocused) ? 2 : StudioMetrics.borderWidth
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

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    var body: some View {
        StudioModal(
            title: "Create Track",
            minWidth: 560,
            onClose: { dismiss() }
        ) {
            LazyVGrid(columns: columns, spacing: 12) {
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
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(samples) { sample in
                                    sampleRow(sample)
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

    /// Recording buffers get the amber accent; factory breaks keep violet.
    private func accent(for sample: AudioSample) -> Color {
        sample.category == .recordings ? StudioTheme.amber : StudioTheme.violet
    }

    private func sampleRow(_ sample: AudioSample) -> some View {
        let rowAccent = accent(for: sample)
        let isRecording = sample.category == .recordings
        return HStack(alignment: .center, spacing: 12) {
            // Accent rail distinguishes recordings from factory breaks at a glance.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(rowAccent)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(sample.name)
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(isRecording ? "BUFFER" : "FACTORY")
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                        .foregroundStyle(rowAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(rowAccent.opacity(0.18), in: Capsule())

                    if pooledSampleIDs.contains(sample.id) {
                        Text("IN PROJECT")
                            .studioText(.microEmphasis)
                            .tracking(0.6)
                            .foregroundStyle(StudioTheme.success)
                    }
                }

                Text(sampleDetail(sample))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                togglePreview(sample)
            } label: {
                Image(systemName: previewingSampleID == sample.id ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: 28, height: 28)
                    .background(rowAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .help(previewingSampleID == sample.id ? "Stop preview" : "Preview loop")

            Button {
                sampleEngine.stopAudition()
                onCreate(sample)
            } label: {
                Text("Use Loop")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(rowAccent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, StudioMetrics.Spacing.comfortable)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private extension TrackGroup {
    /// The group's identity hue: its stored colour when that is a valid 6-digit
    /// hex, otherwise a stable palette colour derived from the group id. The
    /// fallback means a kit and its parts resolve the SAME hue even for the
    /// legacy malformed "#8AA" default — no document migration required.
    var identityColor: Color {
        if TrackPalette.isValidHex(color), let stored = Color(hex: color) {
            return stored
        }
        return Color(hex: TrackPalette.identityHex(for: id)) ?? StudioTheme.success
    }
}
