import SwiftUI

struct DrumKitMatrixModel: Equatable {
    struct Row: Identifiable, Equatable {
        enum Preview: Equatable {
            case steps([Bool], sourceLength: Int, overflow: Bool)
            case limited(badge: String, detail: String)
        }

        var id: UUID { memberID }

        var memberID: UUID
        var partName: String
        var patternSlotIndex: Int
        var sourceMode: TrackSourceMode
        var preview: Preview
        var isDivergentPattern: Bool

        var patternBadge: String {
            "P\(patternSlotIndex + 1)"
        }
    }

    var groupID: TrackGroupID
    var groupName: String
    var colorHex: String
    var originatingPartID: UUID
    var displayStepCount: Int
    var rows: [Row]
    var staleMemberCount: Int

    var memberCountLabel: String {
        "\(rows.count) part\(rows.count == 1 ? "" : "s")"
    }

    var hasPatternMismatch: Bool {
        rows.contains(where: \.isDivergentPattern)
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
                preview: Self.preview(
                    track: track,
                    patternSlot: patternSlot,
                    displayStepCount: resolvedDisplayStepCount,
                    clipPool: clipPool,
                    generatorPool: generatorPool
                ),
                isDivergentPattern: firstPatternSlot.map { patternSlotIndex != $0 } ?? false
            )
        }
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

    private static func preview(
        track: StepSequenceTrack,
        patternSlot: TrackPatternSlot,
        displayStepCount: Int,
        clipPool: [ClipPoolEntry],
        generatorPool: [GeneratorPoolEntry]
    ) -> Row.Preview {
        switch patternSlot.sourceRef.mode {
        case .generator:
            if generatorPool.contains(where: { $0.id == patternSlot.sourceRef.generatorID }) {
                return .limited(badge: "GEN", detail: "Generator source")
            }
            return .limited(badge: "GEN", detail: "Generator unavailable")
        case .clip:
            guard let clipID = patternSlot.sourceRef.clipID,
                  let clip = clipPool.first(where: { $0.id == clipID })
            else {
                return legacyStepPreview(track: track, displayStepCount: displayStepCount)
            }
            guard let steps = clip.content.normalized.noteGridSteps,
                  let sourceLength = clip.content.normalized.noteGridLengthSteps
            else {
                return .limited(badge: "RO", detail: "Read-only source")
            }
            return stepPreview(
                steps: steps.map { !$0.isEmpty },
                sourceLength: sourceLength,
                displayStepCount: displayStepCount
            )
        }
    }

    private static func legacyStepPreview(
        track: StepSequenceTrack,
        displayStepCount: Int
    ) -> Row.Preview {
        stepPreview(
            steps: track.stepPattern,
            sourceLength: max(1, track.stepPattern.count),
            displayStepCount: displayStepCount
        )
    }

    private static func stepPreview(
        steps: [Bool],
        sourceLength: Int,
        displayStepCount: Int
    ) -> Row.Preview {
        let resolvedLength = max(1, sourceLength)
        let visibleSteps = (0..<displayStepCount).map { index in
            guard index < resolvedLength else { return false }
            return steps.indices.contains(index) ? steps[index] : false
        }
        return .steps(
            visibleSteps,
            sourceLength: resolvedLength,
            overflow: resolvedLength > displayStepCount || resolvedLength > 32
        )
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
    @State private var isPresentingRoutingEditor = false

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
        .padding(20)
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
                    .padding(24)
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
        .onChange(of: isPresentingRoutingEditor) {
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
        NotificationCenter.default.post(
            name: .drumKitMatrixRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "routingEditorVisible": isVisible && isPresentingRoutingEditor,
                "displayStepCount": displayStepCount,
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

            Button {
                isPresentingRoutingEditor = true
            } label: {
                Label("Edit Routing", systemImage: "slider.horizontal.3")
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
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
        )
    }

    private var stepDisplayPicker: some View {
        HStack(spacing: 4) {
            stepDisplayButton(16)
            stepDisplayButton(32)
        }
        .padding(4)
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
        StudioPanel(title: "Kit Matrix", eyebrow: "Rows follow TrackGroup.memberIDs order.", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                if model.hasPatternMismatch {
                    mismatchBanner
                }

                if model.staleMemberCount > 0 {
                    staleMemberBanner(count: model.staleMemberCount)
                }

                if model.rows.isEmpty {
                    emptyRowsState
                } else {
                    matrixRows(model.rows)
                }
            }
        }
    }

    private var mismatchBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StudioTheme.amber)
            Text("Pattern mismatch: parts are showing different active pattern slots.")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(StudioTheme.amber.opacity(StudioOpacity.faintStroke), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
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
        .padding(18)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func matrixRows(_ rows: [DrumKitMatrixModel.Row]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            matrixHeaderRow

            ForEach(rows) { row in
                Button {
                    onSelectPart(row.memberID)
                } label: {
                    DrumKitMatrixRowView(
                        row: row,
                        displayStepCount: displayStepCount,
                        accent: accent
                    )
                }
                .buttonStyle(.plain)
                .help("Open \(row.partName)")
            }
        }
    }

    private var matrixHeaderRow: some View {
        HStack(spacing: 8) {
            Text("Part")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 180, alignment: .leading)
            Text("Pat")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 42, alignment: .center)
            Text("Steps")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer()
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
        case "back":
            onBack()
        default:
            if command.hasPrefix("select-index:"),
               let rawIndex = command.split(separator: ":").last,
               let index = Int(rawIndex),
               let model,
               model.rows.indices.contains(index) {
                onSelectPart(model.rows[index].memberID)
            }
        }
    }
}

