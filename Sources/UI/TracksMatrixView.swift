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

enum TracksNavigatorFilter: String, CaseIterable, Identifiable {
    case all
    case mono
    case poly
    case chord
    case slicer
    case audio
    case drumKits
    case drumParts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .mono: return "Mono"
        case .poly: return "Poly"
        case .chord: return "Chord"
        case .slicer: return "Slicer"
        case .audio: return "Audio"
        case .drumKits: return "Drum Kits"
        case .drumParts: return "Drum Parts"
        }
    }
}

enum TracksNavigatorPresentationItem: Equatable, Identifiable {
    case track(UUID)
    case kit(TrackGroupID)

    var id: String {
        switch self {
        case .track(let id): return "track-\(id.uuidString)"
        case .kit(let id): return "kit-\(id.uuidString)"
        }
    }
}

enum TracksNavigatorPresentation {
    static func items(
        tracks: [StepSequenceTrack],
        groups: [TrackGroup],
        filter: TracksNavigatorFilter,
        forceExpandedGroups: Set<TrackGroupID> = []
    ) -> [TracksNavigatorPresentationItem] {
        let ungroupedTracks = tracks.filter { $0.groupID == nil }

        switch filter {
        case .all:
            var result = ungroupedTracks.map { TracksNavigatorPresentationItem.track($0.id) }
            for group in groups {
                result.append(.kit(group.id))
                if !group.isPatternLinked || forceExpandedGroups.contains(group.id) {
                    result.append(contentsOf: members(of: group, tracks: tracks).map {
                        TracksNavigatorPresentationItem.track($0.id)
                    })
                }
            }
            return result

        case .drumKits:
            return groups.map { .kit($0.id) }

        case .drumParts:
            return groups.flatMap { group in
                members(of: group, tracks: tracks).map {
                    TracksNavigatorPresentationItem.track($0.id)
                }
            }

        case .mono, .poly, .chord, .slicer, .audio:
            return ungroupedTracks.compactMap { track in
                filter.includes(track.trackType) ? .track(track.id) : nil
            }
        }
    }

    static func visibleTrackIDs(
        in items: [TracksNavigatorPresentationItem],
        tracks: [StepSequenceTrack],
        groups: [TrackGroup]
    ) -> [UUID] {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return items.flatMap { item -> [UUID] in
            switch item {
            case .track(let trackID):
                return tracksByID[trackID] == nil ? [] : [trackID]
            case .kit(let groupID):
                guard let group = groupsByID[groupID] else { return [] }
                return group.memberIDs.filter { tracksByID[$0] != nil }
            }
        }
    }

    private static func members(
        of group: TrackGroup,
        tracks: [StepSequenceTrack]
    ) -> [StepSequenceTrack] {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return group.memberIDs.compactMap { tracksByID[$0] }
    }
}

private struct CreatePerformanceTrackGroupRequest: Identifiable {
    let id = UUID()
    let memberIDs: Set<UUID>
}

private extension TracksNavigatorFilter {
    func includes(_ trackType: TrackType) -> Bool {
        switch (self, trackType) {
        case (.mono, .monoMelodic), (.poly, .polyMelodic), (.chord, .chord),
             (.slicer, .slice), (.audio, .audioInput):
            return true
        default:
            return false
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
        .padding(StudioMetrics.Spacing.workspaceInset)
    }
}

struct TracksDocumentEditClipboard: Equatable {
    let trackIDs: Set<UUID>

    func resolvedTrackIDs(in liveTrackIDs: [UUID]) -> Set<UUID> {
        trackIDs.intersection(liveTrackIDs)
    }
}

private struct TracksDocumentEditRevision: Equatable {
    let selection: Set<UUID>
    let liveTrackIDs: [UUID]
}

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var selectedLayerID: String
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let onOpenTrack: () -> Void

