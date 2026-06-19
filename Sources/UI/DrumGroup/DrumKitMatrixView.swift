import SwiftUI

/// Matrix-wide step layer. The same layer set the single-track step editor
/// offers for note-grid clips (`ClipEditorMode`): on/off triggers, velocity,
/// and chance. Macro lanes are per-track bindings and stay single-track only.
/// Kit-altitude tab bar (track-view IA, AC13/AC23). The tabs operate at
/// KIT-BUS scope, distinct from the per-part FX/Macros/Mixer reached by
/// diving into a single part. Capture + Perform are header buttons, NOT tabs.
enum DrumKitTab: String, CaseIterable, Identifiable {
    case matrix
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matrix:
            return "Matrix"
        case .fx:
            return "FX"
        case .macros:
            return "Macros"
        case .mixer:
            return "Mixer"
        }
    }
}

enum DrumKitMatrixLayer: String, CaseIterable, Identifiable {
    case steps
    case velocity
    case chance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:
            return "Steps"
        case .velocity:
            return "Velocity"
        case .chance:
            return "Chance"
        }
    }
}

/// Pure cell-edit transforms for the kit matrix. Delegates to
/// `ClipNoteGridStepEditing` — the same implementation the single-track clip
/// editor commits through — so a matrix edit is the identical mutation.
enum DrumKitMatrixStepEdit {
    static func tappedContent(
        layer: DrumKitMatrixLayer,
        stepIndex: Int,
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent? {
        guard steps.indices.contains(stepIndex) else { return nil }
        switch layer {
        case .steps:
            return ClipNoteGridStepEditing.togglingStep(
                at: stepIndex,
                lengthSteps: lengthSteps,
                steps: steps,
                lane: .main,
                defaultNote: defaultNote
            )
        case .velocity:
            let nextValue = ClipNoteGridStepEditing.cycledValue(
                after: ClipNoteGridStepEditing.velocityValue(for: steps[stepIndex], lane: .main),
                allowedValues: ClipNoteGridStepEditing.velocityCycleValues
            )
            return ClipNoteGridStepEditing.updatingLaneVelocities(
                lane: .main,
                values: [nextValue],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        case .chance:
            let nextValue = ClipNoteGridStepEditing.cycledValue(
                after: ClipNoteGridStepEditing.chanceValue(for: steps[stepIndex], lane: .main),
                allowedValues: ClipNoteGridStepEditing.chanceCycleValues
            )
            return ClipNoteGridStepEditing.updatingLaneChances(
                lane: .main,
                values: [nextValue],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        }
    }

    static func draggedContent(
        layer: DrumKitMatrixLayer,
        stepIndex: Int,
        fraction: Double,
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent? {
        guard steps.indices.contains(stepIndex) else { return nil }
        switch layer {
        case .steps:
            return nil
        case .velocity:
            return ClipNoteGridStepEditing.updatingLaneVelocities(
                lane: .main,
                values: [fraction * 127.0],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        case .chance:
            return ClipNoteGridStepEditing.updatingLaneChances(
                lane: .main,
                values: [fraction],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        }
    }
}

struct DrumKitMatrixModel: Equatable {
    struct Row: Identifiable, Equatable {
        /// What the row's active pattern slot resolves to.
        enum Content: Equatable {
            /// Note-grid clip (or empty clip slot — materialized on first
            /// edit, exactly like the single-track editor).
            case editable(clipID: UUID?, lengthSteps: Int, steps: [ClipStep])
            /// Generator-backed slot: generator badge, read-only cells,
            /// no inline editing (v1 conservative treatment).
            case generator(detail: String)
            /// Clip content the step grid cannot represent (slice triggers).
            case readOnly(badge: String, detail: String, steps: [Bool])
        }

        var id: UUID { memberID }

        var memberID: UUID
        var partName: String
        var patternSlotIndex: Int
        var sourceMode: TrackSourceMode
        var content: Content
        var isDivergentPattern: Bool
        var defaultNote: ClipStepNote

        var patternBadge: String {
            "P\(patternSlotIndex + 1)"
        }

        var isEditable: Bool {
            if case .editable = content { return true }
            return false
        }
    }

    var groupID: TrackGroupID
    var groupName: String
    var colorHex: String
    var originatingPartID: UUID
    var displayStepCount: Int
    var rows: [Row]
    var staleMemberCount: Int
    /// Pattern slots where at least one member holds a non-empty source.
    var occupiedSlotIndexes: Set<Int>
    /// The group's explicit pattern-link intent (AC17). Linking gangs pattern
    /// slot selection only; mute/fill/macros stay per-part.
    var isPatternLinked: Bool

    var memberCountLabel: String {
        "\(rows.count) part\(rows.count == 1 ? "" : "s")"
    }

    var hasPatternMismatch: Bool {
        rows.contains(where: \.isDivergentPattern)
    }

    /// The slot every member shares, or nil when members diverge (mixed state).
    var groupSelectedSlotIndex: Int? {
        guard let first = rows.first?.patternSlotIndex else { return nil }
        return rows.allSatisfy { $0.patternSlotIndex == first } ? first : nil
    }

    /// Structural divergence (AC20): the kit intends to be linked, but members
    /// sit on different pattern slots, so the link is effectively broken until
    /// re-linked. This is the condition that surfaces the one-click "Re-link".
    var isLinkBroken: Bool {
        isPatternLinked && groupSelectedSlotIndex == nil && rows.count > 1
    }

    init?(
        groupID: TrackGroupID,
        originatingPartID: UUID,
        displayStepCount: Int,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup],
        layers: [PhraseLayerDefinition],
        selectedPhrase: PhraseModel,
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry],
        generatorPool: [GeneratorPoolEntry]
    ) {
        guard let group = trackGroups.first(where: { $0.id == groupID }) else {
            return nil
        }

        let resolvedDisplayStepCount = displayStepCount == 32 ? 32 : 16
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var seenMemberIDs: Set<UUID> = []
        let orderedMembers = group.memberIDs.compactMap { memberID -> StepSequenceTrack? in
            guard seenMemberIDs.insert(memberID).inserted else { return nil }
            return tracksByID[memberID]
        }
        let resolvedMemberIDs = Set(orderedMembers.map(\.id))
        let staleMemberCount = Set(group.memberIDs).subtracting(resolvedMemberIDs).count
        let firstPatternSlot = orderedMembers.first.map {
            selectedPhrase.patternIndex(for: $0.id, layers: layers)
        }

        self.groupID = group.id
        self.groupName = group.name
        self.colorHex = group.color
        self.originatingPartID = originatingPartID
        self.displayStepCount = resolvedDisplayStepCount
        self.staleMemberCount = staleMemberCount
        self.isPatternLinked = group.isPatternLinked
        self.rows = orderedMembers.map { track in
            let patternSlotIndex = selectedPhrase.patternIndex(for: track.id, layers: layers)
            let patternBank = Self.patternBank(
                for: track,
                patternBanks: patternBanks,
                clipPool: clipPool
            )
            let patternSlot = patternBank.slot(at: patternSlotIndex)
            return Row(
                memberID: track.id,
                partName: track.name,
                patternSlotIndex: patternSlotIndex,
                sourceMode: patternSlot.sourceRef.mode,
                content: Self.content(
                    patternSlot: patternSlot,
                    clipPool: clipPool,
                    generatorPool: generatorPool
                ),
                isDivergentPattern: firstPatternSlot.map { patternSlotIndex != $0 } ?? false,
                defaultNote: ClipStepNote(
                    pitch: track.pitches.first ?? 60,
                    velocity: track.velocity,
                    lengthSteps: track.gateLength
                ).normalized
            )
        }
        self.occupiedSlotIndexes = Self.occupiedSlots(
            members: orderedMembers,
            patternBanks: patternBanks,
            clipPool: clipPool
        )
    }

    private static func patternBank(
        for track: StepSequenceTrack,
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        if let existing = patternBanks.first(where: { $0.trackID == track.id }) {
            return existing
        }
        let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
        return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
    }

    private static func content(
        patternSlot: TrackPatternSlot,
        clipPool: [ClipPoolEntry],
        generatorPool: [GeneratorPoolEntry]
    ) -> Row.Content {
        switch patternSlot.sourceRef.mode {
        case .generator:
            if let generator = generatorPool.first(where: { $0.id == patternSlot.sourceRef.generatorID }) {
                return .generator(detail: generator.name)
            }
            return .generator(detail: "Generator unavailable")
        case .clip:
            guard let clipID = patternSlot.sourceRef.clipID,
                  let clip = clipPool.first(where: { $0.id == clipID })
            else {
                // Empty slot: render an empty 16-step grid; the first edit
                // materializes a clip through `ensureClipAndMutate`. (The
                // single-track editor never edits an empty slot — its clip
                // panel only shows for an occupied clip — so the matrix is
                // the one surface that still needs the slot-address key.)
                return .editable(
                    clipID: nil,
                    lengthSteps: 16,
                    steps: Array(repeating: .empty, count: 16)
                )
            }
            let normalized = clip.content.normalized
            guard let steps = normalized.noteGridSteps,
                  let lengthSteps = normalized.noteGridLengthSteps
            else {
                let pattern: [Bool]
                if case let .sliceTriggers(stepPattern, _, _, _) = normalized {
                    pattern = stepPattern
                } else {
                    pattern = []
                }
                return .readOnly(badge: "RO", detail: "Read-only source", steps: pattern)
            }
            return .editable(clipID: clip.id, lengthSteps: lengthSteps, steps: steps)
        }
    }

    private static func occupiedSlots(
        members: [StepSequenceTrack],
        patternBanks: [TrackPatternBank],
        clipPool: [ClipPoolEntry]
    ) -> Set<Int> {
        let clipsByID = Dictionary(uniqueKeysWithValues: clipPool.map { ($0.id, $0) })
        var occupied: Set<Int> = []
        for member in members {
            let bank = patternBank(for: member, patternBanks: patternBanks, clipPool: clipPool)
            for slot in bank.slots where !occupied.contains(slot.slotIndex) {
                switch slot.sourceRef.mode {
                case .generator:
                    if slot.sourceRef.generatorID != nil {
                        occupied.insert(slot.slotIndex)
                    }
                case .clip:
                    if let clipID = slot.sourceRef.clipID,
                       let clip = clipsByID[clipID],
                       !clipIsEmpty(clip.content) {
                        occupied.insert(slot.slotIndex)
                    }
                }
            }
        }
        return occupied
    }
}

struct DrumKitMatrixView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    let navigationState: DrumKitWorkspaceNavigationState
    /// When the matrix is the track editor's home (kit-first), there is no
    /// "back" target above it, so the back affordance is hidden. Defaults to
    /// `true` so any other caller keeps the original behaviour.
    var showsBackButton = true
    let onBack: () -> Void
    let onSelectPart: (UUID) -> Void

    /// Fixed 16-step grid; paging across bars replaces the old 16/32 toggle.
    private static let stepsPerBar = 16
    /// Which 16-step bar window is visible for every row in lockstep.
    @State private var barPage = 0
    @State private var selectedLayer: DrumKitMatrixLayer = .steps
    @State private var isPresentingRoutingEditor = false
    @State private var isPresentingTemplateChooser = false
    /// Which kit-bus tab is shown (Matrix · FX · Macros · Mixer). Ignored while
    /// `isCaptureOpen` is true — Capture replaces the tab body (AC14 header).
    @State private var kitTab: DrumKitTab = .matrix
    /// Capture surface replaces the tab content; the Patterns row stays visible
    /// above it so a captured set can be assigned to a slot (AC12/AC14).
    @State private var isCaptureOpen = false
    /// "+ FX" picker for the kit bus (AC23 kit FX).
    @State private var isPresentingKitFX = false

    private var model: DrumKitMatrixModel? {
        DrumKitMatrixModel(
            groupID: navigationState.groupID,
            originatingPartID: navigationState.originatingPartID,
            displayStepCount: Self.stepsPerBar,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups,
            layers: session.store.layers,
            selectedPhrase: session.store.selectedPhrase,
            patternBanks: Array(session.store.patternBanksByTrackID.values),
            clipPool: session.store.clipPool,
            generatorPool: session.store.generatorPool
        )
    }

    private var accent: Color {
        Color(hex: model?.colorHex ?? "") ?? StudioTheme.success
    }

    /// The kit's own bus, resolved from its members' `outputBusID` (kits route
    /// to a dedicated bus by default). The first member with a resolvable bus
    /// wins; nil means the kit is on Master / unrouted, in which case the FX
    /// and Mixer tabs show an explanatory empty state. (AC23 kit-bus scope.)
    private func kitBus(_ model: DrumKitMatrixModel) -> MixerBus? {
        let buses = session.store.buses
        let tracksByID = Dictionary(
            uniqueKeysWithValues: session.store.tracks.map { ($0.id, $0) }
        )
        for row in model.rows {
            guard let busID = tracksByID[row.memberID]?.outputBusID,
                  let bus = buses.first(where: { $0.id == busID })
            else { continue }
            return bus
        }
        return nil
    }

    /// Longest editable/read-only row length, in steps, across the kit. Drives
    /// how many 16-step bar pages the pager offers.
    private func longestRowLength(_ model: DrumKitMatrixModel) -> Int {
        var maxLength = Self.stepsPerBar
        for row in model.rows {
            switch row.content {
            case let .editable(_, lengthSteps, steps):
                maxLength = max(maxLength, max(lengthSteps, steps.count))
            case let .readOnly(_, _, steps):
                maxLength = max(maxLength, steps.count)
            case .generator:
                break
            }
        }
        return maxLength
    }

    /// Number of 16-step bar pages, at least one.
    private func barPageCount(_ model: DrumKitMatrixModel) -> Int {
        let length = longestRowLength(model)
        return max(1, (length + Self.stepsPerBar - 1) / Self.stepsPerBar)
    }

    /// `barPage` clamped to the valid range for the current model.
    private func clampedPage(_ model: DrumKitMatrixModel) -> Int {
        min(max(0, barPage), barPageCount(model) - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let model {
                kitBody(model)
            } else {
                unavailableState
            }
        }
        .padding(StudioMetrics.Spacing.section)
        .sheet(isPresented: $isPresentingRoutingEditor) {
            if let draft = DrumGroupRoutingEditorDraft(
                groupID: navigationState.groupID,
                trackGroups: session.store.trackGroups,
                tracks: session.store.tracks
            ) {
                DrumGroupRoutingEditorSheet(
                    draft: draft,
                    audioInstrumentChoices: engineController.availableAudioInstruments,
                    onApply: { routingDraft in
                        session.applyDrumGroupRoutingDraft(routingDraft)
                        isPresentingRoutingEditor = false
                    },
                    onCancel: {
                        isPresentingRoutingEditor = false
                    }
                )
            } else {
                Text("Routing editor unavailable")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(StudioMetrics.Spacing.page)
                    .background(StudioTheme.stageFill)
            }
        }
        .sheet(isPresented: $isPresentingTemplateChooser) {
            if let model,
               let group = session.store.trackGroups.first(where: { $0.id == model.groupID }) {
                DrumKitTemplateChooserSheet(
                    groupName: model.groupName,
                    targetSlotIndex: model.groupSelectedSlotIndex ?? model.rows.first?.patternSlotIndex ?? 0,
                    previewProvider: { template, slotIndex in
                        PatternTemplateApplicationPreview(
                            template: template,
                            group: group,
                            tracks: session.store.tracks,
                            patternBanks: Array(session.store.patternBanksByTrackID.values),
                            clipPool: session.store.clipPool,
                            slotIndex: slotIndex
                        )
                    },
                    onApply: { template, slotIndex in
                        session.applyPatternTemplate(template, toGroup: group.id, slotIndex: slotIndex)
                        isPresentingTemplateChooser = false
                    },
                    onCancel: {
                        isPresentingTemplateChooser = false
                    }
                )
            } else {
                Text("Template chooser unavailable")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(StudioMetrics.Spacing.page)
                    .background(StudioTheme.stageFill)
            }
        }
        .sheet(isPresented: $isPresentingKitFX) {
            kitFXChooserSheet
        }
        .onAppear {
            postRenderedVisualState(isVisible: true)
        }
        .onDisappear {
            postRenderedVisualState(isVisible: false)
        }
        .onChange(of: barPage) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: selectedLayer) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: kitTab) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isCaptureOpen) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isPresentingRoutingEditor) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isPresentingTemplateChooser) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: session.revision) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: navigationState) {
            postRenderedVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumKitMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    private func postRenderedVisualState(isVisible: Bool) {
        let groupSlot = model?.groupSelectedSlotIndex
        NotificationCenter.default.post(
            name: .drumKitMatrixRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "routingEditorVisible": isVisible && isPresentingRoutingEditor,
                "templateChooserVisible": isVisible && isPresentingTemplateChooser,
                "displayStepCount": Self.stepsPerBar,
                "barPage": isVisible ? (model.map(clampedPage) ?? 0) : 0,
                "barPageCount": isVisible ? (model.map(barPageCount) ?? 1) : 1,
                "layer": isVisible ? selectedLayer.rawValue : "none",
                "groupPatternSlot": isVisible ? (groupSlot.map { "\($0 + 1)" } ?? "mixed") : "none",
                "patternLinked": isVisible && (model?.isPatternLinked ?? false),
                "patternLinkBroken": isVisible && (model?.isLinkBroken ?? false),
                "groupName": isVisible ? model?.groupName ?? "none" : "none",
                "memberCount": isVisible ? model?.rows.count ?? 0 : 0,
                "kitTab": isVisible ? (isCaptureOpen ? "capture" : kitTab.rawValue) : "none",
                "captureOpen": isVisible && isCaptureOpen,
                "kitFXChooserVisible": isVisible && isPresentingKitFX,
            ]
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .studioText(.labelBold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                    Text(model?.groupName ?? "Kit")
                        .studioText(.display)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text("\(model?.memberCountLabel ?? "No parts") · 16 steps/bar")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            headerSecondaryButton(title: "Routing", systemImage: "slider.horizontal.3") {
                isPresentingRoutingEditor = true
            }
            .help("Edit the kit's trigger routing and destinations")

            captureButton

            performButton
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func headerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.background)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    /// Neutral header chip (Routing). Distinct from the accent-filled
    /// `headerActionButton` so Capture/Perform read as the primary header pair.
    private func headerSecondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Capture header button (AC13/AC14). Toggles the history surface that
    /// replaces the tab content while the Patterns row stays visible. When
    /// open it reads as selected (accent fill).
    private var captureButton: some View {
        Button {
            isCaptureOpen.toggle()
        } label: {
            Label("Capture", systemImage: "smallcircle.filled.circle")
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCaptureOpen ? StudioTheme.background : StudioTheme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isCaptureOpen ? accent : Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(isCaptureOpen ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .help("Capture: open the kit history surface to save a coordinated clip set")
        .accessibilityIdentifier("kit-capture")
        .accessibilityLabel("Capture kit history")
        .accessibilityValue(isCaptureOpen ? "Open" : "Closed")
    }

    /// Perform header button (AC13). Scoped phrase-perform for the whole kit is
    /// a later slice; for now this posts a notification so QA can observe the
    /// intent without a bespoke surface (see spec AC22).
    private var performButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .drumKitPerformRequested,
                object: navigationState.groupID
            )
        } label: {
            Label("Perform", systemImage: "play.fill")
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.background)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .help("Perform: open the phrase perform UI scoped to the whole kit (coming soon)")
        .accessibilityIdentifier("kit-perform")
        .accessibilityLabel("Perform kit")
    }

    /// Bar pager: one button per 16-step bar (1–16, 17–32, …), shown only when
    /// the kit's longest row spans more than one bar. Selecting a page moves the
    /// visible 16-step window for every part row in lockstep.
    @ViewBuilder
    private func barPager(_ model: DrumKitMatrixModel) -> some View {
        let pageCount = barPageCount(model)
        if pageCount > 1 {
            let current = clampedPage(model)
            HStack(spacing: 6) {
                Text("BAR")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        barPageButton(page, isSelected: page == current)
                    }
                }
                .padding(3)
                .background(
                    Color.white.opacity(StudioOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
                )
            }
        }
    }

    private func barPageButton(_ page: Int, isSelected: Bool) -> some View {
        let lower = page * Self.stepsPerBar + 1
        let upper = (page + 1) * Self.stepsPerBar
        let title = "\(lower)–\(upper)"

        return Button {
            barPage = page
        } label: {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 56, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help("Show steps \(title)")
        .accessibilityLabel("Bar \(title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    /// Kit page layout (AC12/AC13/AC14): persistent Patterns row, then either
    /// the Capture history surface (replaces the tabs) or the kit tab bar +
    /// selected tab body. The Patterns row is ALWAYS above and stays visible
    /// across every tab and during Capture.
    @ViewBuilder
    private func kitBody(_ model: DrumKitMatrixModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.rows.isEmpty {
                persistentPatternsRow(model)
            }

            if isCaptureOpen {
                captureHistoryBody(model)
            } else {
                kitTabBar
                selectedKitTabBody(model)
            }
        }
    }

    /// Persistent Patterns row, framed as its own panel so it reads as a fixed
    /// assignment surface above the tab bar (AC12).
    private func persistentPatternsRow(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Patterns", accent: accent) {
            groupPatternRow(model)
        }
    }

    /// Matrix · FX · Macros · Mixer (AC13). Hidden while Capture is open.
    private var kitTabBar: some View {
        HStack(spacing: 4) {
            ForEach(DrumKitTab.allCases) { tab in
                kitTabButton(tab)
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func kitTabButton(_ tab: DrumKitTab) -> some View {
        let isSelected = kitTab == tab
        return Button {
            kitTab = tab
        } label: {
            Text(tab.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 72, minHeight: 30)
                .padding(.horizontal, 10)
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("kit-tab-\(tab.rawValue)")
        .accessibilityLabel("Kit tab \(tab.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func selectedKitTabBody(_ model: DrumKitMatrixModel) -> some View {
        switch kitTab {
        case .matrix:
            matrixTabBody(model)
        case .fx:
            kitFXTabBody(model)
        case .macros:
            kitMacrosTabBody(model)
        case .mixer:
            kitMixerTabBody(model)
        }
    }

    /// Matrix tab: the existing matrix content, minus the group pattern row
    /// (which now lives in the persistent Patterns row above). (AC23)
    @ViewBuilder
    private func matrixTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Matrix", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    layerSelector

                    barPager(model)

                    Spacer(minLength: 0)

                    if model.hasPatternMismatch {
                        mismatchBadge
                    }

                    headerActionButton(title: "Apply Template…", systemImage: "square.grid.2x2") {
                        isPresentingTemplateChooser = true
                    }
                    .help("Apply a pattern template into the selected group pattern slot")
                }

                if model.staleMemberCount > 0 {
                    staleMemberBanner(count: model.staleMemberCount)
                }

                if model.rows.isEmpty {
                    emptyRowsState
                } else {
                    matrixRows(model)
                }
            }
        }
    }

    // MARK: - Kit FX tab (AC23: insert chain on the kit's own bus)

    /// FX tab: the insert chain on the kit's dedicated bus, so the inserts
    /// process every part together. Reuses the existing per-bus insert model
    /// (`MixerBusInsert`) + session mutations (`addMixerBusInsert` etc.).
    @ViewBuilder
    private func kitFXTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit FX", eyebrow: kitFXEyebrow(model), accent: accent) {
            if let bus = kitBus(model) {
                KitBusFXChainView(
                    inserts: bus.inserts,
                    accent: accent,
                    onAddFX: { isPresentingKitFX = true },
                    onRemove: { insertID in
                        session.removeMixerBusInsert(insertID, busID: bus.id)
                    },
                    onMove: { source, destination in
                        moveKitBusInserts(bus: bus, from: source, to: destination)
                    },
                    onSetBypassed: { insertID, bypassed in
                        session.updateMixerBusInsert(insertID, busID: bus.id) { insert in
                            insert.isEnabled = !bypassed
                        }
                    }
                )
            } else {
                kitBusUnavailableState
            }
        }
    }

    private func kitFXEyebrow(_ model: DrumKitMatrixModel) -> String {
        if let bus = kitBus(model) {
            return "Insert chain on \(bus.name) (whole kit)"
        }
        return "Kit bus unavailable"
    }

    /// `List.onMove` gives index-based moves; the bus session API reorders by an
    /// explicit id list, so translate the move into the new ordering.
    private func moveKitBusInserts(bus: MixerBus, from source: IndexSet, to destination: Int) {
        var ids = bus.inserts.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        session.reorderMixerBusInserts(ids, busID: bus.id)
    }

    private var kitBusUnavailableState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This kit is not on a dedicated bus")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
            Text("Route the kit to its own bus (Routing) to add kit-wide FX.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.loose)
    }

    /// "+ FX" picker for the kit bus, mirroring the per-track Add FX sheet but
    /// committing a `MixerBusInsert` to the kit's bus (AC23).
    @ViewBuilder
    private var kitFXChooserSheet: some View {
        if let model, let bus = kitBus(model) {
            let effects = engineController.availableAudioEffects
            let busID = bus.id
            StudioModal(
                title: "Add Kit FX",
                accent: accent,
                minWidth: 360,
                onClose: { isPresentingKitFX = false }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    kitFXOptionButton(title: "Filter", systemName: "line.3.horizontal.decrease.circle") {
                        session.addMixerBusInsert(.filter(), busID: busID)
                        isPresentingKitFX = false
                    }
                    kitFXOptionButton(title: "Bitcrusher", systemName: "waveform.path.ecg") {
                        session.addMixerBusInsert(.bitcrusher(), busID: busID)
                        isPresentingKitFX = false
                    }
                }

                Divider()
                    .overlay(StudioTheme.border)

                Text("AU Effect")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                if effects.isEmpty {
                    Text("No AU effects found")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(effects.prefix(16)) { effect in
                                kitFXOptionButton(title: effect.displayName, systemName: "slider.horizontal.3") {
                                    session.addMixerBusInsert(.auEffect(effect), busID: busID)
                                    isPresentingKitFX = false
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .scrollContentBackground(.hidden)
                }
            }
            .presentationBackground(.clear)
            .environment(\.colorScheme, .dark)
        } else {
            Text("Kit bus unavailable")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
                .padding(StudioMetrics.Spacing.page)
                .background(StudioTheme.stageFill)
        }
    }

    private func kitFXOptionButton(
        title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kit Macros tab (AC23: M1–M8 across the kit / bus)

    /// Macros tab: a styled M1–M8 surface reusing `AUMacroSlotKnob`. It mirrors
    /// the originating part's macro bindings as a representative kit view.
    /// STUBBED: full cross-part / bus macro wiring (sweeping one parameter
    /// across every part at once) is a later slice; the knobs render the kit's
    /// default mappings but do not yet drive every part — see report.
    @ViewBuilder
    private func kitMacrosTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Macros", eyebrow: "M1–M8 across the whole kit / its bus", accent: accent) {
            let slots = kitMacroSlots(model)
            LazyVGrid(columns: Self.macroColumns, alignment: .leading, spacing: 14) {
                ForEach(slots) { slot in
                    AUMacroSlotKnob(
                        slotIndex: slot.slotIndex,
                        binding: slot.binding,
                        value: nil,
                        onAssign: {},
                        onChange: { _ in }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private static let macroColumns = Array(
        repeating: GridItem(.flexible(), spacing: 14),
        count: 4
    )

    /// Eight slots (M1–M8) seeded from the originating part's macro bindings so
    /// the kit view reflects the seeded drum-part defaults (M1 dir / M2 len /
    /// M3 cutoff). Unbound slots render as assignable knobs.
    private func kitMacroSlots(_ model: DrumKitMatrixModel) -> [MacroSlot] {
        let originating = session.store.tracks.first { $0.id == model.originatingPartID }
        let bindings = originating?.macros ?? []
        return (0..<8).map { slotIndex in
            MacroSlot(
                slotIndex: slotIndex,
                binding: bindings.first { $0.slotIndex == slotIndex }
            )
        }
    }

    // MARK: - Kit Mixer tab (AC23: bus output + sends + per-part levels)

    /// Mixer tab: the kit bus output (→ its destination) and a per-part level
    /// row each (reusing `session.setTrackMix`). Send A/B and bus output
    /// routing are shown as the bus summary; full bus-strip editing is reachable
    /// from the global Mixer — see report for what is real vs summarized.
    @ViewBuilder
    private func kitMixerTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Mixer", eyebrow: "Bus output + per-part levels", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                kitBusOutputRow(model)

                Text("PER-PART LEVELS")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.rows) { row in
                        kitPartLevelRow(row)
                    }
                }
            }
        }
    }

    private func kitBusOutputRow(_ model: DrumKitMatrixModel) -> some View {
        let bus = kitBus(model)
        let outputTitle = bus.map { "→ \($0.name) → Master" } ?? "→ Master"
        return HStack(spacing: 10) {
            Text("BUS OUTPUT")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Text(outputTitle)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(StudioOpacity.hoverFill), in: Capsule())

            Spacer(minLength: 0)

            kitSendBadge("A")
            kitSendBadge("B")
        }
    }

    private func kitSendBadge(_ label: String) -> some View {
        Text("Send \(label)")
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
            .overlay(
                Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
    }

    private func kitPartLevelRow(_ row: DrumKitMatrixModel.Row) -> some View {
        let track = session.store.tracks.first { $0.id == row.memberID }
        let level = track?.mix.level ?? 0
        let percent = Int((level * 100).rounded())
        return HStack(spacing: 12) {
            Text(row.partName)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Slider(
                value: kitPartLevelBinding(memberID: row.memberID, track: track),
                in: 0...1
            )
            .tint(accent)

            Text("\(percent)%")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func kitPartLevelBinding(memberID: UUID, track: StepSequenceTrack?) -> Binding<Double> {
        Binding(
            get: { track?.mix.level ?? 0 },
            set: { newValue in
                guard var mix = session.store.tracks.first(where: { $0.id == memberID })?.mix else { return }
                mix.level = newValue
                session.setTrackMix(trackID: memberID, mix: mix)
            }
        )
    }

    // MARK: - Capture / History body (AC14 header interaction)

    /// Capture surface — replaces the tab content while the Patterns row stays
    /// above (AC12/AC14). STUBBED: the full all-parts history scrubber + save-
    /// as-clip-set content is a later slice; for now this is a styled placeholder
    /// body with a "Close capture" affordance back to the tabs.
    @ViewBuilder
    private func captureHistoryBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Capture · History", eyebrow: "Live buffer · all parts", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        isCaptureOpen = false
                    } label: {
                        Label("Close capture", systemImage: "chevron.left")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("kit-capture-close")
                    .accessibilityLabel("Close capture")

                    Spacer(minLength: 0)
                }

                Text("Capture replaces the tabs; the Patterns row above stays so a captured clip set can be assigned to a slot.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.rows) { row in
                        Text(row.partName)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    }
                }

                Text("All-parts history scrubber + save-as-clip-set arrive in a later slice.")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
    }

    /// Group-level 1–16 pattern row, styled like a track's pattern selector.
    /// Selecting slot N fans the existing per-track pattern switch out to
    /// every member; a mixed state (no selected slot) renders when members
    /// diverge, and selecting any slot realigns them.
    private func groupPatternRow(_ model: DrumKitMatrixModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("GROUP PATTERN")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                linkToggle(model)

                if model.isLinkBroken {
                    mixedBadge
                    reLinkButton
                } else if model.groupSelectedSlotIndex == nil && model.rows.count > 1 {
                    mixedBadge
                }

                Spacer(minLength: 0)
            }

            TrackPatternSlotPalette(
                selectedSlot: groupPatternSlotBinding(model),
                occupiedSlots: model.occupiedSlotIndexes,
                bypassState: .notApplicable,
                onBypassToggle: { _ in }
            )
        }
    }

    /// Explicit pattern-link toggle (AC17). Linked ⛓ gangs slot selection only;
    /// mute/fill/macros stay per-part. The pill reflects and flips the group's
    /// persisted `isPatternLinked`.
    private func linkToggle(_ model: DrumKitMatrixModel) -> some View {
        let linked = model.isPatternLinked
        let title = linked ? "Linked" : "Unlinked"
        let symbol = linked ? "link" : "link.badge.plus"
        return Button {
            session.setDrumGroupPatternLinked(!linked, groupID: navigationState.groupID)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .studioText(.microEmphasis)
                    .tracking(0.6)
            }
            .foregroundStyle(linked ? StudioTheme.background : StudioTheme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                linked ? accent : Color.white.opacity(StudioOpacity.subtleFill),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(linked ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .help(linked
            ? "Linked: selecting a group pattern switches every part to that slot. Mute, fill, and macros stay per-part."
            : "Unlinked: each part keeps its own pattern slot.")
        .accessibilityIdentifier("kit-link-toggle")
        .accessibilityLabel("Pattern linking")
        .accessibilityValue(linked ? "Linked" : "Unlinked")
    }

    private var mixedBadge: some View {
        Text("MIXED")
            .studioText(.microEmphasis)
            .tracking(0.6)
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(StudioTheme.amber, in: Capsule())
            .help("Members are on different pattern slots. Re-link realigns every part.")
    }

    /// One-click re-link (AC20). Re-gangs every member to the representative
    /// slot and restores the link; no modal, no pattern fork.
    private var reLinkButton: some View {
        Button {
            session.reLinkDrumGroupPattern(groupID: navigationState.groupID)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .bold))
                Text("Re-link")
                    .studioText(.microEmphasis)
                    .tracking(0.6)
            }
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Re-link: switch every part back to a shared pattern slot.")
        .accessibilityIdentifier("kit-relink")
        .accessibilityLabel("Re-link kit patterns")
    }

    private func groupPatternSlotBinding(_ model: DrumKitMatrixModel) -> Binding<Int> {
        Binding(
            get: { model.groupSelectedSlotIndex ?? -1 },
            set: { newValue in
                guard (0..<TrackPatternBank.slotCount).contains(newValue) else { return }
                session.setDrumGroupSelectedPatternIndex(newValue, groupID: navigationState.groupID)
            }
        )
    }

    /// Matrix-wide layer selector: the same layer set the single-track step
    /// editor offers (steps, velocity, chance), applied to every part row.
    private var layerSelector: some View {
        HStack(spacing: 4) {
            ForEach(DrumKitMatrixLayer.allCases) { layer in
                layerButton(layer)
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func layerButton(_ layer: DrumKitMatrixLayer) -> some View {
        let isSelected = selectedLayer == layer

        return Button {
            selectedLayer = layer
        } label: {
            Text(layer.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step layer \(layer.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var mismatchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioTheme.background)
            Text("PATTERN MISMATCH")
                .studioText(.microEmphasis)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.background)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(StudioTheme.amber, in: Capsule())
        .help("Pattern mismatch: parts are showing different active pattern slots.")
        .accessibilityLabel("Pattern mismatch: parts are showing different active pattern slots.")
    }

    private func staleMemberBanner(count: Int) -> some View {
        Text("\(count) stale member ID\(count == 1 ? "" : "s") skipped")
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    private var emptyRowsState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No resolved parts")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
            Text("This kit has no current member tracks to display.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.loose)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func matrixRows(_ model: DrumKitMatrixModel) -> some View {
        let pageOffset = clampedPage(model) * Self.stepsPerBar
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    DrumKitMatrixRowView(
                        row: row,
                        layer: selectedLayer,
                        pageOffset: pageOffset,
                        stepsPerBar: Self.stepsPerBar,
                        accent: accent,
                        onTapStep: { stepIndex in
                            commitTap(row: row, stepIndex: stepIndex)
                        },
                        onDragStep: { stepIndex, fraction in
                            commitDrag(row: row, stepIndex: stepIndex, fraction: fraction)
                        },
                        onOpenPart: {
                            onSelectPart(row.memberID)
                        }
                    )
                }
            }
        }
        .scrollIndicators(.never)
    }

    /// Commit a cell tap for a row through `ensureClipAndMutate`, with the
    /// same shared content transform (`ClipNoteGridStepEditing`). The matrix
    /// keeps the slot-address key because a tap on an empty slot must
    /// materialize a clip; the single-track editor (which only ever edits an
    /// existing clip) commits through `StepGridCoordinator.commitEdit`.
    private func commitTap(row: DrumKitMatrixModel.Row, stepIndex: Int) {
        guard case let .editable(_, lengthSteps, steps) = row.content,
              let updated = DrumKitMatrixStepEdit.tappedContent(
                  layer: selectedLayer,
                  stepIndex: stepIndex,
                  lengthSteps: lengthSteps,
                  steps: steps,
                  defaultNote: row.defaultNote
              )
        else { return }

        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            entry.content = updated
        }
    }

    private func commitDrag(row: DrumKitMatrixModel.Row, stepIndex: Int, fraction: Double) {
        guard case let .editable(_, lengthSteps, steps) = row.content,
              let updated = DrumKitMatrixStepEdit.draggedContent(
                  layer: selectedLayer,
                  stepIndex: stepIndex,
                  fraction: fraction,
                  lengthSteps: lengthSteps,
                  steps: steps,
                  defaultNote: row.defaultNote
              )
        else { return }

        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            entry.content = updated
        }
    }

    private var unavailableState: some View {
        StudioPanel(title: "Kit Matrix", eyebrow: "Group unavailable", accent: StudioTheme.amber) {
            Text("The selected kit no longer resolves.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private func applyVisualCommand(_ command: String) {
        switch command {
        case "display-16":
            // Legacy 16/32 toggle removed; map to the first bar page so the
            // external QA command runner stays compatible.
            barPage = 0
        case "display-32":
            // Legacy: second bar (17–32) now that the grid is fixed at 16.
            barPage = 1
        case "open-routing":
            isPresentingRoutingEditor = true
        case "close-routing":
            isPresentingRoutingEditor = false
        case "open-template-chooser":
            isPresentingTemplateChooser = true
        case "close-template-chooser":
            isPresentingTemplateChooser = false
        case "open-capture":
            isCaptureOpen = true
        case "close-capture":
            isCaptureOpen = false
        case "link-on":
            session.setDrumGroupPatternLinked(true, groupID: navigationState.groupID)
        case "link-off":
            session.setDrumGroupPatternLinked(false, groupID: navigationState.groupID)
        case "relink":
            session.reLinkDrumGroupPattern(groupID: navigationState.groupID)
        case "open-kit-fx-chooser":
            isPresentingKitFX = true
        case "close-kit-fx-chooser":
            isPresentingKitFX = false
        case "tab-matrix":
            isCaptureOpen = false
            kitTab = .matrix
        case "tab-fx":
            isCaptureOpen = false
            kitTab = .fx
        case "tab-macros":
            isCaptureOpen = false
            kitTab = .macros
        case "tab-mixer":
            isCaptureOpen = false
            kitTab = .mixer
        case "back":
            onBack()
        default:
            if command.hasPrefix("select-index:"),
               let rawIndex = command.split(separator: ":").last,
               let index = Int(rawIndex),
               let model,
               model.rows.indices.contains(index) {
                onSelectPart(model.rows[index].memberID)
            } else if command.hasPrefix("layer:"),
                      let layer = DrumKitMatrixLayer(rawValue: String(command.dropFirst("layer:".count))) {
                selectedLayer = layer
            } else if command.hasPrefix("bar:"),
                      let rawPage = command.split(separator: ":").last,
                      let page = Int(rawPage),
                      page >= 0 {
                barPage = page
            } else if command.hasPrefix("pattern:"),
                      let rawSlot = command.split(separator: ":").last,
                      let slotIndex = Int(rawSlot),
                      (0..<TrackPatternBank.slotCount).contains(slotIndex) {
                session.setDrumGroupSelectedPatternIndex(slotIndex, groupID: navigationState.groupID)
            }
        }
    }
}

/// One part row: header (part name + chevron, navigates to the part
/// workspace) above the SAME full-size step grid the single-track editor
/// renders. Generator-backed and non-note-grid rows show their badge and
/// read-only cells.
private struct DrumKitMatrixRowView: View {
    let row: DrumKitMatrixModel.Row
    let layer: DrumKitMatrixLayer
    /// Absolute step index of the first visible cell (selected bar × 16).
    let pageOffset: Int
    /// Fixed grid width — always 16 columns.
    let stepsPerBar: Int
    let accent: Color
    /// Receives the ABSOLUTE step index (pageOffset + grid column).
    let onTapStep: (Int) -> Void
    let onDragStep: (Int, Double) -> Void
    let onOpenPart: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            nameColumn
            stepRegion
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(row.isDivergentPattern ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Part name + badges as a fixed-width column to the LEFT of the step grid,
    /// rather than stacked on top, so more part rows are visible at once.
    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOpenPart) {
                HStack(spacing: 5) {
                    Text(row.partName)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(row.partName)")
            .accessibilityLabel("Open \(row.partName)")

            if row.isDivergentPattern {
                Text(row.patternBadge)
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(StudioTheme.amber, in: Capsule())
                    .help("This part is on \(row.patternBadge), diverging from the group.")
            }

            readOnlyBadge
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private var readOnlyBadge: some View {
        switch row.content {
        case .editable:
            EmptyView()
        case let .generator(detail):
            limitedBadge("GEN", detail: detail)
        case let .readOnly(badge, detail, _):
            limitedBadge(badge, detail: detail)
        }
    }

    private func limitedBadge(_ badge: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(badge)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
            Text(detail)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
        }
        .help("Read-only: \(detail)")
    }

    @ViewBuilder
    private var stepRegion: some View {
        switch row.content {
        case let .editable(_, _, steps):
            // Always a 16-cell window starting at the selected bar. The grid's
            // `indexOffset` makes every closure index and cell label ABSOLUTE,
            // so tap/drag commit through the full-length step array unchanged.
            let states = windowedEditableStates(steps: steps)
            StepGridView(
                stepStates: states,
                indexOffset: pageOffset,
                contentProvider: { index, _ in
                    cellContent(steps: steps, index: index)
                },
                onValueDrag: layer == .steps ? nil : { index, fraction in
                    onDragStep(index, fraction)
                },
                advanceStep: { index in
                    onTapStep(index)
                }
            )

        case .generator:
            readOnlyGrid(states: Array(repeating: StepVisualState.off, count: stepsPerBar))

        case let .readOnly(_, _, pattern):
            readOnlyGrid(states: windowedReadOnlyStates(pattern: pattern))
        }
    }

    /// 16 visual states for the current bar window over `steps`, padding cells
    /// past the row's length with `.off`.
    private func windowedEditableStates(steps: [ClipStep]) -> [StepVisualState] {
        (0..<stepsPerBar).map { local in
            let absolute = pageOffset + local
            guard steps.indices.contains(absolute) else { return .off }
            return ClipNoteGridStepEditing.visualState(for: steps[absolute], lane: .main)
        }
    }

    /// 16 read-only states for the current bar window over a boolean pattern.
    private func windowedReadOnlyStates(pattern: [Bool]) -> [StepVisualState] {
        (0..<stepsPerBar).map { local in
            let absolute = pageOffset + local
            return pattern.indices.contains(absolute) && pattern[absolute] ? .on : .off
        }
    }

    private func readOnlyGrid(states: [StepVisualState]) -> some View {
        StepGridView(
            stepStates: states,
            indexOffset: pageOffset,
            advanceStep: { _ in }
        )
        .allowsHitTesting(false)
        .opacity(0.55)
    }

    private func cellContent(steps: [ClipStep], index: Int) -> StepCellContent {
        guard steps.indices.contains(index) else {
            return layer == .steps ? .toggle : .valueBar(fraction: 0)
        }
        switch layer {
        case .steps:
            return .toggle
        case .velocity:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.velocityValue(for: steps[index], lane: .main) / 127.0
            )
        case .chance:
            return .valueBar(
                fraction: ClipNoteGridStepEditing.chanceValue(for: steps[index], lane: .main)
            )
        }
    }
}

/// Kit-bus FX insert chain (AC23). The same grammar as the per-track FX chain
/// (drag handle reorder, bypass + ✕ on one line, "+ FX" button, compact empty
/// state — no "Enabled"/"Empty" filler), but it edits the kit bus's
/// `MixerBusInsert` chain so the inserts process the whole kit at once.
private struct KitBusFXChainView: View {
    let inserts: [MixerBusInsert]
    let accent: Color
    let onAddFX: () -> Void
    let onRemove: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onSetBypassed: (UUID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if inserts.isEmpty {
                emptyState
            } else {
                chainList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Text("No inserts yet.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer(minLength: 0)
            addFXButton
        }
    }

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(inserts) { insert in
                    insertRow(insert)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: listHeight)

            HStack {
                Spacer(minLength: 0)
                addFXButton
            }
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let visibleRows = min(inserts.count, 5)
        return CGFloat(visibleRows) * rowHeight
    }

    private func insertRow(_ insert: MixerBusInsert) -> some View {
        let icon = TrackFXChainView.iconName(for: insert.kind)
        let subtitle = insert.kind.summary
        let bypassed = !insert.isEnabled
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 18)
                .accessibilityLabel("Reorder \(insert.name)")

            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: 22, height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(insert.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle("Bypass \(insert.name)", isOn: bypassBinding(insert))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(StudioTheme.success)

            Button {
                onRemove(insert.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Remove insert")
            .accessibilityLabel("Remove \(insert.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .opacity(bypassed ? 0.55 : 1)
    }

    private var addFXButton: some View {
        Button(action: onAddFX) {
            Label("FX", systemImage: "plus")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.background)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add kit FX insert")
        .accessibilityIdentifier("kit-add-fx")
    }

    private func bypassBinding(_ insert: MixerBusInsert) -> Binding<Bool> {
        Binding(
            get: { insert.isEnabled },
            set: { isActive in onSetBypassed(insert.id, !isActive) }
        )
    }
}

/// Human-readable destination label for routing editor surfaces. Sample
/// destinations resolve to the library sample name when available instead of
/// the raw hex ID; unresolved samples fall back to a short 4-char ID.
private func drumRoutingDestinationLabel(_ destination: Destination) -> String {
    if case let .sample(sampleID, settings) = destination {
        let gainLabel = settings.gain == 0 ? "" : String(format: " • %+.1f dB", settings.gain)
        if let sample = AudioSampleLibrary.shared.sample(id: sampleID) {
            return "\(sample.name)\(gainLabel)"
        }
        return "Sample \(sampleID.uuidString.prefix(4))\(gainLabel)"
    }
    return destination.summary
}

private struct DrumGroupRoutingEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DrumGroupRoutingEditorDraft
    @State private var isPresentingDestinationPicker = false

    let audioInstrumentChoices: [AudioInstrumentChoice]
    let onApply: (Project.DrumGroupRoutingDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: DrumGroupRoutingEditorDraft,
        audioInstrumentChoices: [AudioInstrumentChoice],
        onApply: @escaping (Project.DrumGroupRoutingDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.audioInstrumentChoices = audioInstrumentChoices
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        StudioModal(
            title: "Edit Routing",
            subtitle: draft.groupName,
            minWidth: 620,
            minHeight: 520,
            onClose: {
                draft.cancel()
                onCancel()
                dismiss()
            }
        ) {
            destinationSection

            DrumGroupRoutingModeControl(selection: $draft.triggerMappingMode)

            warningsAndErrors

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($draft.rows) { $row in
                        DrumGroupRoutingEditorRow(draftMode: draft.triggerMappingMode, row: $row)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 360)

            HStack {
                Spacer()

                Button {
                    guard let projectDraft = draft.projectDraft() else { return }
                    onApply(projectDraft)
                    dismiss()
                } label: {
                    Text("Apply")
                        .studioText(.labelBold)
                }
                .buttonStyle(DrumGroupRoutingEditorButtonStyle(accent: StudioTheme.success, isProminent: true))
                .disabled(!draft.canApply)
            }
        }
        .sheet(isPresented: $isPresentingDestinationPicker) {
            AddDestinationSheet(
                trackHasGroup: false,
                audioInstrumentChoices: audioInstrumentChoices,
                sampleLibrary: .shared,
                onCommit: { destination in
                    draft.sharedDestination = destination
                }
            )
        }
        .onAppear {
            postRoutingEditorVisualState(isVisible: true)
        }
        .onDisappear {
            postRoutingEditorVisualState(isVisible: false)
        }
        .onChange(of: draft) {
            postRoutingEditorVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumGroupRoutingEditorVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    private var destinationSection: some View {
        let storedForGroupedModesOnly = draft.triggerMappingMode == .individual

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Shared Destination")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(StudioTheme.mutedText)

                    if storedForGroupedModesOnly {
                        Text("Stored for grouped modes")
                            .studioText(.eyebrow)
                            .foregroundStyle(StudioTheme.mutedText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Color.white.opacity(StudioOpacity.subtleFill),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                            )
                    }
                }

                Text(draft.sharedDestination.map(drumRoutingDestinationLabel) ?? "No shared destination")
                    .studioText(.body)
                    .foregroundStyle(storedForGroupedModesOnly ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(2)

                if storedForGroupedModesOnly {
                    Text("Individual mode uses each part's own destination.")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Spacer()

            Button {
                isPresentingDestinationPicker = true
            } label: {
                Text("Change")
                    .studioText(.labelBold)
            }
            .buttonStyle(DrumGroupRoutingEditorButtonStyle())
            .disabled(storedForGroupedModesOnly)
            .help(storedForGroupedModesOnly ? "Switch to Per Note or Per Channel to edit the stored shared destination." : "Change shared destination")

            if draft.sharedDestination != nil {
                Button {
                    draft.sharedDestination = nil
                } label: {
                    Text("Clear")
                        .studioText(.labelBold)
                }
                .buttonStyle(DrumGroupRoutingEditorButtonStyle())
                .disabled(storedForGroupedModesOnly)
                .help(storedForGroupedModesOnly ? "Switch to Per Note or Per Channel to clear the stored shared destination." : "Clear shared destination")
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(
            Color.white.opacity(storedForGroupedModesOnly ? 0.015 : StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(
                    StudioTheme.border.opacity(storedForGroupedModesOnly ? 0.65 : 1),
                    lineWidth: StudioMetrics.borderWidth
                )
        )
    }

    @ViewBuilder
    private var warningsAndErrors: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(draft.warnings, id: \.message) { warning in
                Text(warning.message)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
            }

            ForEach(draft.validationIssues.map(Self.validationMessage), id: \.self) { message in
                Text(message)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
            }
        }
    }

    private static func validationMessage(_ issue: DrumGroupRoutingEditorDraft.ValidationIssue) -> String {
        switch issue {
        case .invalidNote:
            return "One or more note names are invalid."
        case .invalidChannel:
            return "Channels must be 1-16."
        case .impossibleIndividualRouting:
            return "A part needs an own destination before individual mode can apply."
        case .perChannelRequiresMIDISharedDestination:
            return "Per-channel mode requires a MIDI shared destination."
        }
    }

    private func postRoutingEditorVisualState(isVisible: Bool) {
        NotificationCenter.default.post(
            name: .drumGroupRoutingEditorRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "mode": isVisible ? draft.triggerMappingMode.rawValue : "none",
                "canApply": isVisible && draft.canApply,
                "sharedDestinationKind": isVisible ? draft.sharedDestination?.kindLabel ?? "none" : "none",
                "warnings": isVisible ? draft.warnings.map(\.message).joined(separator: "|") : "none",
                "validationIssues": isVisible ? draft.validationIssues.map(Self.validationIssueLabel).joined(separator: "|") : "none",
                "rowInheritance": isVisible ? draft.rows.map { $0.inheritsGroupDestination ? "inherit" : "own" }.joined(separator: "|") : "none",
                "noteInputs": isVisible ? draft.rows.map(\.noteInput).joined(separator: "|") : "none",
                "channelInputs": isVisible ? draft.rows.map(\.channelInput).joined(separator: "|") : "none",
            ]
        )
    }

    private static func validationIssueLabel(_ issue: DrumGroupRoutingEditorDraft.ValidationIssue) -> String {
        switch issue {
        case .invalidNote:
            return "invalidNote"
        case .invalidChannel:
            return "invalidChannel"
        case .impossibleIndividualRouting:
            return "impossibleIndividualRouting"
        case .perChannelRequiresMIDISharedDestination:
            return "perChannelRequiresMIDISharedDestination"
        }
    }

    private func applyVisualCommand(_ command: String) {
        switch command {
        case "routing-per-note":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            draft.setTriggerMappingMode(.perNote)
        case "routing-per-channel":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            draft.setTriggerMappingMode(.perChannel)
        case "routing-individual":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.individual)
            resetVisualRowInputs()
            for memberID in draft.rows.map(\.memberID) {
                draft.setMemberInheritsGroupDestination(false, memberID: memberID)
            }
        case "routing-duplicate-channel":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.perChannel)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            for memberID in draft.rows.prefix(2).map(\.memberID) {
                draft.setChannelInput("10", memberID: memberID)
            }
        case "routing-invalid-note":
            draft.sharedDestination = .midi(
                port: MIDIEndpointName(displayName: "Visual Kit Out", isVirtual: false),
                channel: 9,
                noteOffset: 0
            )
            draft.setTriggerMappingMode(.perNote)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
            if let firstRow = draft.rows.first {
                draft.setNoteInput("C#", memberID: firstRow.memberID)
            }
        case "routing-non-midi":
            draft.sharedDestination = .sample(sampleID: UUID(), settings: .default)
            draft.setTriggerMappingMode(.perChannel)
            setVisualRowsInheritGroupDestination(true)
            resetVisualRowInputs()
        default:
            break
        }

        postRoutingEditorVisualState(isVisible: true)
    }

    private func setVisualRowsInheritGroupDestination(_ inherits: Bool) {
        for memberID in draft.rows.map(\.memberID) {
            draft.setMemberInheritsGroupDestination(inherits, memberID: memberID)
        }
    }

    private func resetVisualRowInputs() {
        let memberIDs = draft.rows.map(\.memberID)
        for (index, memberID) in memberIDs.enumerated() {
            draft.setNoteInput("C2", memberID: memberID)
            draft.setChannelInput("\(min(index + 1, 16))", memberID: memberID)
        }
    }
}

private struct DrumGroupRoutingModeControl: View {
    @Binding var selection: DrumTriggerMappingMode

    private let modes: [(title: String, mode: DrumTriggerMappingMode)] = [
        ("Per Note", .perNote),
        ("Per Channel", .perChannel),
        ("Individual", .individual),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode".uppercased())
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 4) {
                ForEach(modes.indices, id: \.self) { index in
                    modeButton(modes[index])
                }
            }
            .padding(3)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
            )
        }
    }

    private func modeButton(_ option: (title: String, mode: DrumTriggerMappingMode)) -> some View {
        let isSelected = selection == option.mode

        return Button {
            selection = option.mode
        } label: {
            Text(option.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 10)
                .background(
                    isSelected ? StudioTheme.cyan : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Routing mode \(option.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct DrumGroupRoutingEditorButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var accent: Color = StudioTheme.cyan
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                backgroundFill(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(borderColor, lineWidth: StudioMetrics.borderWidth)
            )
            .opacity(isEnabled ? 1 : 0.48)
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isProminent {
            return accent.opacity(isPressed ? StudioOpacity.accentStroke : StudioOpacity.selectedFill)
        }
        return Color.white.opacity(isPressed ? StudioOpacity.mutedFill : StudioOpacity.subtleFill)
    }

    private var borderColor: Color {
        if isProminent {
            return accent.opacity(isEnabled ? 0.72 : StudioOpacity.softStroke)
        }
        return StudioTheme.border.opacity(isEnabled ? 0.9 : 0.65)
    }
}

private struct DrumGroupRoutingEditorRow: View {
    let draftMode: DrumTriggerMappingMode
    @Binding var row: DrumGroupRoutingEditorDraft.MemberRow

    private var mappingControlsDisabled: Bool {
        row.mappingControlsDisabled(in: draftMode)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(row.inheritsGroupDestination ? "Inherits group" : (row.ownDestination.map(drumRoutingDestinationLabel) ?? "Own destination required"))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)

            if draftMode != .individual {
                Toggle(isOn: $row.inheritsGroupDestination) {
                    Text("Inherit")
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                    .toggleStyle(.switch)
                    .frame(width: 86)
            } else {
                Text("Own")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(width: 86)
            }

            if draftMode == .perNote {
                TextField("C2", text: $row.noteInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                    .disabled(mappingControlsDisabled)
            } else if draftMode == .perChannel {
                TextField("1", text: $row.channelInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .disabled(mappingControlsDisabled)
            } else {
                Text("Mappings disabled")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
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
