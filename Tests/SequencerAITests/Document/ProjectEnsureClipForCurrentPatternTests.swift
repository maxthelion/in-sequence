import XCTest
@testable import SequencerAI

final class ProjectEnsureClipForCurrentPatternTests: XCTestCase {
    func test_ensureClipForCurrentPattern_allocates_for_empty_selected_slot() {
        var project = makeProject()
        let trackID = try! XCTUnwrap(project.tracks.first?.id)

        project.setSelectedPatternIndex(1, for: trackID)
        let baselineClipCount = project.clipPool.count

        let clipID = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertNotNil(clipID)
        XCTAssertEqual(project.clipPool.count, baselineClipCount + 1)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 1).sourceRef.clipID, clipID)
    }

    func test_ensureClipForCurrentPattern_is_idempotent_for_same_slot() {
        var project = makeProject()
        let trackID = try! XCTUnwrap(project.tracks.first?.id)

        project.setSelectedPatternIndex(2, for: trackID)
        let firstID = project.ensureClipForCurrentPattern(trackID: trackID)
        let clipCountAfterFirst = project.clipPool.count
        let secondID = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertEqual(firstID, secondID)
        XCTAssertEqual(project.clipPool.count, clipCountAfterFirst)
    }

    func test_ensureClipForCurrentPattern_allocates_distinct_clips_for_different_slots() {
        var project = makeProject()
        let trackID = try! XCTUnwrap(project.tracks.first?.id)
        let baselineClipCount = project.clipPool.count

        project.setSelectedPatternIndex(1, for: trackID)
        let first = project.ensureClipForCurrentPattern(trackID: trackID)
        project.setSelectedPatternIndex(2, for: trackID)
        let second = project.ensureClipForCurrentPattern(trackID: trackID)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(project.clipPool.count, baselineClipCount + 2)
    }

    func test_ensureClipForCurrentPattern_returns_nil_when_pattern_bank_missing() {
        var project = makeProject()
        let trackID = try! XCTUnwrap(project.tracks.first?.id)
        project.patternBanks = []
        let baselineClipCount = project.clipPool.count

        XCTAssertNil(project.ensureClipForCurrentPattern(trackID: trackID))
        XCTAssertEqual(project.clipPool.count, baselineClipCount)
    }

    func test_ensureClipForCurrentPattern_seeds_empty_step_sequence_using_track_pitches() {
        var project = makeProject()
        let track = try! XCTUnwrap(project.tracks.first)

        project.setSelectedPatternIndex(3, for: track.id)
        let clipID = try! XCTUnwrap(project.ensureClipForCurrentPattern(trackID: track.id))
        let clip = try! XCTUnwrap(project.clipEntry(id: clipID))

        XCTAssertEqual(clip.trackType, track.trackType)
        XCTAssertEqual(noteGridMainStepPattern(clip.content), Array(repeating: false, count: 16))
        XCTAssertTrue(noteGridPitches(clip.content).isEmpty)
    }

    private func makeProject() -> Project {
        let track = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60, 64, 67],
            stepPattern: [true],
            destination: .none,
            velocity: 100,
            gateLength: 4
        )
        let ownedClip = ClipPoolEntry(
            id: UUID(),
            name: "Lead pattern 1",
            trackType: track.trackType,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: track.pitches)
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [ownedClip]
        )

        return Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [ownedClip],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: ownedClip.id)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}
