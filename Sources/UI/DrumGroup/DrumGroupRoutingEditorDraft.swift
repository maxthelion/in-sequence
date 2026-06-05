import Foundation

struct DrumGroupRoutingEditorDraft: Equatable {
    struct MemberRow: Identifiable, Equatable {
        var id: UUID { memberID }

        var memberID: UUID
        var name: String
        var inheritsGroupDestination: Bool
        var ownDestination: Destination?
        var noteInput: String
        var channelInput: String

        private var storedNoteOffset: Int
        private var storedMIDIChannel: UInt8

        var noteOffsetForDisabledMapping: Int { storedNoteOffset }
        var midiChannelForDisabledMapping: UInt8 { storedMIDIChannel }

        init(
            memberID: UUID,
            name: String,
            inheritsGroupDestination: Bool,
            ownDestination: Destination?,
            noteOffset: Int,
            midiChannel: UInt8
        ) {
            self.memberID = memberID
            self.name = name
            self.inheritsGroupDestination = inheritsGroupDestination
            self.ownDestination = ownDestination
            self.noteInput = DAWNoteName.string(forNoteOffset: noteOffset) ?? ""
            self.channelInput = "\(Int(midiChannel) + 1)"
            self.storedNoteOffset = noteOffset
            self.storedMIDIChannel = min(midiChannel, 15)
        }

        func mappingControlsDisabled(in mode: DrumTriggerMappingMode) -> Bool {
            mode == .individual || !inheritsGroupDestination
        }

        fileprivate func noteOffsetForApply(ignoreInvalidInput: Bool) -> Int? {
            if ignoreInvalidInput {
                return storedNoteOffset
            }
            return DAWNoteName.noteOffset(from: noteInput)
        }

        fileprivate func midiChannelForApply(ignoreInvalidInput: Bool) -> UInt8? {
            if ignoreInvalidInput {
                return storedMIDIChannel
            }
            guard let uiChannel = Int(channelInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...16).contains(uiChannel)
            else {
                return nil
            }
            return UInt8(uiChannel - 1)
        }
    }

    enum ValidationIssue: Equatable, Error {
        case invalidNote(memberID: UUID, value: String)
        case invalidChannel(memberID: UUID, value: String)
        case impossibleIndividualRouting(memberID: UUID)
        case perChannelRequiresMIDISharedDestination
    }

    struct Warning: Equatable {
        var memberIDs: [UUID]
        var message: String
    }

    private struct State: Equatable {
        var sharedDestination: Destination?
        var triggerMappingMode: DrumTriggerMappingMode
        var rows: [MemberRow]
    }

    let groupID: TrackGroupID
    let groupName: String
    private let originalState: State

    var sharedDestination: Destination?
    var triggerMappingMode: DrumTriggerMappingMode
    var rows: [MemberRow]

    init?(project: Project, groupID: TrackGroupID) {
        guard let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return nil
        }

        var seenMemberIDs: Set<UUID> = []
        let rows = group.memberIDs.compactMap { memberID -> MemberRow? in
            guard seenMemberIDs.insert(memberID).inserted,
                  let track = project.tracks.first(where: { $0.id == memberID })
            else {
                return nil
            }

            let inheritsGroupDestination = track.destination == .inheritGroup
            let ownDestination = inheritsGroupDestination ? nil : track.destination
            return MemberRow(
                memberID: memberID,
                name: track.name,
                inheritsGroupDestination: inheritsGroupDestination,
                ownDestination: ownDestination,
                noteOffset: group.noteMapping[memberID] ?? 0,
                midiChannel: min(group.channelMapping[memberID] ?? 0, 15)
            )
        }

        let state = State(
            sharedDestination: group.sharedDestination,
            triggerMappingMode: group.triggerMappingMode,
            rows: rows
        )

