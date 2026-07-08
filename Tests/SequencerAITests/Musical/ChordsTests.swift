import XCTest
@testable import SequencerAI

final class ChordsTests: XCTestCase {
    func test_chord_id_has_16_cases() {
        XCTAssertEqual(ChordID.allCases.count, 16)
    }

    func test_every_chord_id_has_a_chord() {
        for id in ChordID.allCases {
            XCTAssertNotNil(ChordDefinition.for(id: id), "Missing chord for \(id)")
        }
    }

    func test_spot_check_intervals() {
        XCTAssertEqual(ChordDefinition.for(id: .majorTriad)?.intervals, [0, 4, 7])
        XCTAssertEqual(ChordDefinition.for(id: .dominant7th)?.intervals, [0, 4, 7, 10])
    }

    func test_chord_intervals_are_valid() {
        for id in ChordID.allCases {
            guard let chord = ChordDefinition.for(id: id) else {
                XCTFail("Missing chord for \(id)")
                continue
            }

            XCTAssertEqual(chord.intervals.first, 0, "Chord \(id) should start at 0")
            XCTAssertEqual(chord.intervals, chord.intervals.sorted(), "Chord \(id) should be ascending")
            XCTAssertEqual(chord.intervals.count, Set(chord.intervals).count, "Chord \(id) should not repeat intervals")
        }
    }

    func test_chord_track_step_reference_plays_palette_slot_notes() {
        var project = Self.makeChordProject()
        let trackID = project.selectedTrackID
        let slotID = project.tracks.first(where: { $0.id == trackID })?.chordPalette.slotID(at: 1)
        Self.replaceCurrentChordClip(
            in: &project,
            stepPattern: [true],
            slotIDs: [slotID],
            inversions: [0]
        )

        let notes = Self.resolvedNotes(project: project, trackID: trackID, stepIndex: 0)
        XCTAssertEqual(notes.map(\.pitch), [65, 69, 72])
    }

    func test_changing_palette_slot_updates_every_referencing_step() {
        var project = Self.makeChordProject()
        let trackID = project.selectedTrackID
        let slotID = project.tracks.first(where: { $0.id == trackID })?.chordPalette.slotID(at: 1)
        Self.replaceCurrentChordClip(
            in: &project,
            stepPattern: [true, true],
            slotIDs: [slotID, slotID],
            inversions: [0, 0]
        )

        let before = Self.resolvedNotes(project: project, trackID: trackID, stepIndex: 1)
        XCTAssertEqual(before.map(\.pitch), [65, 69, 72])

        let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID })!
        let paletteIndex = project.tracks[trackIndex].chordPalette.slots.firstIndex(where: { $0.id == slotID })!
        project.tracks[trackIndex].chordPalette.slots[paletteIndex].root = 62

        let after = Self.resolvedNotes(project: project, trackID: trackID, stepIndex: 1)
        XCTAssertEqual(after.map(\.pitch), [62, 66, 69])
    }

    func test_step_inversion_changes_voicing_without_mutating_palette() {
        var project = Self.makeChordProject()
        let trackID = project.selectedTrackID
        let slotID = project.tracks.first(where: { $0.id == trackID })?.chordPalette.slotID(at: 0)
        Self.replaceCurrentChordClip(
            in: &project,
            stepPattern: [true],
            slotIDs: [slotID],
            inversions: [1]
        )

        let notes = Self.resolvedNotes(project: project, trackID: trackID, stepIndex: 0)
        XCTAssertEqual(notes.map(\.pitch), [64, 67, 72])

        let palette = project.tracks.first(where: { $0.id == trackID })!.chordPalette
        XCTAssertEqual(palette.voicedPitches(slotID: slotID, inversion: 0), [60, 64, 67])
    }

    func test_step_chord_type_override_changes_quality_without_mutating_palette() {
        var project = Self.makeChordProject()
        let trackID = project.selectedTrackID
        let slotID = project.tracks.first(where: { $0.id == trackID })?.chordPalette.slotID(at: 0)
        Self.replaceCurrentChordClip(
            in: &project,
            stepPattern: [true],
            slotIDs: [slotID],
            inversions: [0],
            chordIDs: [.minor7th]
        )

        let notes = Self.resolvedNotes(project: project, trackID: trackID, stepIndex: 0)
        XCTAssertEqual(notes.map(\.pitch), [60, 63, 67, 70])

        let palette = project.tracks.first(where: { $0.id == trackID })!.chordPalette
        XCTAssertEqual(palette.slot(id: slotID)?.chordID, .majorTriad)
    }


    func test_baking_chord_track_creates_note_grid_and_retains_recipe_clip() {
        var project = Self.makeChordProject()
        let trackID = project.selectedTrackID
        let sourceClipID = project.patternBank(for: trackID).slot(at: 0).sourceRef.clipID!
        let slotID = project.tracks.first(where: { $0.id == trackID })?.chordPalette.slotID(at: 2)
        Self.replaceCurrentChordClip(
            in: &project,
            stepPattern: [true],
            slotIDs: [slotID],
            inversions: [0]
        )

        let bakedClipID = project.bakeChordSourceToClip(trackID: trackID, slotIndex: 0)
        XCTAssertNotNil(bakedClipID)
        XCTAssertNotEqual(bakedClipID, sourceClipID)

        let slot = project.patternBank(for: trackID).slot(at: 0)
        XCTAssertEqual(slot.sourceRef.clipID, bakedClipID)
        XCTAssertEqual(slot.sourceRef.sourceClipID, sourceClipID)

        guard let bakedClip = project.clipEntry(id: bakedClipID),
              case let .noteGrid(_, steps) = bakedClip.content.normalized
        else {
            return XCTFail("Expected baked chord clip to be a playable note grid")
        }
        XCTAssertEqual(steps.first?.main?.notes.map(\.pitch), [67, 71, 74])

        guard let sourceClip = project.clipEntry(id: sourceClipID),
              case .chordReferences = sourceClip.content.normalized
        else {
            return XCTFail("Expected source recipe clip to remain recoverable")
        }
    }

    private static func makeChordProject() -> Project {
        var project = Project(version: 1, tracks: [StepSequenceTrack.default], selectedTrackID: StepSequenceTrack.default.id)
        project.appendTrack(trackType: .chord)
        return project
    }

    private static func replaceCurrentChordClip(
        in project: inout Project,
        stepPattern: [Bool],
        slotIDs: [UUID?],
        inversions: [Int],
        chordIDs: [ChordID?]? = nil
    ) {
        let trackID = project.selectedTrackID
        let clipID = project.patternBank(for: trackID).slot(at: 0).sourceRef.clipID!
        project.updateClipEntry(id: clipID) { clip in
            clip.content = .chordReferences(
                stepPattern: stepPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs ?? Array(repeating: nil, count: max(1, stepPattern.count)),
                velocities: Array(repeating: 96, count: max(1, stepPattern.count)),
                lengthSteps: Array(repeating: 4, count: max(1, stepPattern.count))
            )
        }
    }

    private static func resolvedNotes(project: Project, trackID: UUID, stepIndex: Int) -> [GeneratedNote] {
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        var state = GeneratedSourceEvaluationState()
        var rng = SystemRandomNumberGenerator()
        return EngineController.resolvedStepNotes(
            for: trackID,
            in: snapshot,
            phraseID: project.selectedPhraseID,
            stepIndex: stepIndex,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
    }
}
