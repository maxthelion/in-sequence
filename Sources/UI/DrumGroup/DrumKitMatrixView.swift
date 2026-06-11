import SwiftUI

/// Matrix-wide step layer. The same layer set the single-track step editor
/// offers for note-grid clips (`ClipEditorMode`): on/off triggers, velocity,
/// and chance. Macro lanes are per-track bindings and stay single-track only.
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
                // materializes a clip through `ensureClipAndMutate`, exactly
                // like the single-track editor's empty-slot behavior.
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
    let onBack: () -> Void
    let onSelectPart: (UUID) -> Void

    @State private var displayStepCount = 16
    @State private var selectedLayer: DrumKitMatrixLayer = .steps
    @State private var isPresentingRoutingEditor = false
    @State private var isPresentingTemplateChooser = false

    private var model: DrumKitMatrixModel? {
        DrumKitMatrixModel(
            groupID: navigationState.groupID,
            originatingPartID: navigationState.originatingPartID,
            displayStepCount: displayStepCount,
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let model {
                matrixContent(model)
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
        .onAppear {
            postRenderedVisualState(isVisible: true)
        }
        .onDisappear {
            postRenderedVisualState(isVisible: false)
        }
        .onChange(of: displayStepCount) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: selectedLayer) {
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
                "displayStepCount": displayStepCount,
                "layer": isVisible ? selectedLayer.rawValue : "none",
                "groupPatternSlot": isVisible ? (groupSlot.map { "\($0 + 1)" } ?? "mixed") : "none",
                "groupName": isVisible ? model?.groupName ?? "none" : "none",
                "memberCount": isVisible ? model?.rows.count ?? 0 : 0,
            ]
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
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
                    .stroke(StudioTheme.border, lineWidth: 1)
            )

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

                Text("\(model?.memberCountLabel ?? "No parts") · \(displayStepCount) steps")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            stepDisplayPicker

            headerActionButton(title: "Apply Template…", systemImage: "square.grid.2x2") {
                isPresentingTemplateChooser = true
            }
            .help("Apply a pattern template into the selected group pattern slot")

            headerActionButton(title: "Edit Routing", systemImage: "slider.horizontal.3") {
                isPresentingRoutingEditor = true
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
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
        .foregroundStyle(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
    }

    private var stepDisplayPicker: some View {
        HStack(spacing: 4) {
            stepDisplayButton(16)
            stepDisplayButton(32)
        }
        .padding(StudioMetrics.Spacing.hairline)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func stepDisplayButton(_ count: Int) -> some View {
        Button {
            displayStepCount = count
        } label: {
            Text("\(count)")
                .studioText(.labelBold)
                .frame(width: 34, height: 28)
                .foregroundStyle(displayStepCount == count ? StudioTheme.text : StudioTheme.mutedText)
                .background(
                    (displayStepCount == count ? accent.opacity(StudioOpacity.selectedFill) : Color.clear),
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help("\(count)-step display")
    }

    @ViewBuilder
    private func matrixContent(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Matrix", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                if !model.rows.isEmpty {
                    groupPatternRow(model)
                }

                HStack(spacing: 10) {
                    layerSelector

                    Spacer(minLength: 0)

                    if model.hasPatternMismatch {
                        mismatchBadge
                    }
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

                if model.groupSelectedSlotIndex == nil {
                    Text("MIXED")
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                        .foregroundStyle(StudioTheme.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                        )
                        .help("Members are on different pattern slots. Selecting a slot realigns every part.")
                }
            }

            TrackPatternSlotPalette(
                selectedSlot: groupPatternSlotBinding(model),
                occupiedSlots: model.occupiedSlotIndexes,
                bypassState: .notApplicable,
                onBypassToggle: { _ in }
            )
        }
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
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: 1)
        )
    }

    private func layerButton(_ layer: DrumKitMatrixLayer) -> some View {
        let isSelected = selectedLayer == layer

        return Button {
            selectedLayer = layer
        } label: {
            Text(layer.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? accent.opacity(StudioOpacity.selectedFill) : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(isSelected ? accent.opacity(StudioOpacity.softStroke) : Color.clear, lineWidth: 1)
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
                .foregroundStyle(StudioTheme.amber)
            Text("PATTERN MISMATCH")
                .studioText(.microEmphasis)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.amber)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: Capsule())
        .overlay(
            Capsule()
                .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
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
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func matrixRows(_ model: DrumKitMatrixModel) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    DrumKitMatrixRowView(
                        row: row,
                        layer: selectedLayer,
                        displayStepCount: displayStepCount,
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

    /// Commit a cell tap for a row through the same typed session mutation the
    /// single-track editor uses (`ensureClipAndMutate`), with the same shared
    /// content transform (`ClipNoteGridStepEditing`).
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
            displayStepCount = 16
        case "display-32":
            displayStepCount = 32
        case "open-routing":
            isPresentingRoutingEditor = true
        case "close-routing":
            isPresentingRoutingEditor = false
        case "open-template-chooser":
            isPresentingTemplateChooser = true
        case "close-template-chooser":
            isPresentingTemplateChooser = false
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
    let displayStepCount: Int
    let accent: Color
    let onTapStep: (Int) -> Void
    let onDragStep: (Int, Double) -> Void
    let onOpenPart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rowHeader
            stepRegion
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(row.isDivergentPattern ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
        )
    }

    private var rowHeader: some View {
        HStack(spacing: 8) {
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
                    .foregroundStyle(StudioTheme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                    )
                    .help("This part is on \(row.patternBadge), diverging from the group.")
            }

            Spacer(minLength: 0)

            readOnlyBadge
        }
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
        case let .editable(_, lengthSteps, steps):
            let visibleCount = min(displayStepCount, lengthSteps)
            let visibleSteps = Array(steps.prefix(visibleCount))
            StepGridView(
                stepStates: visibleSteps.map {
                    ClipNoteGridStepEditing.visualState(for: $0, lane: .main)
                },
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
            readOnlyGrid(states: Array(repeating: StepVisualState.off, count: min(displayStepCount, 16)))

        case let .readOnly(_, _, pattern):
            let visibleCount = min(displayStepCount, max(1, pattern.count))
            readOnlyGrid(
                states: (0..<visibleCount).map { index in
                    pattern.indices.contains(index) && pattern[index] ? .on : .off
                }
            )
        }
    }

    private func readOnlyGrid(states: [StepVisualState]) -> some View {
        StepGridView(
            stepStates: states,
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
                                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: 1)
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
                    lineWidth: 1
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
                    .stroke(StudioTheme.border.opacity(0.9), lineWidth: 1)
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
                .foregroundStyle(isSelected ? StudioTheme.text : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 10)
                .background(
                    isSelected ? StudioTheme.cyan.opacity(StudioOpacity.selectedFill) : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(isSelected ? StudioTheme.cyan.opacity(0.72) : Color.clear, lineWidth: 1)
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
                    .stroke(borderColor, lineWidth: 1)
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
                .stroke(StudioTheme.border, lineWidth: 1)
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