        self.groupID = groupID
        self.groupName = group.name
        self.originalState = state
        self.sharedDestination = state.sharedDestination
        self.triggerMappingMode = state.triggerMappingMode
        self.rows = state.rows
    }

    var hasChanges: Bool {
        State(sharedDestination: sharedDestination, triggerMappingMode: triggerMappingMode, rows: rows) != originalState
    }

    var warnings: [Warning] {
        guard triggerMappingMode == .perChannel else { return [] }

        let inheritedChannels = rows.compactMap { row -> (UInt8, UUID)? in
            guard row.inheritsGroupDestination,
                  let channel = row.midiChannelForApply(ignoreInvalidInput: false)
            else {
                return nil
            }
            return (channel, row.memberID)
        }

        let grouped = Dictionary(grouping: inheritedChannels, by: { $0.0 })
        return grouped.keys.sorted().compactMap { channel in
            let memberIDs = grouped[channel, default: []].map(\.1)
            guard memberIDs.count > 1 else { return nil }
            return Warning(
                memberIDs: memberIDs,
                message: "Multiple parts use MIDI channel \(Int(channel) + 1)."
            )
        }
    }

    var validationIssues: [ValidationIssue] {
        buildProjectDraft().issues
    }

    var canApply: Bool {
        validationIssues.isEmpty
    }

    mutating func cancel() {
        sharedDestination = originalState.sharedDestination
        triggerMappingMode = originalState.triggerMappingMode
        rows = originalState.rows
    }

    mutating func setTriggerMappingMode(_ mode: DrumTriggerMappingMode) {
        triggerMappingMode = mode
    }

    mutating func setMemberInheritsGroupDestination(
        _ inheritsGroupDestination: Bool,
        memberID: UUID,
        ownDestination: Destination? = nil
    ) {
        guard let index = rows.firstIndex(where: { $0.memberID == memberID }) else {
            return
        }

        rows[index].inheritsGroupDestination = inheritsGroupDestination
        if inheritsGroupDestination {
            return
        }

        if let ownDestination {
            rows[index].ownDestination = ownDestination
        } else if rows[index].ownDestination == nil {
            rows[index].ownDestination = safeOwnDestinationFallback()
        }
    }

    mutating func setNoteInput(_ value: String, memberID: UUID) {
        guard let index = rows.firstIndex(where: { $0.memberID == memberID }) else {
            return
        }
        rows[index].noteInput = value
    }

    mutating func setChannelInput(_ value: String, memberID: UUID) {
        guard let index = rows.firstIndex(where: { $0.memberID == memberID }) else {
            return
        }
        rows[index].channelInput = value
    }

    func projectDraft() -> Project.DrumGroupRoutingDraft? {
        let result = buildProjectDraft()
        guard result.issues.isEmpty else { return nil }
        return result.draft
    }

    mutating func apply(to project: inout Project) -> Bool {
        guard let draft = projectDraft() else { return false }
        project.applyDrumGroupRoutingDraft(draft)
        return true
    }

    private func buildProjectDraft() -> (draft: Project.DrumGroupRoutingDraft?, issues: [ValidationIssue]) {
        var issues: [ValidationIssue] = []

        if triggerMappingMode == .perChannel, sharedDestination?.kind != .midi {
            issues.append(.perChannelRequiresMIDISharedDestination)
        }

        var memberRoutes: [Project.DrumGroupRoutingDraft.MemberRoute] = []
        for row in rows {
            let mappingControlsDisabled = row.mappingControlsDisabled(in: triggerMappingMode)
            let noteOffset = row.noteOffsetForApply(ignoreInvalidInput: mappingControlsDisabled)
            let midiChannel = row.midiChannelForApply(ignoreInvalidInput: mappingControlsDisabled)

            if noteOffset == nil {
                issues.append(.invalidNote(memberID: row.memberID, value: row.noteInput))
            }
            if midiChannel == nil {
                issues.append(.invalidChannel(memberID: row.memberID, value: row.channelInput))
            }

            let appliesAsInherited = triggerMappingMode == .individual ? false : row.inheritsGroupDestination
            let ownDestination = appliesAsInherited ? row.ownDestination : safeOwnDestination(for: row)
            if !appliesAsInherited, ownDestination == nil {
                issues.append(.impossibleIndividualRouting(memberID: row.memberID))
            }

            memberRoutes.append(
                .init(
                    memberID: row.memberID,
                    inheritsGroupDestination: appliesAsInherited,
                    ownDestination: ownDestination,
                    noteOffset: noteOffset ?? row.noteOffsetForDisabledMapping,
                    midiChannel: midiChannel ?? row.midiChannelForDisabledMapping
                )
            )
        }

        guard issues.isEmpty else {
            return (nil, issues)
        }

        return (
            Project.DrumGroupRoutingDraft(
                groupID: groupID,
                sharedDestination: sharedDestination,
                triggerMappingMode: triggerMappingMode,
                members: memberRoutes
            ),
            []
        )
    }

    private func safeOwnDestination(for row: MemberRow) -> Destination? {
        if let ownDestination = row.ownDestination, ownDestination.kind != .inheritGroup {
            return ownDestination
        }
        return safeOwnDestinationFallback()
    }

    private func safeOwnDestinationFallback() -> Destination? {
        guard let sharedDestination,
              sharedDestination.kind != .inheritGroup,
              sharedDestination.kind != .none
        else {
            return nil
        }
        return sharedDestination
    }
}
