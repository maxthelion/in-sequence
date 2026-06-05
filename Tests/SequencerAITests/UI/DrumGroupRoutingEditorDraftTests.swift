import XCTest
@testable import SequencerAI

final class DrumGroupRoutingEditorDraftTests: XCTestCase {
    func test_cancel_discards_draft_changes() throws {
        let fixture = makeFixture()
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.sharedDestination = .midi(port: MIDIEndpointName(displayName: "Other", isVirtual: false), channel: 2, noteOffset: 0)
        draft.setTriggerMappingMode(.perChannel)
        draft.setNoteInput("F#2", memberID: fixture.kickID)
        XCTAssertTrue(draft.hasChanges)

        draft.cancel()

        XCTAssertFalse(draft.hasChanges)
        XCTAssertEqual(draft.sharedDestination, .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0))
        XCTAssertEqual(draft.triggerMappingMode, .perNote)
        XCTAssertEqual(draft.rows.first(where: { $0.memberID == fixture.kickID })?.noteInput, "C2")
    }

    func test_apply_commits_destination_mode_inherit_note_and_channel_atomically() throws {
        var fixture = makeFixture()
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))
        let nextSharedDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Kit Out", isVirtual: false),
            channel: 7,
            noteOffset: 4
        )
        let snareDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Snare Out", isVirtual: false),
            channel: 1,
            noteOffset: 0
        )

        draft.sharedDestination = nextSharedDestination
        draft.setTriggerMappingMode(.perChannel)
        draft.setNoteInput("D#2", memberID: fixture.kickID)
        draft.setChannelInput("4", memberID: fixture.kickID)
        draft.setMemberInheritsGroupDestination(false, memberID: fixture.snareID, ownDestination: snareDestination)

        XCTAssertTrue(draft.apply(to: &fixture.project))

        let group = try XCTUnwrap(fixture.project.trackGroups.first)
        XCTAssertEqual(group.sharedDestination, nextSharedDestination)
        XCTAssertEqual(group.triggerMappingMode, .perChannel)
        XCTAssertEqual(group.noteMapping[fixture.kickID], 3)
        XCTAssertEqual(group.channelMapping[fixture.kickID], 3)
        XCTAssertEqual(fixture.project.tracks.first(where: { $0.id == fixture.kickID })?.destination, .inheritGroup)
        XCTAssertEqual(fixture.project.tracks.first(where: { $0.id == fixture.snareID })?.destination, snareDestination)
    }

    func test_invalid_apply_does_not_partially_mutate_project() throws {
        var fixture = makeFixture()
        let originalProject = fixture.project
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.sharedDestination = .sample(sampleID: UUID(), settings: .default)
        draft.setTriggerMappingMode(.perChannel)
        draft.setNoteInput("Not a note", memberID: fixture.kickID)

        XCTAssertFalse(draft.apply(to: &fixture.project))
        XCTAssertEqual(fixture.project, originalProject)
        XCTAssertTrue(draft.validationIssues.contains(.perChannelRequiresMIDISharedDestination))
        XCTAssertTrue(draft.validationIssues.contains(.invalidNote(memberID: fixture.kickID, value: "Not a note")))
    }

    func test_mode_switching_preserves_note_and_channel_draft_values() throws {
        let fixture = makeFixture()
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setNoteInput("F2", memberID: fixture.kickID)
        draft.setChannelInput("12", memberID: fixture.kickID)
        draft.setTriggerMappingMode(.perChannel)
        draft.setTriggerMappingMode(.perNote)

        let row = try XCTUnwrap(draft.rows.first(where: { $0.memberID == fixture.kickID }))
        XCTAssertEqual(row.noteInput, "F2")
        XCTAssertEqual(row.channelInput, "12")

        let projectDraft = try XCTUnwrap(draft.projectDraft())
        XCTAssertEqual(projectDraft.members.first(where: { $0.memberID == fixture.kickID })?.noteOffset, 5)
        XCTAssertEqual(projectDraft.members.first(where: { $0.memberID == fixture.kickID })?.midiChannel, 11)
    }

    func test_own_destination_rows_disable_mapping_and_do_not_block_on_invalid_mapping_inputs() throws {
        var fixture = makeFixture(snareDestination: .midi(port: MIDIEndpointName(displayName: "Snare", isVirtual: false), channel: 2, noteOffset: 0))
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setNoteInput("bad", memberID: fixture.snareID)
        draft.setChannelInput("99", memberID: fixture.snareID)

        let row = try XCTUnwrap(draft.rows.first(where: { $0.memberID == fixture.snareID }))
        XCTAssertTrue(row.mappingControlsDisabled(in: draft.triggerMappingMode))
        XCTAssertTrue(draft.canApply)

        XCTAssertTrue(draft.apply(to: &fixture.project))
        let group = try XCTUnwrap(fixture.project.trackGroups.first)
        XCTAssertEqual(group.noteMapping[fixture.snareID], 2)
        XCTAssertEqual(group.channelMapping[fixture.snareID], 1)
    }

    func test_duplicate_channel_warnings_are_non_blocking_for_inherited_members() throws {
        var fixture = makeFixture()
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setTriggerMappingMode(.perChannel)
        draft.setChannelInput("10", memberID: fixture.kickID)
        draft.setChannelInput("10", memberID: fixture.snareID)

        XCTAssertEqual(draft.warnings, [
            .init(memberIDs: [fixture.kickID, fixture.snareID], message: "Multiple parts use MIDI channel 10.")
        ])
        XCTAssertTrue(draft.canApply)
        XCTAssertTrue(draft.apply(to: &fixture.project))
    }

    func test_invalid_note_blocks_apply_and_preserves_stored_mapping() throws {
        var fixture = makeFixture()
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setNoteInput("C#", memberID: fixture.kickID)

        XCTAssertFalse(draft.apply(to: &fixture.project))
        XCTAssertEqual(fixture.project.trackGroups[0].noteMapping[fixture.kickID], 0)
        XCTAssertTrue(draft.validationIssues.contains(.invalidNote(memberID: fixture.kickID, value: "C#")))
    }

    func test_per_channel_mode_blocks_without_midi_shared_destination() throws {
        var fixture = makeFixture(sharedDestination: .sample(sampleID: UUID(), settings: .default))
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setTriggerMappingMode(.perChannel)

        XCTAssertFalse(draft.apply(to: &fixture.project))
        XCTAssertTrue(draft.validationIssues.contains(.perChannelRequiresMIDISharedDestination))
    }

    func test_individual_mode_blocks_when_inherited_member_has_no_safe_own_destination() throws {
        var fixture = makeFixture(sharedDestination: nil)
        var draft = try XCTUnwrap(DrumGroupRoutingEditorDraft(project: fixture.project, groupID: fixture.groupID))

        draft.setTriggerMappingMode(.individual)

        XCTAssertFalse(draft.apply(to: &fixture.project))
        XCTAssertTrue(draft.validationIssues.contains(.impossibleIndividualRouting(memberID: fixture.kickID)))
    }

    private struct Fixture {
        var project: Project
        var groupID: TrackGroupID
        var kickID: UUID
        var snareID: UUID
    }

    private func makeFixture(
        sharedDestination: Destination? = .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0),
        snareDestination: Destination = .inheritGroup
    ) -> Fixture {
        let groupID = UUID()
        let kick = StepSequenceTrack(
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let snare = StepSequenceTrack(
            name: "Snare",
            trackType: .monoMelodic,
            pitches: [38],
            stepPattern: [true],
            destination: snareDestination,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let tracks = [kick, snare]
        let generatorPool = GeneratorPoolEntry.defaultPool
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: generatorPool,
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: tracks,
            trackGroups: [
                TrackGroup(
                    id: groupID,
                    name: "808 Bones",
                    memberIDs: [kick.id, snare.id],
                    sharedDestination: sharedDestination,
                    triggerMappingMode: .perNote,
                    noteMapping: [kick.id: 0, snare.id: 2],
                    channelMapping: [kick.id: 0, snare.id: 1]
                )
            ],
            generatorPool: generatorPool,
            clipPool: [],
            layers: layers,
            patternBanks: [],
            selectedTrackID: kick.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        return Fixture(project: project, groupID: groupID, kickID: kick.id, snareID: snare.id)
    }
}