private struct DrumKitMatrixRowView: View {
    let row: DrumKitMatrixModel.Row
    let displayStepCount: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(row.partName)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)

            Text(row.patternBadge)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(row.isDivergentPattern ? StudioTheme.amber : accent)
                .frame(width: 42, height: 26)
                .background((row.isDivergentPattern ? StudioTheme.amber : accent).opacity(StudioOpacity.faintStroke), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke((row.isDivergentPattern ? StudioTheme.amber : accent).opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                )

            stepRegion

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(row.isDivergentPattern ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var stepRegion: some View {
        switch row.preview {
        case let .steps(steps, sourceLength, overflow):
            ScrollView(.horizontal, showsIndicators: displayStepCount == 32) {
                HStack(spacing: displayStepCount == 32 ? 3 : 5) {
                    ForEach(0..<displayStepCount, id: \.self) { index in
                        DrumKitMatrixStepCell(
                            isOn: steps.indices.contains(index) ? steps[index] : false,
                            isBeatStart: index % 4 == 0,
                            accent: accent
                        )
                    }

                    if overflow {
                        Text("+")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.mutedText)
                            .frame(width: 16)
                            .help("Source length: \(sourceLength) steps")
                    }
                }
                .frame(minWidth: displayStepCount == 32 ? 390 : 250, alignment: .leading)
            }
            .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
        case let .limited(badge, detail):
            HStack(spacing: 8) {
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(StudioOpacity.borderSubtle), in: Capsule())
                Text(detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
            }
            .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DrumKitMatrixStepCell: View {
    let isOn: Bool
    let isBeatStart: Bool
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isOn ? accent.opacity(0.85) : Color.white.opacity(isBeatStart ? 0.08 : 0.035))
            .frame(width: 10, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(isBeatStart ? StudioTheme.border.opacity(0.8) : StudioTheme.border.opacity(0.45), lineWidth: 1)
            )
            .accessibilityLabel(isOn ? "Step on" : "Step off")
    }
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Edit Routing")
                        .studioText(.display)
                        .foregroundStyle(StudioTheme.text)
                    Text(draft.groupName)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Button("Cancel") {
                    draft.cancel()
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Apply") {
                    guard let projectDraft = draft.projectDraft() else { return }
                    onApply(projectDraft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
                .disabled(!draft.canApply)
            }

            destinationSection

            Picker("Mode", selection: $draft.triggerMappingMode) {
                Text("Per Note").tag(DrumTriggerMappingMode.perNote)
                Text("Per Channel").tag(DrumTriggerMappingMode.perChannel)
                Text("Individual").tag(DrumTriggerMappingMode.individual)
            }
            .pickerStyle(.segmented)

            warningsAndErrors

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($draft.rows) { $row in
                        DrumGroupRoutingEditorRow(draftMode: draft.triggerMappingMode, row: $row)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 520)
        .background(StudioTheme.stageFill)
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
    }

    private var destinationSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared Destination")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
                Text(draft.sharedDestination?.summary ?? "No shared destination")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(2)
            }

            Spacer()

            Button("Change") {
                isPresentingDestinationPicker = true
            }
            .buttonStyle(.bordered)

            if draft.sharedDestination != nil {
                Button("Clear") {
                    draft.sharedDestination = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
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

                Text(row.inheritsGroupDestination ? "Inherits group" : (row.ownDestination?.summary ?? "Own destination required"))
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .frame(width: 210, alignment: .leading)

            if draftMode != .individual {
                Toggle("Inherit", isOn: $row.inheritsGroupDestination)
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
        .padding(12)
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
