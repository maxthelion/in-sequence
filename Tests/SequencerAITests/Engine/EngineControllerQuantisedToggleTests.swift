import XCTest
@testable import SequencerAI

/// Integration tests for quantised perform toggles on the engine tick path
/// (perform/setup split slice 2): armed changes apply on the prepare of the
/// bar-boundary tick — never earlier — cancel on the second tap, group-commit
/// together, and fill cues sound for exactly the cued bar.
final class EngineControllerQuantisedToggleTests: XCTestCase {
    private let ticksPerBar = 4

    private struct Fixture {
        let controller: EngineController
        let sink: CountingAudioSink
        let project: Project
        let trackID: UUID
        let secondTrackID: UUID
        let phraseID: UUID
    }

    /// Two clip-backed tracks (main pitch 60/64, fill pitch 72/76) on a
    /// 4-tick bar so boundaries arrive quickly under manual ticking.
    private func makeFixture() -> Fixture {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink, stepsPerBar: ticksPerBar)
        let firstTrackID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let secondTrackID = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff")!
        let firstClipID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let secondClipID = UUID(uuidString: "22222222-3333-4444-5555-666666666666")!
        let alternateFirstClipID = UUID(uuidString: "33333333-4444-5555-6666-777777777777")!
        let tracks = [
            quantiseTestTrack(id: firstTrackID, name: "First"),
            quantiseTestTrack(id: secondTrackID, name: "Second"),
        ]
        let clips = [
            quantiseTestClip(id: firstClipID, mainPitch: 60, fillPitch: 72),
            quantiseTestClip(id: secondClipID, mainPitch: 64, fillPitch: 76),
            quantiseTestClip(id: alternateFirstClipID, mainPitch: 67, fillPitch: 79),
        ]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips
        )
        let patternBanks = [
            TrackPatternBank(trackID: firstTrackID, slots: [
                TrackPatternSlot(slotIndex: 0, sourceRef: .clip(firstClipID)),
                TrackPatternSlot(slotIndex: 1, sourceRef: .clip(alternateFirstClipID)),
            ]),
            TrackPatternBank(trackID: secondTrackID, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(secondClipID))]),
        ]
        let project = Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips,
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: firstTrackID,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        controller.apply(documentModel: project)
        // Test-isolation convention (bacee620): every controller a test
        // creates gets a full shutdown at teardown so no TickClock or host
        // work leaks into later suites.
        addTeardownBlock {
            controller.shutdown()
            XCTAssertFalse(controller.clock.isRunning,
                "no TickClock may survive test teardown")
        }
        return Fixture(
            controller: controller,
            sink: sink,
            project: project,
            trackID: firstTrackID,
            secondTrackID: secondTrackID,
            phraseID: phrase.id
        )
    }

    private func startForManualTicks(_ controller: EngineController) {
        controller.start()
        controller.clock.stop()
    }

    /// Pitches dispatched for one tick: resets the sink, processes the tick,
    /// returns what played.
    private func playedPitches(_ fixture: Fixture, tick: UInt64) -> [Int] {
        fixture.sink.resetPlayedEvents()
        fixture.controller.processTick(tickIndex: tick, now: TimeInterval(tick) / 10)
        return fixture.sink.playedEvents.flatMap { $0 }.map { Int($0.pitch) }.sorted()
    }

    private func muteFirstTrack(_ fixture: Fixture, muted: Bool = true) -> QuantisedToggleChange {
        .mute(trackID: fixture.trackID, muted: muted, basisPhraseID: fixture.phraseID)
    }

    private func fillFlagFirstTrack(_ fixture: Fixture, enabled: Bool = true) -> QuantisedToggleChange {
        .fillFlag(
            trackID: fixture.trackID,
            enabled: enabled,
            basisPhraseID: fixture.phraseID,
            lengthBars: nil,
            startTick: nil
        )
    }

    // MARK: - Arming

    func test_armIsRejectedWhileTransportIsStopped() {
        let fixture = makeFixture()
        XCTAssertEqual(
            fixture.controller.armQuantisedToggle(muteFirstTrack(fixture)),
            .rejected,
            "no boundary exists while stopped — callers must apply immediately instead"
        )
    }

    func test_armPublishesThePendingMirrorAndSecondTapCancels() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        XCTAssertEqual(fixture.controller.armQuantisedToggle(muteFirstTrack(fixture)), .armed)
        XCTAssertEqual(fixture.controller.quantisedPendingChanges, [muteFirstTrack(fixture)])
        XCTAssertEqual(fixture.controller.quantisedPendingMuteTarget(for: fixture.trackID), true)

        XCTAssertEqual(fixture.controller.armQuantisedToggle(muteFirstTrack(fixture)), .cancelled)
        XCTAssertTrue(fixture.controller.quantisedPendingChanges.isEmpty)
        XCTAssertNil(fixture.controller.quantisedPendingMuteTarget(for: fixture.trackID))
    }

    // MARK: - Mute applies at the bar boundary

    func test_armedMuteKeepsPlayingUntilTheBoundaryThenSilencesTheBarStartTick() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        var committedBatches: [[QuantisedToggleChange]] = []
        fixture.controller.quantisedToggleCommittedHandler = { committedBatches.append($0) }

        XCTAssertEqual(playedPitches(fixture, tick: 0), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 1), [60, 64])

        fixture.controller.armQuantisedToggle(muteFirstTrack(fixture))

        // Mid-bar ticks 2 and 3 still play the armed track.
        XCTAssertEqual(playedPitches(fixture, tick: 2), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 3), [60, 64],
                       "tick 3's processTick prepares boundary tick 4 — tick 3 itself must still sound")

        // Tick 4 is the bar start: prepared AFTER the commit, so the very
        // first step of the new bar is already muted.
        XCTAssertEqual(playedPitches(fixture, tick: 4), [64])
        XCTAssertEqual(committedBatches, [[muteFirstTrack(fixture)]])
        XCTAssertEqual(fixture.controller.quantisedMuteOverridesForTesting, [fixture.trackID: true])
        XCTAssertTrue(fixture.controller.quantisedPendingChanges.isEmpty,
                      "commit empties the pending mirror")

        // The override stays live until main confirms the staged document
        // record — then the (already equivalent) snapshot owns the value.
        XCTAssertEqual(playedPitches(fixture, tick: 5), [64])
        fixture.controller.confirmQuantisedMuteApplied(trackIDs: [fixture.trackID])
        XCTAssertTrue(fixture.controller.quantisedMuteOverridesForTesting.isEmpty)
    }

    func test_cancelledMuteNeverApplies() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        var committedBatches: [[QuantisedToggleChange]] = []
        fixture.controller.quantisedToggleCommittedHandler = { committedBatches.append($0) }

        _ = playedPitches(fixture, tick: 0)
        fixture.controller.armQuantisedToggle(muteFirstTrack(fixture))
        fixture.controller.armQuantisedToggle(muteFirstTrack(fixture)) // cancel

        for tick in UInt64(1)...5 {
            XCTAssertEqual(playedPitches(fixture, tick: tick), [60, 64])
        }
        XCTAssertTrue(committedBatches.isEmpty)
        XCTAssertTrue(fixture.controller.quantisedMuteOverridesForTesting.isEmpty)
    }

    // MARK: - Group commit

    func test_changesArmedInTheSameWindowCommitOnTheSameBoundary() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        var committedBatches: [[QuantisedToggleChange]] = []
        fixture.controller.quantisedToggleCommittedHandler = { committedBatches.append($0) }

        _ = playedPitches(fixture, tick: 0)
        fixture.controller.armQuantisedToggle(muteFirstTrack(fixture))
        _ = playedPitches(fixture, tick: 1)
        fixture.controller.armQuantisedToggle(.fillCue(trackID: fixture.secondTrackID))
        _ = playedPitches(fixture, tick: 2)

        // Tick 3 prepares boundary tick 4: ONE batch with both changes.
        _ = playedPitches(fixture, tick: 3)
        XCTAssertEqual(
            committedBatches,
            [[muteFirstTrack(fixture), .fillCue(trackID: fixture.secondTrackID)]],
            "changes armed in the same window land on the same boundary, together"
        )

        // Bar 2 (ticks 4-7): first track muted AND second track playing its
        // fill lane — one atomic group commit, audible on the bar-start tick.
        XCTAssertEqual(playedPitches(fixture, tick: 4), [76])
    }

    // MARK: - Fill cue lifecycle

    func test_fillCuePlaysTheFillLaneForExactlyTheCuedBar() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        _ = playedPitches(fixture, tick: 0)
        fixture.controller.armQuantisedToggle(.fillCue(trackID: fixture.trackID))
        XCTAssertEqual(fixture.controller.hasQuantisedPendingFillCue(for: fixture.trackID), true)

        XCTAssertEqual(playedPitches(fixture, tick: 1), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 2), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 3), [60, 64])

        // The cued bar: ticks 4-7 play the fill lane (72), then auto-return.
        // The active-cue mirror tracks the PREPARED tick (one ahead of the
        // dispatched one), so it reads active through tick 6's process and
        // empties while tick 7 — the last cued tick — is being prepared out.
        for tick in UInt64(4)...7 {
            XCTAssertEqual(playedPitches(fixture, tick: tick), [64, 72],
                           "tick \(tick) is inside the cued bar")
            if tick < 7 {
                XCTAssertEqual(fixture.controller.quantisedFillCueActiveTrackIDs, [fixture.trackID])
            }
        }
        XCTAssertEqual(playedPitches(fixture, tick: 8), [60, 64],
                       "the cue auto-returns at the next boundary (Rytm next-cycle cue)")
        XCTAssertTrue(fixture.controller.quantisedFillCueActiveTrackIDs.isEmpty)
        XCTAssertFalse(fixture.controller.hasQuantisedPendingFillCue(for: fixture.trackID))
    }

    func test_fillFlagCommitUsesFillLaneFromTheBoundaryTickUntilSnapshotConfirmation() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        var committedBatches: [[QuantisedToggleChange]] = []
        fixture.controller.quantisedToggleCommittedHandler = { committedBatches.append($0) }

        XCTAssertEqual(playedPitches(fixture, tick: 0), [60, 64])
        fixture.controller.armQuantisedToggle(fillFlagFirstTrack(fixture))

        XCTAssertEqual(playedPitches(fixture, tick: 1), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 2), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 3), [60, 64])

        XCTAssertEqual(playedPitches(fixture, tick: 4), [64, 72])
        XCTAssertEqual(committedBatches, [[.fillFlag(
            trackID: fixture.trackID,
            enabled: true,
            basisPhraseID: fixture.phraseID,
            lengthBars: nil,
            startTick: 4
        )]])
        XCTAssertEqual(fixture.controller.quantisedFillFlagOverridesForTesting, [fixture.trackID: true])

        XCTAssertEqual(playedPitches(fixture, tick: 5), [64, 72])
        fixture.controller.confirmQuantisedFillFlagApplied(trackIDs: [fixture.trackID])
        XCTAssertTrue(fixture.controller.quantisedFillFlagOverridesForTesting.isEmpty)
    }

    /// WS1 AC3(a): a fill ENGAGE armed mid-bar commits exactly at the next
    /// bar boundary, and the later DISENGAGE returns to the main lane at the
    /// following boundary — verified on the dispatch stream per tick AND by
    /// an event-recorder comparison across both boundaries: fill items sound
    /// only inside [engage boundary, disengage boundary), main items only
    /// outside it, with no step realized on both lanes.
    func test_fillEngageAndDisengageMidPlayback_realizedStreamCommitsExactlyAtBarBoundaries() {
        let fixture = makeFixture()
        let recorder = fixture.controller.enableEventRecording()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        // Bar 0 plays the main lane; the engage is armed MID-BAR (after tick 1).
        XCTAssertEqual(playedPitches(fixture, tick: 0), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 1), [60, 64])
        XCTAssertEqual(fixture.controller.armQuantisedToggle(fillFlagFirstTrack(fixture)), .armed)

        // The rest of bar 0 still plays the main lane — nothing commits early.
        XCTAssertEqual(playedPitches(fixture, tick: 2), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 3), [60, 64])

        // Bar 1 (ticks 4-7): the fill lane, from the very first boundary tick.
        XCTAssertEqual(playedPitches(fixture, tick: 4), [64, 72])
        XCTAssertEqual(playedPitches(fixture, tick: 5), [64, 72])

        // Disengage armed MID-BAR: bar 1 finishes on the fill lane.
        XCTAssertEqual(
            fixture.controller.armQuantisedToggle(fillFlagFirstTrack(fixture, enabled: false)),
            .armed
        )
        XCTAssertEqual(playedPitches(fixture, tick: 6), [64, 72])
        XCTAssertEqual(playedPitches(fixture, tick: 7), [64, 72])

        // Bar 2: back on the main lane from the boundary tick.
        XCTAssertEqual(playedPitches(fixture, tick: 8), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 9), [60, 64])

        // Event-recorder comparison across both boundaries: the realized
        // stream switches lanes exactly at steps 4 and 8, never mid-bar.
        let blockID = EngineController.generatorBlockID(for: fixture.trackID)
        let recorded = recorder.recordedEvents.filter { $0.blockID == blockID }
        XCTAssertFalse(recorded.isEmpty, "the recorder must capture the realized stream")
        let recordedSteps = Set(recorded.map(\.step))
        XCTAssertTrue(recordedSteps.isSuperset(of: Set(0...9)),
                      "the recording must cover both boundaries")
        for event in recorded {
            let expected = (4..<8).contains(event.step) ? 72 : 60
            XCTAssertEqual(
                Int(event.pitch), expected,
                "step \(event.step): the lane switch must commit exactly on the bar boundary — " +
                "fill items only from the engage boundary, main items only from the disengage boundary"
            )
        }
    }

    func test_patternCommitUsesNewSlotFromTheBoundaryTickUntilSnapshotConfirmation() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)
        defer { fixture.controller.stop() }

        var committedBatches: [[QuantisedToggleChange]] = []
        fixture.controller.quantisedToggleCommittedHandler = { committedBatches.append($0) }

        XCTAssertEqual(playedPitches(fixture, tick: 0), [60, 64])
        fixture.controller.armQuantisedToggle(.pattern(
            trackID: fixture.trackID,
            slotIndex: 1,
            basisPhraseID: fixture.phraseID,
            lengthBars: nil,
            startTick: nil
        ))

        XCTAssertEqual(playedPitches(fixture, tick: 1), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 2), [60, 64])
        XCTAssertEqual(playedPitches(fixture, tick: 3), [60, 64])

        XCTAssertEqual(playedPitches(fixture, tick: 4), [64, 67])
        XCTAssertEqual(committedBatches, [[.pattern(
            trackID: fixture.trackID,
            slotIndex: 1,
            basisPhraseID: fixture.phraseID,
            lengthBars: nil,
            startTick: 4
        )]])
        XCTAssertEqual(fixture.controller.quantisedPatternSlotOverridesForTesting, [fixture.trackID: 1])

        XCTAssertEqual(playedPitches(fixture, tick: 5), [64, 67])
        fixture.controller.confirmQuantisedPatternApplied(trackIDs: [fixture.trackID])
        XCTAssertTrue(fixture.controller.quantisedPatternSlotOverridesForTesting.isEmpty)
    }

    // MARK: - Transport stop

    func test_stopClearsArmedChangesOverridesAndCues() {
        let fixture = makeFixture()
        startForManualTicks(fixture.controller)

        _ = playedPitches(fixture, tick: 0)
        fixture.controller.armQuantisedToggle(muteFirstTrack(fixture))
        fixture.controller.armQuantisedToggle(.fillCue(trackID: fixture.secondTrackID))

        fixture.controller.stop()

        XCTAssertTrue(fixture.controller.quantisedPendingChanges.isEmpty)
        XCTAssertTrue(fixture.controller.quantisedMuteOverridesForTesting.isEmpty)
        XCTAssertTrue(fixture.controller.quantisedFillFlagOverridesForTesting.isEmpty)
        XCTAssertTrue(fixture.controller.quantisedPatternSlotOverridesForTesting.isEmpty)
        XCTAssertTrue(fixture.controller.quantisedFillCueActiveTrackIDs.isEmpty)
    }

    // MARK: - resolvedStepNotes honours the cue set directly

    func test_resolvedStepNotesTreatsCuedTrackAsFillEnabled() {
        let fixture = makeFixture()
        let snapshot = SequencerSnapshotCompiler.compile(project: fixture.project)
        var rng = SystemRandomNumberGenerator()
        var state = GeneratedSourceEvaluationState()

        let withoutCue = EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(withoutCue.map(\.pitch), [60])

        state = GeneratedSourceEvaluationState()
        let withCue = EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedFillCueTrackIDs: [fixture.trackID],
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(withCue.map(\.pitch), [72])

        state = GeneratedSourceEvaluationState()
        let withFillFlagOverrideOff = EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedFillFlagOverrides: [fixture.trackID: false],
            quantisedFillCueTrackIDs: [fixture.trackID],
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(
            withFillFlagOverrideOff.map(\.pitch),
            [60],
            "an explicit fill-flag override wins over a runtime fill cue"
        )

        state = GeneratedSourceEvaluationState()
        let otherTrackCued = EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedFillCueTrackIDs: [fixture.secondTrackID],
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(otherTrackCued.map(\.pitch), [60],
                       "the cue set is per-track — other tracks stay on the main lane")

        state = GeneratedSourceEvaluationState()
        let withPatternOverride = EngineController.resolvedStepNotes(
            for: fixture.trackID,
            in: snapshot,
            phraseID: snapshot.selectedPhraseID,
            stepIndex: 0,
            chordContext: nil,
            quantisedPatternSlotOverrides: [fixture.trackID: 1],
            state: &state,
            rng: &rng
        )
        XCTAssertEqual(withPatternOverride.map(\.pitch), [67],
                       "the pattern slot override is per-track and affects the source slot immediately")
    }
}

private func quantiseTestTrack(id: UUID, name: String) -> StepSequenceTrack {
    StepSequenceTrack(
        id: id,
        name: name,
        pitches: [48],
        stepPattern: [false],
        stepAccents: [false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 70,
        gateLength: 1
    )
}

private func quantiseTestClip(id: UUID, mainPitch: Int, fillPitch: Int) -> ClipPoolEntry {
    ClipPoolEntry(
        id: id,
        name: "Quantise Clip",
        trackType: .monoMelodic,
        content: .noteGrid(
            lengthSteps: 1,
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: mainPitch, velocity: 80, lengthSteps: 2)]),
                    fill: ClipLane(chance: 1, notes: [ClipStepNote(pitch: fillPitch, velocity: 118, lengthSteps: 5)])
                )
            ]
        )
    )
}