    /// The consolidated creation flow: non-nil presents the ONE Create Track
    /// sheet at the given step (type picker, drum-group builder, slice loop
    /// picker, or the mono/poly sound step). Replaces the old trio of
    /// independent sheet booleans whose handoff dismissed one sheet and
    /// re-presented another.
    @State private var createTrackStep: CreateTrackFlowStep?
    /// Drives the delete confirmation for the selection-action bar.
    @State private var isConfirmingSelectionDelete = false
    @State private var trackFilter: TracksNavigatorFilter = .all
    @State private var pendingDeleteTrackIDs: Set<UUID> = []
    @State private var createPerformanceTrackGroupRequest: CreatePerformanceTrackGroupRequest?
    /// AC18: a linked drum kit collapses to ONE cell; an unlinked kit expands
    /// to its per-part cells (linked↔collapsed, unlinked↔expanded). The Expand
    /// affordance on a collapsed cell adds the group to this transient set,
    /// overriding collapse for display only — it never changes the link state.
    @State private var forceExpandedGroups: Set<TrackGroupID> = []

    private let columns = StudioMetrics.Grid.matrixColumns(spacing: 12, minimum: 112, maximum: 190)

    var body: some View {
        #if DEBUG
        let _ = { TracksPageInvalidationProbe.pageBodyEvaluations += 1 }()
        #endif
        let tracks = session.store.tracks
        let groups = session.store.trackGroups
        let selectedTrackID = session.store.selectedTrackID
        let presentationItems = TracksNavigatorPresentation.items(
            tracks: tracks,
            groups: groups,
            filter: trackFilter,
            forceExpandedGroups: forceExpandedGroups
        )
        let visibleTrackIDs = TracksNavigatorPresentation.visibleTrackIDs(
            in: presentationItems,
            tracks: tracks,
            groups: groups
        )
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1). This is a plain navigator —
        // Tap a tile to open it; secondary click or Shift-tap builds a
        // multi-selection for the actions nav. No perform chrome lives here.
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: StudioTheme.transportAccent,
                showsHeader: false,
                contentPadding: 0
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    selectionTopBar(
                        trackCount: tracks.count,
                        visibleTrackIDs: visibleTrackIDs
                    )

                    if tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            accent: StudioTheme.transportAccent
                        )
                        .help("Create a mono, poly, slice, or drum-kit bundle to start building the matrix")
                    } else {
                        matrixSections(
                            items: presentationItems,
                            tracks: tracks,
                            groups: groups,
                            selectedTrackID: selectedTrackID
                        )
                    }
                }
            }
        }
        .sheet(item: $createTrackStep) { step in
            CreateTrackFlow(
                initialStep: step,
                onOpenTrack: onOpenTrack,
                onDismiss: { createTrackStep = nil }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $createPerformanceTrackGroupRequest) { request in
            createPerformanceTrackGroupSheet(request)
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
        .documentEditTarget(
            isActive: true,
            revision: TracksDocumentEditRevision(
                selection: session.tracksSelection,
                liveTrackIDs: tracks.map(\.id)
            ),
            makeTarget: tracksDocumentEditTarget
        )
    }

    /// Capture-harness hook: drive the ONE creation flow to a target step (or
    /// close it) on command. The runner owns the reported `tracks*ModalVisible`
    /// status (set when the command is applied); this just sets the @State so
    /// the sheet renders at the requested step.
    private func applyModalVisualCommand(_ command: String) {
        if command.hasPrefix("filter:"),
           let filter = TracksNavigatorFilter(rawValue: String(command.dropFirst("filter:".count))) {
            trackFilter = filter
            return
        }

        if command == "copy-selection" {
            _ = session.documentEditCommands.copy()
            return
        }

        if command == "create-track-group:open" {
            guard !session.tracksSelection.isEmpty else { return }
            createTrackStep = nil
            createPerformanceTrackGroupRequest = CreatePerformanceTrackGroupRequest(
                memberIDs: session.tracksSelection
            )
            return
        }

        if command == "create-track-group:close" {
            createPerformanceTrackGroupRequest = nil
            return
        }

        switch CreateTrackFlowStep.action(forVisualCommand: command) {
        case .present(let step):
            createPerformanceTrackGroupRequest = nil
            createTrackStep = step
        case .close:
            createTrackStep = nil
        case nil:
            break
        }
    }

    /// A single horizontal bar with the Select toggle. With selection mode ON
    /// and ≥1 visible track selected, the Perform / Create performance group
    /// action buttons appear inline — there
    /// is no separate actions section and no "N selected" text.
    private func selectionTopBar(trackCount: Int, visibleTrackIDs: [UUID]) -> some View {
        let isOn = session.tracksSelectionMode
        let visibleSelection = Set(visibleTrackIDs.filter { session.tracksSelection.contains($0) })
        let hasSelection = !visibleSelection.isEmpty
        return HStack(spacing: 10) {
            StudioMenuPicker(
                title: nil,
                selection: $trackFilter,
                options: TracksNavigatorFilter.allCases.map {
                    StudioMenuPickerOption(label: $0.title, value: $0)
                },
                help: "Filter tracks by type",
                symbolName: "line.3.horizontal.decrease.circle"
            )
            .accessibilityIdentifier("tracks-type-filter")

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
                .foregroundStyle(isOn ? StudioTheme.transportAccent : StudioTheme.text)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(
                    StudioTheme.subtleFill,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(isOn ? StudioTheme.transportAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .disabled(trackCount == 0)
            .accessibilityIdentifier("tracks-select-toggle")
            .help(isOn ? "Exit selection mode" : "Select tracks to perform together")

            if isOn, hasSelection {
                selectionActionButton(
                    title: "Perform",
                    accent: StudioTheme.phraseAccent,
                    identifier: "tracks-action-perform"
                ) { requestPhrasePerform(trackIDs: visibleSelection) }

                createTrackGroupButton(trackIDs: visibleSelection)

                deleteSelectionButton(trackIDs: visibleSelection)
            }

            Spacer(minLength: 0)
        }
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $isConfirmingSelectionDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = pendingDeleteTrackIDs
                isConfirmingSelectionDelete = false
                pendingDeleteTrackIDs.removeAll()
                session.removeTracks(ids: ids)
            }
            Button("Cancel", role: .cancel) {
                isConfirmingSelectionDelete = false
                pendingDeleteTrackIDs.removeAll()
            }
        } message: {
            Text("This removes the selected track\(pendingDeleteTrackIDs.count == 1 ? "" : "s") from the project. This cannot be undone.")
        }
    }

    private var deleteConfirmTitle: String {
        let count = pendingDeleteTrackIDs.count
        return "Delete \(count) track\(count == 1 ? "" : "s")?"
    }

    /// Selection-action Delete: removes the selected tracks after a
    /// confirmation. Styled as a true destructive action.
    private func deleteSelectionButton(trackIDs: Set<UUID>) -> some View {
        let destructiveAccent = StudioTheme.danger // ux-canon-allow: semantic destructive delete action uses the danger role
        return Button {
            pendingDeleteTrackIDs = trackIDs
            isConfirmingSelectionDelete = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                Text("Delete")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
            }
            .foregroundStyle(destructiveAccent)
            .frame(height: 32)
            .padding(.horizontal, 14)
            .background(StudioTheme.subtleFill, in: Capsule())
            .overlay(Capsule().stroke(destructiveAccent, lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tracks-action-delete")
        .help("Delete the selected tracks")
    }

    /// A compact selection action button used by navigator commands.
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
                .foregroundStyle(accent)
                .frame(height: 32)
                .padding(.horizontal, 14)
                .background(StudioTheme.subtleFill, in: Capsule())
                .overlay(Capsule().stroke(accent, lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .help(title)
    }

    private func createTrackGroupButton(trackIDs: Set<UUID>) -> some View {
        selectionActionButton(
            title: "Create Track Group",
            accent: StudioTheme.transportAccent,
            identifier: "tracks-action-create-group"
        ) {
            createPerformanceTrackGroupRequest = CreatePerformanceTrackGroupRequest(memberIDs: trackIDs)
        }
        .accessibilityIdentifier("tracks-action-create-group")
        .help("Save the selected tracks into one of 16 performance group slots")
    }

    private func createPerformanceTrackGroupSheet(
        _ request: CreatePerformanceTrackGroupRequest
    ) -> some View {
        let memberNames = session.store.tracks
            .filter { request.memberIDs.contains($0.id) }
            .map(\.name)
        return StudioModal(
            title: "Create Track Group",
            subtitle: memberNames.joined(separator: ", "),
            accent: StudioTheme.transportAccent,
            minWidth: 520,
            onClose: { createPerformanceTrackGroupRequest = nil }
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 86), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(0..<PerformanceTrackGroup.slotCount, id: \.self) { index in
                    performanceTrackGroupSlot(index: index, memberIDs: request.memberIDs)
                }
            }
            .accessibilityIdentifier("create-track-group-slot-matrix")
        }
    }

    private func performanceTrackGroupSlot(index: Int, memberIDs: Set<UUID>) -> some View {
        let existing = session.store.performanceTrackGroups[index]
        return Button {
            guard session.setPerformanceTrackGroup(slotIndex: index, memberIDs: memberIDs) != nil else { return }
            createPerformanceTrackGroupRequest = nil
            session.tracksSelection.removeAll()
            session.tracksSelectionMode = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(index + 1)")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.transportAccent)
                Text(existing?.name ?? "Empty")
                    .studioText(.labelBold)
                    .foregroundStyle(existing == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(1)
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(existing == nil ? StudioTheme.border : StudioTheme.transportAccent, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(existing == nil ? "Save as track group \(index + 1)" : "Replace \(existing?.name ?? "track group")")
        .accessibilityIdentifier("create-track-group-slot-\(index + 1)")
    }

    /// Queue the one navigator Perform action into Phrase -> Layers, scoped to
    /// the visible selected tracks and starting in By Track mode.
    private func requestPhrasePerform(trackIDs: Set<UUID>) {
        session.requestPhrasePerform(
            tab: .layers,
            layerEditMode: .byTrack,
            trackIDs: trackIDs
        )
    }

    private func tracksDocumentEditTarget() -> DocumentEditCommandController.Target {
        .init(
            canCopy: {
                !TracksDocumentEditClipboard(trackIDs: session.tracksSelection)
                    .resolvedTrackIDs(in: session.store.tracks.map(\.id))
                    .isEmpty
            },
            canClear: { !session.tracksSelection.isEmpty },
            isPasteCompatible: { payload in
                guard payload.domain == .tracks,
                      let clipboard = payload.value(as: TracksDocumentEditClipboard.self)
                else { return false }
                return !clipboard.resolvedTrackIDs(in: session.store.tracks.map(\.id)).isEmpty
            },
            copy: {
                let clipboard = TracksDocumentEditClipboard(trackIDs: session.tracksSelection)
                let resolvedIDs = clipboard.resolvedTrackIDs(in: session.store.tracks.map(\.id))
                guard !resolvedIDs.isEmpty else { return nil }
                return .init(
                    domain: .tracks,
                    snapshot: TracksDocumentEditClipboard(trackIDs: resolvedIDs)
                )
            },
            paste: { payload in
                guard let clipboard = payload.value(as: TracksDocumentEditClipboard.self) else { return }
                let resolvedIDs = clipboard.resolvedTrackIDs(in: session.store.tracks.map(\.id))
                guard !resolvedIDs.isEmpty else { return }
                _ = session.duplicateTracks(ids: resolvedIDs)
            },
            clearSelection: {
                session.tracksSelection.removeAll()
            }
        )
    }

    private func applyTrackSelection(
        _ trackID: UUID,
        gesture: StudioSelectionGesture
    ) {
        applyTracksSelection([trackID], gesture: gesture)
    }

    private func applyTracksSelection(
        _ trackIDs: [UUID],
        gesture: StudioSelectionGesture
    ) {
        guard let firstTrackID = trackIDs.first else { return }
        let nextSelection = gesture.selection(
            targeting: Set(trackIDs),
            in: session.tracksSelection
        )

        if nextSelection.isEmpty {
            session.tracksSelection.removeAll()
            session.tracksSelectionMode = false
        } else {
            session.tracksSelectionMode = true
            session.tracksSelection = nextSelection
        }
        session.setSelectedTrackID(firstTrackID)
    }

    /// One flat navigator grid: ungrouped track cells, then each kit (a single
    /// kit cell when collapsed, or the kit cell followed inline by its per-part
    /// cells when expanded), then the add-track tile. Kit cells reuse the same
    /// cell chrome + footprint as normal track cells — no surrounding wrapper
    /// section. The expand/collapse affordance lives ON the kit cell itself.
    private func matrixSections(
        items: [TracksNavigatorPresentationItem],
        tracks: [StepSequenceTrack],
        groups: [TrackGroup],
        selectedTrackID: UUID
    ) -> some View {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                switch item {
                case .track(let trackID):
                    if let track = tracksByID[trackID] {
                        #if DEBUG
                        let _ = { TracksPageInvalidationProbe.cardContentEvaluations += 1 }()
                        #endif
                        let group = track.groupID.flatMap { groupsByID[$0] }
                        trackCell(track, group: group, selectedTrackID: selectedTrackID)
                    }
                case .kit(let groupID):
                    if let group = groupsByID[groupID] {
                        let section = GroupedTrackSection(
                            group: group,
                            members: group.memberIDs.compactMap { tracksByID[$0] }
                        )
                        kitCell(section: section, selectedTrackID: selectedTrackID)
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
            onSelectKit: { gesture in
                applyTracksSelection(memberIDs, gesture: gesture)
            },
            onAddPart: {
                if let createdID = session.addDefaultDrumPart(groupID: section.group.id) {
                    session.setSelectedTrackID(createdID)
                    onOpenTrack()
                }
            },
            onOpenKit: {
                if let representativeTrackID {
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
            onSelect: { gesture in
                applyTrackSelection(track.id, gesture: gesture)
            }
        ) {
            session.setSelectedTrackID(track.id)
            onOpenTrack()
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
            createTrackStep = .pickType
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
    let onSelectKit: (StudioSelectionGesture) -> Void
    let onAddPart: () -> Void
    let onOpenKit: () -> Void
    let onToggleExpand: () -> Void

    // Group identity accent shared with this kit's member parts.
    private var accent: Color {
        StudioTheme.groupAccent(for: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(group.name)
                    .studioText(.subtitle)
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if !isSelectionMode, isCollapsed {
                    // The expand/collapse affordance lives ON the cell.
                    Button(action: onToggleExpand) {
                        Image(systemName: isCollapsed
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .background(StudioTheme.subtleFill, in: Circle())
                            .overlay(Circle().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(isCollapsed ? "kit-expand" : "kit-collapse")
                    .help(isCollapsed
                        ? "Expand \(group.name) to its per-part cells"
                        : "Collapse \(group.name) back to one cell")
                } else {
                    Button(action: onToggleExpand) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kit-collapse")
                    .help("Collapse \(group.name) back to one cell")
                }
            }

            // The contained parts shown as small cells inside the kit cell, for
            // indication, while collapsed. When expanded they live in the grid
            // as sibling cells instead, so the strip is hidden.
            if partNames.isEmpty {
                emptyPartAction
            } else if isCollapsed {
                partThumbnailStrip
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(partNames.count) PARTS")
                    Text(patternSlotLabel)
                }
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(isSelected ? accent : StudioTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    isSelected ? accent : accent.opacity(isFocused ? 0.86 : StudioOpacity.accentStroke),
                    lineWidth: (isSelected || isFocused) ? 2 : StudioMetrics.borderWidth
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture(perform: onOpenKit)
        .studioSelectionGesture { gesture in
            onSelectKit(gesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.name)
        .accessibilityValue("Drum kit, \(partNames.count) parts\(isSelected ? ", selected" : "")")
        .accessibilityIdentifier("kit-collapsed-cell")
        .help("\(group.name), drum kit")
    }

    private var emptyPartAction: some View {
        Button(action: onAddPart) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add Part")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(accent.opacity(StudioOpacity.accentFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous).stroke(accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("kit-add-first-part")
        .help("Add the first part to \(group.name)")
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
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? accent : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous).stroke(isSelected ? StudioTheme.background : accent.opacity(StudioOpacity.accentStroke), lineWidth: StudioMetrics.borderWidth))
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(isSelected ? StudioTheme.background : accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(isSelected ? accent : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous).stroke(isSelected ? StudioTheme.background : accent, lineWidth: StudioMetrics.borderWidth))
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
            accent: StudioTheme.phraseAccent,
            minWidth: 500,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: 16) {
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
                        .foregroundStyle(phrase.id == basisPhraseID ? StudioTheme.phraseAccent : StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(.horizontal, 10)
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(phrase.id == basisPhraseID ? StudioTheme.phraseAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .help("Capture edits to \(phrase.name)")

        case .new:
            Button(action: onCaptureNew) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("+ New")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.phraseAccent)

                    Text("phrase")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(.horizontal, 10)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.phraseAccent, lineWidth: StudioMetrics.borderWidth)
                )
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
    let onSelect: (StudioSelectionGesture) -> Void
    let onTap: () -> Void

    // Identity hue (bug 20260629-100436): a grouped part shares its kit's hue so
    // they read as one group; an ungrouped track gets a stable per-track palette
    // colour derived from its id. Selection is encoded by the outline, not the
    // hue, so identity and selection no longer collide.
    private var accent: Color {
        if let group {
            return StudioTheme.groupAccent(for: group)
        }
        return StudioTheme.trackAccent(for: track)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(track.name)
                    .studioText(.subtitle)
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSelected ? StudioTheme.background : accent)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(isSelected ? StudioTheme.background : accent, lineWidth: StudioMetrics.borderWidth))
                        .accessibilityIdentifier("track-card-muted")
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.comfortable)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .fill(isSelected ? accent : StudioTheme.subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            onTap()
        }
        .studioSelectionGesture { gesture in
            onSelect(gesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.name)
        .accessibilityValue("\(group == nil ? track.trackType.label : "Drum part")\(isSelected ? ", selected" : "")")
        .help("\(track.name), \(group == nil ? track.trackType.label : "drum part")")
    }

    private var strokeColor: Color {
        if isSelected { return accent }
        return accent.opacity(isFocused ? 0.86 : StudioOpacity.accentStroke)
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
                        .foregroundStyle(StudioTheme.phraseAccent)
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
                    .foregroundStyle(StudioTheme.phraseAccent)
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
            return StudioTheme.phraseAccent
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
        StudioTheme.subtleFill
    }

    private func labelStroke(cuePresentation: QuantisedFillCuePresentation, isActive: Bool) -> Color {
        if !state.isAvailable {
            return StudioTheme.border
        }
        // Armed = dashed phrase accent; applies-at-boundary = solid phrase
        // accent for the cued bar (the armed-toggle grammar, wireframes §2).
        if cuePresentation.isPending || cuePresentation.isCueBarActive {
            return StudioTheme.phraseAccent
        }
        if state.isMomentaryPressed {
            return StudioTheme.phraseAccent
        }
        if state.isLatched {
            return accent
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
