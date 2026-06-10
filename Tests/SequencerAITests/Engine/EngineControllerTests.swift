import AVFoundation
import SwiftUI
import XCTest
@testable import SequencerAI

final class EngineControllerTests: XCTestCase {
    func test_init_registers_core_blocks_and_builds_default_pipeline() {
        let controller = EngineController(client: nil, endpoint: nil)

        XCTAssertEqual(Set(controller.registeredKindIDs), ["note-generator", "midi-out", "chord-context-sink"])
        XCTAssertNotNil(controller.executor)
    }

    func test_start_and_stop_toggle_running_state() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.start()
        XCTAssertTrue(controller.isRunning)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }

    func test_noteRepeatCommandsActivateClipBackedRuntimeStateAndReleaseIdempotently() {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true, false])

        controller.apply(documentModel: project)
        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        controller.engageNoteRepeat(trackID: trackID)
        let activeSnapshot = controller.noteRepeatRuntimeSnapshot(for: trackID)
        XCTAssertEqual(activeSnapshot?.trackID, trackID)
        XCTAssertEqual(activeSnapshot?.engagedAtTickIndex, 0)

        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(controller.noteRepeatRuntimeSnapshot(for: trackID), activeSnapshot)

        controller.stop()
        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        controller.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        controller.releaseNoteRepeat(trackID: trackID)
        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        controller.releaseNoteRepeat(trackID: trackID)
        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
    }

    func test_noteRepeatCommandsNoOpForMissingAndGeneratorBackedTracks() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        var (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true])
        let generator = try XCTUnwrap(
            GeneratorPoolEntry.defaultPool.first { $0.trackType == project.tracks[0].trackType }
        )
        project.patternBanks = [
            TrackPatternBank(
                trackID: trackID,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
            )
        ]

        controller.apply(documentModel: project)

        controller.engageNoteRepeat(trackID: trackID)
        controller.engageNoteRepeat(trackID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertTrue(controller.activeNoteRepeatTrackIDsForTesting.isEmpty)
    }

    func test_noteRepeatRuntimeStateIsIndependentPerTrack() {
        let controller = EngineController(client: nil, endpoint: nil, audioOutputFactory: { CountingAudioSink() })
        let project = Self.twoClipTrackProject()
        let firstTrackID = project.tracks[0].id
        let secondTrackID = project.tracks[1].id

        controller.apply(documentModel: project)

        controller.engageNoteRepeat(trackID: firstTrackID)
        controller.engageNoteRepeat(trackID: secondTrackID)

        XCTAssertEqual(controller.activeNoteRepeatTrackIDsForTesting, [firstTrackID, secondTrackID])

        controller.releaseNoteRepeat(trackID: firstTrackID)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: firstTrackID))
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: secondTrackID))
        XCTAssertEqual(controller.activeNoteRepeatTrackIDsForTesting, [secondTrackID])
    }

    func test_noteRepeatEngageSnapshotsStoredIntervalUntilNextEngagement() {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        var (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true])
        project.tracks[0].noteRepeatInterval = .oneThirtySecond
        controller.apply(documentModel: project)

        controller.engageNoteRepeat(trackID: trackID)
        XCTAssertEqual(controller.noteRepeatRuntimeSnapshot(for: trackID)?.interval, .oneThirtySecond)

        project.tracks[0].noteRepeatInterval = .oneSixtyFourth
        controller.apply(documentModel: project)

        XCTAssertEqual(controller.noteRepeatRuntimeSnapshot(for: trackID)?.interval, .oneThirtySecond)

        controller.releaseNoteRepeat(trackID: trackID)
        controller.engageNoteRepeat(trackID: trackID)

        XCTAssertEqual(controller.noteRepeatRuntimeSnapshot(for: trackID)?.interval, .oneSixtyFourth)
    }

    func test_noteRepeatReconciliationClearsUnsupportedTrackAndKeepsUnrelatedActiveTrack() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutputFactory: { CountingAudioSink() })
        var project = Self.twoClipTrackProject()
        let firstTrackID = project.tracks[0].id
        let secondTrackID = project.tracks[1].id

        controller.apply(documentModel: project)
        controller.engageNoteRepeat(trackID: firstTrackID)
        controller.engageNoteRepeat(trackID: secondTrackID)
        XCTAssertEqual(controller.activeNoteRepeatTrackIDsForTesting, [firstTrackID, secondTrackID])

        let firstGenerator = try XCTUnwrap(
            GeneratorPoolEntry.defaultPool.first { $0.trackType == project.tracks[0].trackType }
        )
        project.patternBanks[0] = TrackPatternBank(
            trackID: firstTrackID,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(firstGenerator.id))]
        )

        controller.apply(documentModel: project)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: firstTrackID))
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: secondTrackID))
        XCTAssertEqual(controller.activeNoteRepeatTrackIDsForTesting, [secondTrackID])
    }

    func test_noteRepeatEngageCapturesCurrentPreparedClipStepMaterial() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                ),
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 74, velocity: 113, lengthSteps: 6)]),
                    fill: nil
                )
            ]
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)

        let captured = try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        XCTAssertEqual(captured.stepIndex, 0)
        XCTAssertEqual(captured.notes, [
            NoteEvent(pitch: 62, velocity: 91, length: 3, gate: true, voiceTag: nil)
        ])
    }

    func test_noteRepeatCaptureUsesFillLaneWhenResolvedStepHasFillEnabled() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 80, lengthSteps: 2)]),
                    fill: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 118, lengthSteps: 5)])
                )
            ],
            fillEnabled: true
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)

        let captured = try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        XCTAssertEqual(captured.notes, [
            NoteEvent(pitch: 72, velocity: 118, length: 5, gate: true, voiceTag: nil)
        ])
    }

    func test_noteRepeatCapturePreservesPreparedProbabilityResultWithoutRerolling() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 0, notes: [ClipStepNote(pitch: 67, velocity: 111, lengthSteps: 4)]),
                    fill: nil
                )
            ]
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)

        let captured = try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        XCTAssertEqual(captured.stepIndex, 0)
        XCTAssertTrue(captured.notes.isEmpty)
    }

    func test_noteRepeatEngageCapturesEmptyCurrentStepAsSilence() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                .empty,
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 76, velocity: 100, lengthSteps: 4)]),
                    fill: nil
                )
            ]
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)

        let captured = try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        XCTAssertEqual(captured.stepIndex, 0)
        XCTAssertTrue(captured.notes.isEmpty)
    }

    func test_noteRepeatUnsupportedGeneratorTrackDoesNotCapturePreparedMaterial() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        var (project, trackID, _) = makeLiveStoreProject(clipPitch: 60, stepPattern: [true])
        let generator = try XCTUnwrap(
            GeneratorPoolEntry.defaultPool.first { $0.trackType == project.tracks[0].trackType }
        )
        project.patternBanks = [
            TrackPatternBank(
                trackID: trackID,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
            )
        ]

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertTrue(controller.activeNoteRepeatTrackIDsForTesting.isEmpty)
    }

    func test_noteRepeatEngageReleaseDoesNotMutatePersistedProjectState() throws {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        let originalProject = project
        let encodedBefore = try Self.persistedProjectData(project)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.releaseNoteRepeat(trackID: trackID)

        XCTAssertEqual(project, originalProject)
        XCTAssertEqual(try Self.persistedProjectData(project), encodedBefore)
        let encoded = String(decoding: encodedBefore, as: UTF8.self)
        XCTAssertFalse(encoded.contains("activeNoteRepeat"))
        XCTAssertFalse(encoded.contains("capturedStep"))
    }

    func test_noteRepeatCaptureCachesClearOnStopApplyAndTrackFillPreviewChanges() throws {
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )

        let stoppedController = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        stoppedController.apply(documentModel: project)
        stoppedController.processTick(tickIndex: 0, now: 0)
        stoppedController.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(stoppedController.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        stoppedController.releaseNoteRepeat(trackID: trackID)

        stoppedController.stop()
        stoppedController.engageNoteRepeat(trackID: trackID)
        XCTAssertNil(try XCTUnwrap(stoppedController.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)

        let runningStopController = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        runningStopController.apply(documentModel: project)
        runningStopController.start()
        XCTAssertTrue(runningStopController.isRunning)
        runningStopController.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(runningStopController.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)

        runningStopController.stop()
        XCTAssertFalse(runningStopController.isRunning)
        runningStopController.engageNoteRepeat(trackID: trackID)
        XCTAssertNil(try XCTUnwrap(runningStopController.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)

        let applyController = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        applyController.apply(documentModel: project)
        applyController.processTick(tickIndex: 0, now: 0)
        applyController.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(applyController.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        applyController.releaseNoteRepeat(trackID: trackID)

        applyController.apply(documentModel: project)
        applyController.engageNoteRepeat(trackID: trackID)
        XCTAssertNil(try XCTUnwrap(applyController.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)

        applyController.releaseNoteRepeat(trackID: trackID)
        applyController.processTick(tickIndex: 0, now: 0)
        applyController.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(applyController.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        applyController.releaseNoteRepeat(trackID: trackID)

        applyController.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))
        applyController.engageNoteRepeat(trackID: trackID)
        XCTAssertNil(try XCTUnwrap(applyController.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)

        let fillPreviewController = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        fillPreviewController.apply(documentModel: project)
        fillPreviewController.processTick(tickIndex: 0, now: 0)
        fillPreviewController.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(fillPreviewController.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        fillPreviewController.releaseNoteRepeat(trackID: trackID)

        fillPreviewController.apply(trackFillPreview: TrackFillPreviewPlaybackSnapshot(activeTrackID: trackID))
        fillPreviewController.engageNoteRepeat(trackID: trackID)
        XCTAssertNil(try XCTUnwrap(fillPreviewController.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)
    }

    func test_noteRepeatCaptureCacheClearsOnPhraseSwitchBeforeReengage() throws {
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        var nextPhrase = try XCTUnwrap(project.phrases.first)
        nextPhrase.id = UUID(uuidString: "71717171-7171-7171-7171-717171717171")!
        nextPhrase.name = "Phrase B"
        project.phrases.append(nextPhrase)

        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        controller.releaseNoteRepeat(trackID: trackID)

        XCTAssertTrue(controller.switchPhraseNow(nextPhrase.id))
        controller.engageNoteRepeat(trackID: trackID)

        XCTAssertNil(try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)
    }

    func test_noteRepeatCaptureCacheClearsOnAuditionOverrideBeforeReengage() throws {
        let (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        let auditionOverride = PseudoClipState(
            sourceTrackID: trackID,
            startStep: 0,
            lengthSteps: 1,
            noteGrid: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 74, velocity: 110, lengthSteps: 2)]),
                        fill: nil
                    )
                ]
            )
        )

        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID)?.capturedStep)
        controller.releaseNoteRepeat(trackID: trackID)

        controller.setAuditionOverride(auditionOverride, for: trackID)
        controller.engageNoteRepeat(trackID: trackID)

        XCTAssertNil(try XCTUnwrap(controller.noteRepeatRuntimeSnapshot(for: trackID)).capturedStep)
    }

    func test_noteRepeatSchedulerMapsIntervalsToV1TriggerCounts() {
        let cases: [(NoteRepeatInterval, Int)] = [
            (.oneSixteenth, 1),
            (.oneThirtySecond, 2),
            (.oneSixtyFourth, 4),
        ]

        for (interval, expectedCount) in cases {
            let sink = CountingAudioSink()
            let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
            var (project, trackID) = Self.noteRepeatClipProject(
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                        fill: nil
                    )
                ]
            )
            project.tracks[0].noteRepeatInterval = interval

            controller.apply(documentModel: project)
            controller.processTick(tickIndex: 0, now: 0)
            sink.resetPlayedEvents()
            controller.engageNoteRepeat(trackID: trackID)
            controller.processTick(tickIndex: 1, now: 1)

            XCTAssertEqual(sink.playedEvents.count, expectedCount, "interval \(interval.rawValue)")
            XCTAssertEqual(
                sink.playedEvents.flatMap { $0 }.map(\.pitch),
                Array(repeating: UInt8(62), count: expectedCount)
            )

            let scheduledAtCurrentStep = controller.noteRepeatScheduledOutputsForTesting(for: trackID)
                .filter { $0.stepIndex == 1 }
            XCTAssertEqual(scheduledAtCurrentStep.count, expectedCount)
            XCTAssertEqual(scheduledAtCurrentStep.map(\.scheduledHostTime), (0..<expectedCount).map {
                1 + (Double($0) * 0.125 / Double(expectedCount))
            })
        }
    }

    func test_noteRepeatOnlyPlaybackPublishesTransportNoteActivity() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneSixtyFourth

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        sink.resetPlayedEvents()
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)

        XCTAssertEqual(sink.playedEvents.count, 4)
        XCTAssertEqual(controller.lastNoteTriggerCount, 4)
        XCTAssertEqual(controller.lastNoteTriggerUptime, 1.09375, accuracy: 0.000001)
    }

    func test_noteRepeatRetriggersDoNotAdvanceMainStepCounterAndUnrelatedTrackKeepsTiming() {
        var createdSinks: [CountingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CountingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let project = Self.noteRepeatTimingProject(firstInterval: .oneSixtyFourth)
        let repeatTrackID = project.tracks[0].id

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        createdSinks.forEach { $0.resetPlayedEvents() }

        controller.engageNoteRepeat(trackID: repeatTrackID)
        controller.processTick(tickIndex: 1, now: 1)

        XCTAssertEqual(controller.transportTickIndex, 1)
        XCTAssertEqual(createdSinks[0].playedEvents.flatMap { $0 }.map(\.pitch), [60, 60, 60, 60])
        XCTAssertEqual(createdSinks[1].playedEvents.flatMap { $0 }.map(\.pitch), [72])
    }

    func test_noteRepeatReleaseInsidePreparedStepCancelsPendingRepeatAndResumesNormalOutput() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneSixtyFourth

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: trackID).count, 4)

        controller.releaseNoteRepeat(trackID: trackID)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertEqual(controller.pendingRepeatOwnedEventCountForTesting(trackID: trackID), 0)

        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 2, now: 2)
        XCTAssertEqual(sink.playedEvents.flatMap { $0 }.map(\.pitch), [62])
    }

    func test_noteRepeatReleaseAtStepBoundaryDoesNotDoubleOrDropUnrelatedOutput() {
        var createdSinks: [CountingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CountingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let project = Self.noteRepeatTimingProject(firstInterval: .oneThirtySecond)
        let repeatTrackID = project.tracks[0].id

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: repeatTrackID)
        controller.processTick(tickIndex: 1, now: 1)

        controller.releaseNoteRepeat(trackID: repeatTrackID)
        createdSinks.forEach { $0.resetPlayedEvents() }
        controller.processTick(tickIndex: 2, now: 2)

        XCTAssertEqual(createdSinks[0].playedEvents.flatMap { $0 }.map(\.pitch), [60])
        XCTAssertEqual(createdSinks[1].playedEvents.flatMap { $0 }.map(\.pitch), [72])
    }

    func test_noteRepeatRapidReleaseReengageDoesNotReplayStaleScheduledOutput() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneThirtySecond

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: trackID).map(\.stepIndex), [1, 1])

        controller.releaseNoteRepeat(trackID: trackID)
        controller.engageNoteRepeat(trackID: trackID)
        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 2, now: 2)

        XCTAssertEqual(sink.playedEvents.flatMap { $0 }.map(\.pitch), [62, 62])
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: trackID).map(\.stepIndex), [2, 2])
    }

    func test_noteRepeatTransportStopClearsActiveStateAndPendingRepeatOutput() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneSixtyFourth

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: trackID).count, 4)

        controller.stop()

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertEqual(controller.pendingRepeatOwnedEventCountForTesting(trackID: trackID), 0)
    }

    func test_noteRepeatShutdownClearsProjectCloseRuntimeState() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneSixtyFourth

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        controller.shutdown()

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertEqual(controller.pendingRepeatOwnedEventCountForTesting(trackID: trackID), 0)
    }

    func test_noteRepeatPlaybackPipelineRebuildClearsRuntimeStateEvenWhenClipSourceStillSupportsRepeat() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, trackID) = Self.noteRepeatClipProject(
            steps: [
                ClipStep(
                    main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 62, velocity: 91, lengthSteps: 3)]),
                    fill: nil
                )
            ]
        )
        project.tracks[0].noteRepeatInterval = .oneSixtyFourth

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: trackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: trackID))

        project.tracks[0].destination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        controller.apply(documentModel: project)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: trackID))
        XCTAssertEqual(controller.pendingRepeatOwnedEventCountForTesting(trackID: trackID), 0)
    }

    func test_noteRepeatSourceChangeCleansOnlyAffectedTrackRepeatOutput() throws {
        var createdSinks: [CountingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CountingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        var project = Self.noteRepeatTimingProject(firstInterval: .oneSixtyFourth, secondInterval: .oneThirtySecond)
        let firstTrackID = project.tracks[0].id
        let secondTrackID = project.tracks[1].id

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        controller.engageNoteRepeat(trackID: firstTrackID)
        controller.engageNoteRepeat(trackID: secondTrackID)
        controller.processTick(tickIndex: 1, now: 1)
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: firstTrackID).count, 4)
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: secondTrackID).count, 2)

        let firstGenerator = try XCTUnwrap(
            GeneratorPoolEntry.defaultPool.first { $0.trackType == project.tracks[0].trackType }
        )
        project.patternBanks[0] = TrackPatternBank(
            trackID: firstTrackID,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(firstGenerator.id))]
        )

        controller.apply(documentModel: project)

        XCTAssertNil(controller.noteRepeatRuntimeSnapshot(for: firstTrackID))
        XCTAssertNotNil(controller.noteRepeatRuntimeSnapshot(for: secondTrackID))
        XCTAssertEqual(controller.pendingRepeatOwnedEventCountForTesting(trackID: firstTrackID), 0)
        XCTAssertEqual(controller.noteRepeatScheduledOutputsForTesting(for: secondTrackID).count, 2)
    }

    func test_setBPM_reaches_executor_within_two_ticks() {
        let controller = EngineController(client: nil, endpoint: nil)

        controller.setBPM(240)
        controller.start()
        controller.setBPM(120)

        let deadline = Date().addingTimeInterval(0.4)
        while controller.executor?.currentBPM != 120 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        controller.stop()
        XCTAssertEqual(controller.executor?.currentBPM, 120)
    }

    private static func twoClipTrackProject() -> Project {
        let first = StepSequenceTrack(
            id: UUID(uuidString: "10101010-1010-1010-1010-101010101010")!,
            name: "First",
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let second = StepSequenceTrack(
            id: UUID(uuidString: "20202020-2020-2020-2020-202020202020")!,
            name: "Second",
            pitches: [64],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        let firstClip = ClipPoolEntry(
            id: UUID(uuidString: "30303030-3030-3030-3030-303030303030")!,
            name: "First Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )
                ]
            )
        )
        let secondClip = ClipPoolEntry(
            id: UUID(uuidString: "40404040-4040-4040-4040-404040404040")!,
            name: "Second Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 64, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )
                ]
            )
        )
        let tracks = [first, second]
        let clips = [firstClip, secondClip]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: clips)
        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips,
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank(
                    trackID: first.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(firstClip.id))]
                ),
                TrackPatternBank(
                    trackID: second.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(secondClip.id))]
                ),
            ],
            selectedTrackID: first.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }

    private static func noteRepeatTimingProject(
        firstInterval: NoteRepeatInterval,
        secondInterval: NoteRepeatInterval = .oneSixteenth
    ) -> Project {
        var first = StepSequenceTrack(
            id: UUID(uuidString: "11111111-5151-5151-5151-515151515151")!,
            name: "Repeat First",
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        first.noteRepeatInterval = firstInterval
        var second = StepSequenceTrack(
            id: UUID(uuidString: "22222222-5151-5151-5151-515151515151")!,
            name: "Normal Second",
            pitches: [72],
            stepPattern: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 4
        )
        second.noteRepeatInterval = secondInterval

        let firstClip = ClipPoolEntry(
            id: UUID(uuidString: "33333333-5151-5151-5151-515151515151")!,
            name: "First Repeat Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )
                ]
            )
        )
        let secondClip = ClipPoolEntry(
            id: UUID(uuidString: "44444444-5151-5151-5151-515151515151")!,
            name: "Second Normal Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]),
                        fill: nil
                    )
                ]
            )
        )
        let tracks = [first, second]
        let clips = [firstClip, secondClip]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips
        )
        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips,
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank(
                    trackID: first.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(firstClip.id))]
                ),
                TrackPatternBank(
                    trackID: second.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(secondClip.id))]
                ),
            ],
            selectedTrackID: first.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }

    private static func noteRepeatClipProject(
        steps: [ClipStep],
        fillEnabled: Bool = false
    ) -> (Project, UUID) {
        let trackID = UUID(uuidString: "51515151-5151-5151-5151-515151515151")!
        let clipID = UUID(uuidString: "61616161-6161-6161-6161-616161616161")!
        let track = StepSequenceTrack(
            id: trackID,
            name: "Repeat Clip",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let clip = ClipPoolEntry(
            id: clipID,
            name: "Repeat Source",
            trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: max(1, steps.count), steps: steps)
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        var phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip]
        )
        if fillEnabled,
           let fillLayer = layers.first(where: { $0.target == .macroRow("fill-flag") })
        {
            phrase.setCell(.single(.bool(true)), for: fillLayer.id, trackID: track.id)
        }
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        return (
            Project(
                version: 1,
                tracks: [track],
                generatorPool: GeneratorPoolEntry.defaultPool,
                clipPool: [clip],
                layers: layers,
                routes: [],
                patternBanks: [patternBank],
                selectedTrackID: track.id,
                phrases: [phrase],
                selectedPhraseID: phrase.id
            ),
            trackID
        )
    }

    private static func persistedProjectData(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    func test_apply_document_model_updates_note_generator_params() {
        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let bass = StepSequenceTrack(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            name: "Bass",
            pitches: [36],
            stepPattern: [true, false],
            stepAccents: [false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 90,
            gateLength: 4
        )
        let lead = StepSequenceTrack(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            name: "Lead",
            pitches: [72],
            stepPattern: [false, true],
            stepAccents: [false, true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.72, pan: -0.15, isMuted: false),
            velocity: 111,
            gateLength: 2
        )
        let bassGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!,
            name: "Bass Program",
            trackType: bass.trackType,
            pattern: [true, false],
            pitch: 36,
            velocity: 90,
            gateLength: 4
        )
        let leadGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "bbbbbbbb-2222-2222-2222-222222222222")!,
            name: "Lead Program",
            trackType: lead.trackType,
            pattern: [false, true],
            pitch: 72,
            velocity: 127,
            gateLength: 2
        )
        let generators = [bassGenerator, leadGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [bass, lead])
        let phrase = PhraseModel.default(tracks: [bass, lead], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: bass.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(bassGenerator.id))]
            ),
            TrackPatternBank(
                trackID: lead.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(leadGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [bass, lead],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: lead.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch), [36])
        XCTAssertEqual(createdSinks[0].receivedEvents.flatMap { $0 }.map(\.velocity), [90])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.pitch), [72])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.velocity), [127])
        XCTAssertEqual(createdSinks[1].receivedEvents.flatMap { $0 }.map(\.length), [2])
    }

    func test_apply_document_model_uses_selected_generator_pool_source_over_legacy_track_fields() throws {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212") ?? UUID(),
            name: "Generator Driven",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            velocity: 80,
            gateLength: 2
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            name: "Upbeat",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 4, offset: 0)),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 99, gateLength: 3, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.pitch, 72)
        XCTAssertEqual(events.first?.velocity, 99)
        XCTAssertEqual(events.first?.length, 3)
    }

    func test_apply_document_model_uses_selected_clip_source_over_legacy_track_fields() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656") ?? UUID(),
            name: "Clip Driven",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 80,
            gateLength: 2
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "78787878-7878-7878-7878-787878787878")!,
            name: "Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false, false, false], pitches: [65])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.pitch, 65)
        XCTAssertEqual(events.first?.velocity, 100)
        XCTAssertEqual(events.first?.length, 4)
    }

    func test_clip_source_runs_post_source_pitch_processing_without_overwriting_clip_velocity_or_length() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "11111111-aaaa-bbbb-cccc-111111111111") ?? UUID(),
            name: "Processed Clip",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "22222222-aaaa-bbbb-cccc-222222222222")!,
            name: "Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 91, lengthSteps: 3)]),
                        fill: nil
                    )
                ]
            )
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "33333333-aaaa-bbbb-cccc-333333333333")!,
            name: "Pitch Processor",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 0, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 30, gateLength: 1, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [
                TrackPatternSlot(
                    slotIndex: 0,
                    sourceRef: SourceRef(
                        mode: .clip,
                        generatorID: nil,
                        clipID: clip.id,
                        modifierGeneratorID: generator.id
                    )
                )
            ],
            attachedGeneratorID: generator.id
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [72])
        XCTAssertEqual(events.map(\.velocity), [91])
        XCTAssertEqual(events.map(\.length), [3])
    }

    func test_clip_source_modifier_bypass_preserves_raw_clip_pitch() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "10101010-aaaa-bbbb-cccc-101010101010") ?? UUID(),
            name: "Bypassed Clip Modifier",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "20202020-aaaa-bbbb-cccc-202020202020")!,
            name: "Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 91, lengthSteps: 3)]),
                        fill: nil
                    )
                ]
            )
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "30303030-aaaa-bbbb-cccc-303030303030")!,
            name: "Pitch Modifier",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 0, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 30, gateLength: 1, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [
                TrackPatternSlot(
                    slotIndex: 0,
                    sourceRef: SourceRef(
                        mode: .clip,
                        generatorID: nil,
                        clipID: clip.id,
                        modifierGeneratorID: generator.id,
                        modifierBypassed: true
                    )
                )
            ]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [60])
        XCTAssertEqual(events.map(\.velocity), [91])
        XCTAssertEqual(events.map(\.length), [3])
    }

    func test_generator_source_without_modifier_emits_unmodified_source_pitch() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "40404040-aaaa-bbbb-cccc-404040404040") ?? UUID(),
            name: "Raw Generator",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "50505050-aaaa-bbbb-cccc-505050505050")!,
            name: "Source Generator",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 61),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 88, gateLength: 4, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [
                TrackPatternSlot(
                    slotIndex: 0,
                    sourceRef: SourceRef(
                        mode: .generator,
                        generatorID: generator.id,
                        clipID: nil,
                        modifierGeneratorID: nil,
                        modifierBypassed: false
                    )
                )
            ]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [61])
        XCTAssertEqual(events.map(\.velocity), [88])
        XCTAssertEqual(events.map(\.length), [4])
    }

    func test_fill_enabled_clip_step_prefers_fill_lane_over_main_lane() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "44444444-aaaa-bbbb-cccc-444444444444") ?? UUID(),
            name: "Fill Clip",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "55555555-aaaa-bbbb-cccc-555555555555")!,
            name: "Fill",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 80, lengthSteps: 2)]),
                        fill: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 118, lengthSteps: 5)])
                    )
                ]
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let fillLayer = try! XCTUnwrap(layers.first(where: { $0.target == .macroRow("fill-flag") }))
        var phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
        phrase.setCell(.single(.bool(true)), for: fillLayer.id, trackID: track.id)
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [72])
        XCTAssertEqual(events.map(\.velocity), [118])
        XCTAssertEqual(events.map(\.length), [5])
    }

    func test_saveRollingCapture_writes_a_new_note_grid_clip_to_destination_slot() {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: CapturingAudioSink())
        let track = StepSequenceTrack(
            id: UUID(uuidString: "66666666-aaaa-bbbb-cccc-666666666666") ?? UUID(),
            name: "Capture",
            pitches: [48],
            stepPattern: [false],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 70,
            gateLength: 1
        )
        let generator = monoGeneratorEntry(
            id: UUID(uuidString: "77777777-aaaa-bbbb-cccc-777777777777")!,
            name: "Source",
            trackType: .monoMelodic,
            pattern: [true],
            pitch: 65,
            velocity: 99,
            gateLength: 3
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
        )
        var document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let clipID = controller.saveRollingCapture(
            to: &document,
            trackID: track.id,
            destinationSlotIndex: 1,
            lengthSteps: 1,
            name: "Captured"
        )

        XCTAssertNotNil(clipID)
        XCTAssertEqual(document.patternBank(for: track.id).slot(at: 1).sourceRef.mode, .clip)
        XCTAssertEqual(document.patternBank(for: track.id).slot(at: 1).sourceRef.clipID, clipID)
        let capturedClip = try! XCTUnwrap(document.clipEntry(id: clipID))
        guard case let .noteGrid(lengthSteps, steps) = capturedClip.content else {
            return XCTFail("expected captured note-grid clip")
        }
        XCTAssertEqual(lengthSteps, 1)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].main?.chance, 1)
        XCTAssertEqual(steps[0].main?.notes.map(\.pitch), [65])
        XCTAssertEqual(steps[0].main?.notes.map(\.velocity), [99])
        XCTAssertEqual(steps[0].main?.notes.map(\.lengthSteps), [3])
    }

    func test_setAuditionOverride_playsPseudoClipInsteadOfLiveSourceAndLoops() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (document, track) = makeAuditionOverrideDocument()
        let override = PseudoClipState(
            sourceTrackID: track.id,
            startStep: 0,
            lengthSteps: 2,
            noteGrid: .noteGrid(
                lengthSteps: 2,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 110, lengthSteps: 2)]), fill: nil),
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 74, velocity: 112, lengthSteps: 3)]), fill: nil)
                ]
            )
        )

        controller.apply(documentModel: document)
        controller.setAuditionOverride(override, for: track.id)
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)
        controller.processTick(tickIndex: 2, now: 0.2)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [72, 74, 72])
        XCTAssertEqual(events.map(\.velocity), [110, 112, 110])
        XCTAssertEqual(events.map(\.length), [2, 3, 2])
    }

    func test_clearingAuditionOverrideRestoresLiveSourceOutput() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (document, track) = makeAuditionOverrideDocument()
        let override = PseudoClipState(
            sourceTrackID: track.id,
            startStep: 0,
            lengthSteps: 1,
            noteGrid: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 110, lengthSteps: 2)]), fill: nil)
                ]
            )
        )

        controller.apply(documentModel: document)
        controller.setAuditionOverride(override, for: track.id)
        controller.processTick(tickIndex: 0, now: 0)
        controller.setAuditionOverride(nil, for: track.id)
        controller.processTick(tickIndex: 1, now: 0.1)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [72, 60])
        XCTAssertEqual(events.map(\.velocity), [110, 90])
        XCTAssertEqual(events.map(\.length), [2, 4])
    }

    func test_setAndClearAuditionOverrideLeavesDocumentClipSlotsUnchanged() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (document, track) = makeAuditionOverrideDocument()
        let originalPatternBanks = document.patternBanks
        let originalClipPool = document.clipPool
        let override = PseudoClipState(
            sourceTrackID: track.id,
            startStep: 0,
            lengthSteps: 1,
            noteGrid: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 110, lengthSteps: 2)]), fill: nil)
                ]
            )
        )

        controller.apply(documentModel: document)
        controller.setAuditionOverride(override, for: track.id)
        controller.processTick(tickIndex: 0, now: 0)
        controller.setAuditionOverride(nil, for: track.id)

        XCTAssertEqual(document.patternBanks, originalPatternBanks)
        XCTAssertEqual(document.clipPool, originalClipPool)
    }

    func test_auditionOverrideDoesNotAppendToRollingCapture() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (document, track) = makeAuditionOverrideDocument()
        let override = PseudoClipState(
            sourceTrackID: track.id,
            startStep: 0,
            lengthSteps: 1,
            noteGrid: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 110, lengthSteps: 2)]), fill: nil)
                ]
            )
        )

        controller.apply(documentModel: document)
        controller.setAuditionOverride(override, for: track.id)
        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertTrue(controller.captureSnapshot(trackID: track.id).isEmpty)
    }

    func test_documentApplyClearsAuditionOverride() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let (document, track) = makeAuditionOverrideDocument()
        let override = PseudoClipState(
            sourceTrackID: track.id,
            startStep: 0,
            lengthSteps: 1,
            noteGrid: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 110, lengthSteps: 2)]), fill: nil)
                ]
            )
        )

        controller.apply(documentModel: document)
        controller.setAuditionOverride(override, for: track.id)
        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        let events = audioSink.receivedEvents.flatMap { $0 }
        XCTAssertEqual(events.map(\.pitch), [60])
        XCTAssertEqual(events.map(\.velocity), [90])
    }

    func test_process_tick_marks_recent_note_trigger_when_selected_source_emits_notes() {
        let controller = EngineController(client: nil, endpoint: nil)
        let track = StepSequenceTrack(
            id: UUID(uuidString: "90909090-9090-9090-9090-909090909090") ?? UUID(),
            name: "Activity",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 80,
            gateLength: 2
        )
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "91919191-9191-9191-9191-919191919191")!,
            name: "Activity Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: [true, false, false, false], pitches: [67])
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: GeneratorPoolEntry.defaultPool, clipPool: [clip])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 12.5)

        XCTAssertEqual(controller.lastNoteTriggerUptime, 12.5)
        XCTAssertEqual(controller.lastNoteTriggerCount, 1)
    }

    func test_selected_au_output_routes_note_events_to_audio_sink() throws {
        throw XCTSkip("Selecting the AU output path can restart the macOS XCTest host before assertions run; controller fan-out remains covered by the multi-track audio sink tests and manual AU smoke.")
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let synthTrack = StepSequenceTrack(
            name: "Synth",
            pitches: [64],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.55, pan: 0.35, isMuted: false),
            velocity: 96,
            gateLength: 2
        )
        let document = Project(
            version: 1,
            tracks: [synthTrack],
            selectedTrackID: synthTrack.id
        )

        controller.apply(documentModel: document)
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(audioSink.startCallCount, 1)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.pitch, 64)
        XCTAssertEqual(audioSink.receivedEvents.first?.first?.velocity, 96)
        XCTAssertEqual(audioSink.selectedInstrument, .testInstrument)
        XCTAssertEqual(controller.statusSummary, "Audio: Mock AU Instrument via Main Mixer")
        XCTAssertEqual(audioSink.receivedMixes.last, synthTrack.mix)
        XCTAssertEqual(audioSink.stopCallCount, 1)
    }

    func test_muted_track_suppresses_audio_playback_and_updates_status() {
        let audioSink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: audioSink)
        let mutedTrack = StepSequenceTrack(
            name: "Muted",
            pitches: [67],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.9, pan: 0, isMuted: true),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: mutedTrack)
        controller.processTick(tickIndex: 0, now: 0)

        XCTAssertTrue(audioSink.receivedEvents.isEmpty)
        XCTAssertEqual(controller.statusSummary, "Audio: Mock AU Instrument via Main Mixer (Muted)")
    }

    func test_effective_destination_uses_group_shared_destination_and_pitch_offset() {
        let controller = EngineController(client: nil, endpoint: nil)
        let groupID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") ?? UUID()
        let track = StepSequenceTrack(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID(),
            name: "Kick",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [track.id],
            sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 2),
            noteMapping: [track.id: 12]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            trackGroups: [group],
            selectedTrackID: track.id,
            phrases: [PhraseModel.default(tracks: [track])],
            selectedPhraseID: PhraseModel.default(tracks: [track]).id
        )

        controller.apply(documentModel: document)

        let resolved = controller.effectiveDestination(for: track.id)
        XCTAssertEqual(resolved.destination, .midi(port: .sequencerAIOut, channel: 9, noteOffset: 2))
        XCTAssertEqual(resolved.pitchOffset, 12)
    }

    func test_effective_destination_returns_none_when_inherited_group_has_no_shared_destination() {
        let controller = EngineController(client: nil, endpoint: nil)
        let groupID = UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-ffffffffffff") ?? UUID()
        let track = StepSequenceTrack(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
            name: "Hat",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [track.id], sharedDestination: nil)
        let phrase = PhraseModel.default(tracks: [track])
        let document = Project(
            version: 1,
            tracks: [track],
            trackGroups: [group],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)

        let resolved = controller.effectiveDestination(for: track.id)
        XCTAssertEqual(resolved.destination, .none)
        XCTAssertEqual(resolved.pitchOffset, 0)
    }

    func test_effective_destination_per_channel_uses_shared_midi_port_and_member_channel() {
        let controller = EngineController(client: nil, endpoint: nil)
        let groupID = UUID()
        let memberID = UUID()
        let track = StepSequenceTrack(
            id: memberID,
            name: "Clap",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let port = MIDIEndpointName(displayName: "Kit Port", isVirtual: false)
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [memberID],
            sharedDestination: .midi(port: port, channel: 9, noteOffset: 12),
            triggerMappingMode: .perChannel,
            noteMapping: [memberID: 24],
            channelMapping: [memberID: 4]
        )
        let phrase = PhraseModel.default(tracks: [track])
        let document = Project(
            version: 1,
            tracks: [track],
            trackGroups: [group],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)

        let resolved = controller.effectiveDestination(for: memberID)
        XCTAssertEqual(resolved.destination, .midi(port: port, channel: 4, noteOffset: 0))
        XCTAssertEqual(resolved.pitchOffset, 0)
    }

    func test_effective_destination_per_channel_fails_safe_without_midi_shared_destination() {
        let groupID = UUID()
        let memberID = UUID()
        let track = StepSequenceTrack(
            id: memberID,
            name: "Tom",
            pitches: [60],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let phrase = PhraseModel.default(tracks: [track])
        let nilShared = Project(
            version: 1,
            tracks: [track],
            trackGroups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [memberID],
                    sharedDestination: nil,
                    triggerMappingMode: .perChannel,
                    channelMapping: [memberID: 3]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let nonMIDIShared = Project(
            version: 1,
            tracks: [track],
            trackGroups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [memberID],
                    sharedDestination: .sample(sampleID: UUID(), settings: .default),
                    triggerMappingMode: .perChannel,
                    channelMapping: [memberID: 3]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(EngineController.effectiveDestination(for: memberID, in: nilShared).destination, .none)
        XCTAssertEqual(EngineController.effectiveDestination(for: memberID, in: nonMIDIShared).destination, .none)
    }

    func test_effective_destination_individual_mode_respects_own_destination_and_fails_inherited_marker_safe() {
        let groupID = UUID()
        let inherited = StepSequenceTrack(
            id: UUID(),
            name: "Inherited",
            pitches: [60],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let ownDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Own", isVirtual: false),
            channel: 6,
            noteOffset: 7
        )
        let own = StepSequenceTrack(
            id: UUID(),
            name: "Own",
            pitches: [60],
            stepPattern: [true],
            destination: ownDestination,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [inherited.id, own.id],
            sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0),
            triggerMappingMode: .individual
        )
        let phrase = PhraseModel.default(tracks: [inherited, own])
        let document = Project(
            version: 1,
            tracks: [inherited, own],
            trackGroups: [group],
            selectedTrackID: inherited.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        XCTAssertEqual(EngineController.effectiveDestination(for: inherited.id, in: document).destination, .none)
        XCTAssertEqual(EngineController.effectiveDestination(for: own.id, in: document).destination, ownDestination)
    }

    func test_multiple_audio_tracks_all_play_when_transport_ticks() {
        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let bassTrack = StepSequenceTrack(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
            name: "Bass",
            pitches: [48],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.6, pan: -0.2, isMuted: false),
            velocity: 90,
            gateLength: 2
        )
        let leadTrack = StepSequenceTrack(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
            name: "Lead",
            pitches: [72],
            stepPattern: [true],
            stepAccents: [true],
            destination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            mix: TrackMixSettings(level: 0.8, pan: 0.3, isMuted: false),
            velocity: 100,
            gateLength: 2
        )
        let bassGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "cccccccc-3333-3333-3333-333333333333")!,
            name: "Bass Audio Program",
            trackType: bassTrack.trackType,
            pattern: [true],
            pitch: 48,
            velocity: 90,
            gateLength: 2
        )
        let leadGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "dddddddd-4444-4444-4444-444444444444")!,
            name: "Lead Audio Program",
            trackType: leadTrack.trackType,
            pattern: [true],
            pitch: 72,
            velocity: 100,
            gateLength: 2
        )
        let generators = [bassGenerator, leadGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [bassTrack, leadTrack])
        let phrase = PhraseModel.default(tracks: [bassTrack, leadTrack], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: bassTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(bassGenerator.id))]
            ),
            TrackPatternBank(
                trackID: leadTrack.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(leadGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [bassTrack, leadTrack],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: leadTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(createdSinks.count, 2)
        XCTAssertEqual(createdSinks[0].receivedEvents.first?.first?.pitch, 48)
        XCTAssertEqual(createdSinks[1].receivedEvents.first?.first?.pitch, 72)
        XCTAssertEqual(createdSinks[1].selectedInstrument, .testInstrument)
    }

    func test_apply_document_model_prepares_audio_unit_hosts_before_playback() {
        let sink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let track = StepSequenceTrack(
            name: "Prepared",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: track)

        XCTAssertGreaterThanOrEqual(sink.prepareCallCount, 1)
    }

    func test_processTick_doesNotReapplyUnchangedAudioDestinationEveryDispatch() {
        let sink = CapturingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let track = StepSequenceTrack(
            name: "Stable AU",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
            velocity: 100,
            gateLength: 2
        )

        controller.apply(track: track)
        XCTAssertEqual(sink.receivedDestinations.count, 1)

        controller.processTick(tickIndex: 0, now: 0)
        controller.processTick(tickIndex: 1, now: 0.1)
        controller.processTick(tickIndex: 2, now: 0.2)

        XCTAssertEqual(sink.receivedDestinations.count, 1)
        XCTAssertEqual(sink.receivedEvents.count, 3)
    }

    func test_group_inherited_audio_destination_reuses_one_host_and_applies_pitch_offsets() {
        var createdSinks: [CapturingAudioSink] = []
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutputFactory: {
                let sink = CapturingAudioSink()
                createdSinks.append(sink)
                return sink
            }
        )
        let groupID = UUID(uuidString: "12121212-3434-5656-7878-909090909090") ?? UUID()
        let kick = StepSequenceTrack(
            id: UUID(uuidString: "abababab-abab-abab-abab-abababababab") ?? UUID(),
            name: "Kick",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let snare = StepSequenceTrack(
            id: UUID(uuidString: "cdcdcdcd-cdcd-cdcd-cdcd-cdcdcdcdcdcd") ?? UUID(),
            name: "Snare",
            pitches: [60],
            stepPattern: [true],
            stepAccents: [false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 2
        )
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [kick.id, snare.id],
            sharedDestination: .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil),
            noteMapping: [kick.id: 0, snare.id: 12]
        )
        let kickGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "eeeeeeee-5555-5555-5555-555555555555")!,
            name: "Kick Program",
            trackType: kick.trackType,
            pattern: [true],
            pitch: 60,
            velocity: 100,
            gateLength: 2
        )
        let snareGenerator = monoGeneratorEntry(
            id: UUID(uuidString: "ffffffff-6666-6666-6666-666666666666")!,
            name: "Snare Program",
            trackType: snare.trackType,
            pattern: [true],
            pitch: 60,
            velocity: 100,
            gateLength: 2
        )
        let generators = [kickGenerator, snareGenerator]
        let layers = PhraseLayerDefinition.defaultSet(for: [kick, snare])
        let phrase = PhraseModel.default(tracks: [kick, snare], layers: layers, generatorPool: generators, clipPool: [])
        let patternBanks = [
            TrackPatternBank(
                trackID: kick.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(kickGenerator.id))]
            ),
            TrackPatternBank(
                trackID: snare.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(snareGenerator.id))]
            )
        ]
        let document = Project(
            version: 1,
            tracks: [kick, snare],
            trackGroups: [group],
            generatorPool: generators,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: patternBanks,
            selectedTrackID: kick.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        controller.apply(documentModel: document)
        controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(createdSinks.count, 1)
        let playedPitches = createdSinks[0].receivedEvents.flatMap { $0 }.map(\.pitch).sorted()
        XCTAssertEqual(playedPitches, [60, 72])
        XCTAssertEqual(createdSinks[0].selectedInstrument, .testInstrument)
    }

    /// Arming with phrase quantize schedules the record start at the next
    /// phrase-cycle boundary; bar quantize keeps the next-bar behavior.
    func test_armAudioInput_quantizesToBarOrPhrase() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2

        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        if let phraseIndex = project.phrases.firstIndex(where: { $0.id == project.selectedPhraseID }) {
            project.phrases[phraseIndex].lengthBars = 2
        }
        controller.apply(documentModel: project)
        for tick in 0...5 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, quantize: .bar))
        let barArm = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(barArm.pendingStartTick, 16)

        _ = controller.cancelAudioInputArm(trackID: trackID)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, quantize: .phrase))
        let phraseArm = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(phraseArm.pendingStartTick, 32)
    }

    /// Switching the audio device must recompute audio-input route states:
    /// picking an interface with enough input channels should unlock arming
    /// without any other interaction (regression: route state stayed frozen
    /// at the old device's channel count after Preferences device changes).
    func test_applyAudioDeviceUIDs_resyncsAudioInputRouteState() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 1
        controller.audioDeviceApplyOverrideForTesting = { inputUID, outputUID in
            AudioDeviceApplyResult(
                appliedInputDeviceUID: inputUID,
                appliedOutputDeviceUID: outputUID,
                wasRunningBeforeApply: false,
                restartedEngine: false
            )
        }

        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        let beforeSwitch = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(beforeSwitch.routeState, .silentUnavailable)

        controller.audioInputAvailableChannelCountOverrideForTesting = 24
        _ = try controller.applyAudioDeviceUIDs(inputUID: "big-interface", outputUID: nil)

        let afterSwitch = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(afterSwitch.routeState, .available)
    }

    func test_audioInputRuntime_setupIsLimitedToOneTrackAndTearsDownOnRemoval() {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let firstInputID = project.selectedTrackID
        project.appendTrack(trackType: .audioInput)
        let secondInputID = project.selectedTrackID

        controller.apply(documentModel: project)

        XCTAssertEqual(controller.audioInputRuntimeTrackIDs, [firstInputID])
        XCTAssertNil(controller.audioInputRuntime(for: secondInputID))

        project.removeSelectedTrack()
        project.selectedTrackID = firstInputID
        project.removeSelectedTrack()
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.audioInputRuntimeTrackIDs.isEmpty)
    }

    func test_audioInputRuntime_acceptsArmAndCancelCommands() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 128))
        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .armed)
        XCTAssertEqual(runtime.pendingStartTick, 128)

        XCTAssertTrue(controller.cancelAudioInputArm(trackID: trackID))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .idle)
        XCTAssertNil(runtime.pendingStartTick)
    }

    func test_audioInputRuntime_acceptsMonitorModeAndInputChannelCommands() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .loop))
        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.monitorMode, .loop)
        XCTAssertTrue(runtime.isSilent)

        XCTAssertTrue(controller.markAudioInputLoopPlaceholder(trackID: trackID, waveformBuckets: [0, 0.5, 0.25]))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .hasLoop)
        XCTAssertEqual(runtime.waveformBuckets, [0, 0.5, 0.25])
        XCTAssertFalse(runtime.isSilent)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono2))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.selectedInputChannel, .mono2)
        XCTAssertEqual(runtime.routeState, .available)
    }

    func test_audioInputRuntime_applySyncsAuthoredRecordLengthAndInputChannelChanges() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono1))
        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.selectedInputChannel, .mono1)

        project.tracks[project.selectedTrackIndex].recordBarLength = 4
        controller.apply(documentModel: project)

        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.selectedInputChannel, .stereo)

        project.tracks[project.selectedTrackIndex].inputChannel = .mono2
        controller.apply(documentModel: project)

        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.selectedInputChannel, .mono2)
        XCTAssertEqual(runtime.routeState, .available)
    }

    func test_audioInputRuntime_invalidRouteStaysSilentAndNonCrashing() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 1
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertFalse(controller.armAudioInput(trackID: trackID))
        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.selectedInputChannel, .stereo)
        XCTAssertEqual(runtime.routeState, .silentUnavailable)
        XCTAssertTrue(runtime.isSilent)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono1))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.routeState, .available)
        XCTAssertFalse(runtime.isSilent)
    }

    func test_audioInputCapture_armStartsOnNextBarBoundary() throws {
        let (controller, _, trackID) = makeAudioInputSchedulingFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID))
        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .armed)
        XCTAssertEqual(runtime.pendingStartTick, 4)

        controller.processTick(tickIndex: 3, now: 0.3)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .armed)
        XCTAssertEqual(runtime.pendingStartTick, 4)

        controller.processTick(tickIndex: 4, now: 0.4)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .recording)
        XCTAssertEqual(runtime.captureStartTick, 4)
        XCTAssertEqual(runtime.captureEndTick, 8)
    }

    func test_audioInputCapture_cancelBeforeStartPreventsRecording() throws {
        let (controller, _, trackID) = makeAudioInputSchedulingFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID))
        XCTAssertTrue(controller.cancelAudioInputArm(trackID: trackID))
        controller.processTick(tickIndex: 4, now: 0.4)

        let runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .idle)
        XCTAssertNil(runtime.pendingStartTick)
        XCTAssertNil(runtime.captureStartTick)
        XCTAssertNil(runtime.recordedLoopID)
    }

    func test_audioInputCapture_autoStopsAllSupportedBarLengths() throws {
        for bars in [1, 2, 4, 8] {
            let (controller, _, trackID) = makeAudioInputSchedulingFixture(recordBarLength: bars)

            XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
            controller.processTick(tickIndex: 4, now: 0.4)
            var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
            XCTAssertEqual(runtime.armState, .recording)
            XCTAssertEqual(runtime.captureEndTick, UInt64(4 + bars * 4))

            controller.processTick(tickIndex: UInt64(4 + bars * 4), now: Double(bars))
            runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
            XCTAssertEqual(runtime.armState, .hasLoop)
            XCTAssertEqual(runtime.recordedLoopBarLength, bars)
            XCTAssertEqual(runtime.transientFrameCount, bars * 4)
            XCTAssertNotNil(runtime.recordedLoopID)
            XCTAssertNil(runtime.captureEndTick)
        }
    }

    func test_audioInputCapture_completionDestructivelyReplacesPreviousLoopBuffer() throws {
        let (controller, project, trackID) = makeAudioInputSchedulingFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.processTick(tickIndex: 8, now: 0.8)
        let firstRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        let firstLoopID = try XCTUnwrap(firstRuntime.recordedLoopID)

        var updatedProject = project
        updatedProject.tracks[updatedProject.selectedTrackIndex].recordBarLength = 2
        controller.apply(documentModel: updatedProject)
        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 12))
        controller.processTick(tickIndex: 12, now: 1.2)
        controller.processTick(tickIndex: 20, now: 2.0)

        let secondRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(secondRuntime.armState, .hasLoop)
        XCTAssertEqual(secondRuntime.recordedLoopBarLength, 2)
        XCTAssertNotEqual(secondRuntime.recordedLoopID, firstLoopID)
    }

    func test_audioInputCaptureStore_preservesReservedPCMSamplesForPlaybackBuffer() throws {
        let store = AudioInputCaptureStore(bucketCount: 4)
        let trackID = UUID()
        let plan = AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: 5)
        let firstSource = makeAudioInputLoopBuffer(
            left: [0.1, -0.2, 0.3],
            right: [0.4, -0.5, 0.6]
        )
        let secondSource = makeAudioInputLoopBuffer(
            left: [-0.7, 0.8],
            right: [0.9, -1.0]
        )
        let firstSummary = AudioInputCaptureStore.summarize(buffer: firstSource)
        let secondSummary = AudioInputCaptureStore.summarize(buffer: secondSource)

        _ = store.beginCapture(trackID: trackID, plan: plan)
        let writer = try XCTUnwrap(store.pcmWriterForActiveCapture(trackID: trackID))
        let firstReceipt = try XCTUnwrap(writer.copy(trackID: trackID, from: firstSource))
        let secondReceipt = try XCTUnwrap(writer.copy(trackID: trackID, from: secondSource))

        firstSource.floatChannelData![0][0] = 1.0
        firstSource.floatChannelData![1][2] = 1.0
        secondSource.floatChannelData![0][0] = 1.0
        secondSource.floatChannelData![1][1] = 1.0

        _ = store.process(
            packet: AudioInputCaptureBufferPacket(
                summary: firstSummary,
                captureWriterID: firstReceipt.writerID,
                copiedFrameCount: firstReceipt.frameCount
            ),
            trackID: trackID
        )
        _ = store.process(
            packet: AudioInputCaptureBufferPacket(
                summary: secondSummary,
                captureWriterID: secondReceipt.writerID,
                copiedFrameCount: secondReceipt.frameCount
            ),
            trackID: trackID
        )
        let completed = store.completeCapture(trackID: trackID)

        XCTAssertEqual(completed.completedFrameCount, 5)
        let playbackBuffer = try XCTUnwrap(store.completedLoopPlaybackBuffer(trackID: trackID))
        XCTAssertEqual(playbackBuffer.frameLength, 5)
        XCTAssertEqual(playbackBuffer.format.channelCount, 2)
        XCTAssertEqual(playbackBuffer.format.sampleRate, 44_100)
        XCTAssertAudioInputBufferSamples(
            playbackBuffer,
            left: [0.1, -0.2, 0.3, -0.7, 0.8],
            right: [0.4, -0.5, 0.6, 0.9, -1.0]
        )

        playbackBuffer.floatChannelData![0][0] = 0.99
        let reconstructedAgain = try XCTUnwrap(store.completedLoopPlaybackBuffer(trackID: trackID))
        XCTAssertAudioInputBufferSamples(
            reconstructedAgain,
            left: [0.1, -0.2, 0.3, -0.7, 0.8],
            right: [0.4, -0.5, 0.6, 0.9, -1.0]
        )
    }

    func test_audioInputCaptureStore_beginBoundaryDoesNotCountBuffersWithoutActivePCMReceipt() throws {
        let store = AudioInputCaptureStore(bucketCount: 4)
        let slot = AudioInputCapturePCMWriterSlot()
        let trackID = UUID()
        let plan = AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: 8)
        let writer = try XCTUnwrap(AudioInputCapturePCMWriter(trackID: trackID, plan: plan))
        let boundarySource = makeAudioInputLoopBuffer(
            left: [0.8, 0.7, 0.6],
            right: [0.5, 0.4, 0.3]
        )
        let activeSource = makeAudioInputLoopBuffer(
            left: [0.1, -0.2],
            right: [0.3, -0.4]
        )
        let boundarySummary = AudioInputCaptureStore.summarize(buffer: boundarySource)
        let activeSummary = AudioInputCaptureStore.summarize(buffer: activeSource)

        slot.install(writer)
        let boundaryReceipt = slot.copy(trackID: trackID, from: boundarySource)
        _ = store.beginCapture(trackID: trackID, writer: writer)
        _ = store.process(
            packet: AudioInputCaptureBufferPacket(
                summary: boundarySummary,
                captureWriterID: boundaryReceipt?.writerID,
                copiedFrameCount: boundaryReceipt?.frameCount ?? 0
            ),
            trackID: trackID
        )

        XCTAssertNil(boundaryReceipt)

        let activeReceipt = try XCTUnwrap(slot.copy(trackID: trackID, from: activeSource))
        _ = store.process(
            packet: AudioInputCaptureBufferPacket(
                summary: activeSummary,
                captureWriterID: activeReceipt.writerID,
                copiedFrameCount: activeReceipt.frameCount
            ),
            trackID: trackID
        )
        let completed = store.completeCapture(trackID: trackID)

        XCTAssertEqual(completed.completedFrameCount, 2)
        let playbackBuffer = try XCTUnwrap(store.completedLoopPlaybackBuffer(trackID: trackID))
        XCTAssertEqual(playbackBuffer.frameLength, 2)
        XCTAssertAudioInputBufferSamples(
            playbackBuffer,
            left: [0.1, -0.2],
            right: [0.3, -0.4]
        )
    }

    func test_audioInputCapture_continuesAcrossWorkspaceSelectionChanges() throws {
        let (controller, project, trackID) = makeAudioInputSchedulingFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        var navigatedProject = project
        let nonInputTrackID = try XCTUnwrap(navigatedProject.tracks.first { $0.id != trackID }?.id)
        navigatedProject.selectedTrackID = nonInputTrackID
        controller.apply(documentModel: navigatedProject)

        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .armed)
        XCTAssertEqual(runtime.pendingStartTick, 4)

        controller.processTick(tickIndex: 4, now: 0.4)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .recording)

        navigatedProject.selectedTrackID = trackID
        controller.apply(documentModel: navigatedProject)
        controller.processTick(tickIndex: 8, now: 0.8)

        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .hasLoop)
        XCTAssertEqual(runtime.recordedLoopBarLength, 1)
        XCTAssertNotNil(runtime.recordedLoopID)
    }

    func test_audioInputLoopModeWithRecordedLoopEntersOnNextBarBoundary() throws {
        let (controller, project, trackID) = makeAudioInputSchedulingFixture(recordBarLength: 1)
        var routedProject = project
        routedProject.tracks[routedProject.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.62,
            pan: -0.15,
            isMuted: false,
            sendA: 0.35,
            sendB: 0.2
        )
        controller.apply(documentModel: routedProject)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.recordAudioInputBufferForTesting(
            trackID: trackID,
            buffer: makeAudioInputLoopBuffer(left: [0.1, -0.5, 0.2, 0.4], right: [0.2, -0.25, 0.7, 0.1])
        )
        controller.drainAudioInputCapturePublicationForTesting()
        controller.processTick(tickIndex: 8, now: 0.8)
        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .loop))

        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        var readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(runtime.monitorMode, .loop)
        XCTAssertEqual(runtime.activeMonitorMode, .input)
        XCTAssertEqual(runtime.pendingLoopStartTick, 12)
        XCTAssertEqual(readout.requestedSource, .input)
        XCTAssertNil(readout.scheduledLoopFrameCount)

        controller.processTick(tickIndex: 11, now: 1.1)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(runtime.activeMonitorMode, .input)
        XCTAssertNil(readout.scheduledLoopFrameCount)

        controller.processTick(tickIndex: 12, now: 1.2)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(runtime.activeMonitorMode, .loop)
        XCTAssertNil(runtime.pendingLoopStartTick)
        XCTAssertEqual(runtime.scheduledLoopPlaybackID, runtime.recordedLoopID)
        XCTAssertEqual(readout.requestedSource, .loop)
        XCTAssertEqual(readout.connectedSource, .loop)
        XCTAssertEqual(readout.scheduledLoopFrameCount, 4)
        XCTAssertEqual(readout.scheduledLoopChannelCount, 2)
        XCTAssertEqual(readout.scheduledLoopSampleRate, 44_100)
        XCTAssertEqual(readout.loopPlaybackScheduleCount, 1)
        XCTAssertTrue(
            readout.loopPlayer.engine?.outputConnectionPoints(for: readout.loopPlayer, outputBus: 0).first?.node === readout.outputMixer
        )
        let sendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        XCTAssertTrue(readout.dryDestination === sendReadout.dryDestination)
        XCTAssertEqual(readout.outputVolume, 0.62, accuracy: 0.0001)
        XCTAssertEqual(readout.pan, -0.15, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendAGain, 0.35, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendBGain, 0.2, accuracy: 0.0001)

        controller.processTick(tickIndex: 16, now: 1.6)
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.loopPlaybackScheduleCount, 1)

        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .input))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(runtime.activeMonitorMode, .input)
        XCTAssertNil(runtime.scheduledLoopPlaybackID)
        XCTAssertEqual(readout.requestedSource, .input)
        XCTAssertEqual(readout.connectedSource, .input)
        XCTAssertNil(readout.scheduledLoopFrameCount)

        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .loop))
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.activeMonitorMode, .input)
        XCTAssertEqual(runtime.pendingLoopStartTick, 20)

        controller.processTick(tickIndex: 20, now: 2.0)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(runtime.activeMonitorMode, .loop)
        XCTAssertEqual(runtime.scheduledLoopPlaybackID, runtime.recordedLoopID)
        XCTAssertEqual(readout.connectedSource, .loop)
        XCTAssertEqual(readout.scheduledLoopFrameCount, 4)
        XCTAssertEqual(readout.loopPlaybackScheduleCount, 2)
    }

    func test_audioInputRouting_inputModeUsesLiveInputRequestThroughMixerPath() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.tracks[project.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.65,
            pan: -0.25,
            isMuted: false,
            sendA: 0.2,
            sendB: 0.3
        )

        controller.apply(documentModel: project)

        let readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.requestedSource, .input)
        XCTAssertEqual(readout.selectedChannel, .stereo)
        XCTAssertNotNil(readout.dryDestination)
        XCTAssertEqual(readout.outputVolume, 0.65, accuracy: 0.0001)
        XCTAssertEqual(readout.pan, -0.25, accuracy: 0.0001)
        XCTAssertTrue(readout.connectedSource == .input || readout.connectedSource == .silent)
    }

    func test_audioInputRouting_mixUpdateUsesScopedParameterPathWithoutTapChurn() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(client: nil, endpoint: nil, mainAudioGraph: graph)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.tracks[project.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.8,
            pan: -0.1,
            isMuted: false,
            sendA: 0.15,
            sendB: 0.25
        )

        controller.apply(documentModel: project)
        let fullSyncsBefore = graph.audioInputFullRoutingSyncCountForTesting
        let scopedUpdatesBefore = graph.audioInputScopedRoutingUpdateCountForTesting
        let tapInstallsBefore = graph.masterMeterTapInstallCountForTesting
        let tapRemovesBefore = graph.masterMeterTapRemoveCountForTesting
        let tapGenerationBefore = graph.masterMeterTapGenerationForTesting

        controller.setMix(
            trackID: trackID,
            mix: TrackMixSettings(level: 0.35, pan: 0.45, isMuted: false, sendA: 0.6, sendB: 0.05)
        )

        let readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let sendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.outputVolume, 0.35, accuracy: 0.0001)
        XCTAssertEqual(readout.pan, 0.45, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendAGain, 0.6, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendBGain, 0.05, accuracy: 0.0001)
        XCTAssertEqual(graph.audioInputFullRoutingSyncCountForTesting, fullSyncsBefore)
        XCTAssertEqual(graph.audioInputScopedRoutingUpdateCountForTesting, scopedUpdatesBefore + 1)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, tapInstallsBefore)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovesBefore)
        XCTAssertEqual(graph.masterMeterTapGenerationForTesting, tapGenerationBefore)
    }

    @MainActor
    func test_audioInputRouting_targetsAuthoredBusAndPreservesSendFanoutAcrossDocumentOutputBusMutation() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(client: nil, endpoint: nil, mainAudioGraph: graph)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        let dryBusID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let mutatedBusID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        var project = Project.empty
        project.buses = [
            MixerBus(id: dryBusID, name: "Input Dry"),
            MixerBus(id: mutatedBusID, name: "Input Alt"),
        ]
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.setTrackOutputBus(trackID: trackID, busID: dryBusID)
        project.tracks[project.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.7,
            pan: -0.2,
            isMuted: false,
            sendA: 0.4,
            sendB: 0.25
        )

        controller.apply(documentModel: project)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: controller,
            debounceInterval: .seconds(100)
        )
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let initialReadout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let initialSendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        let dryBus = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: dryBusID))
        let sendA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let sendB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))
        XCTAssertTrue(initialReadout.dryDestination === dryBus.inputMixer)
        XCTAssertTrue(initialSendReadout.dryDestination === dryBus.inputMixer)
        XCTAssertTrue(initialSendReadout.sendADestination === sendA.inputMixer)
        XCTAssertTrue(initialSendReadout.sendBDestination === sendB.inputMixer)
        XCTAssertEqual(initialReadout.outputVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(initialReadout.pan, -0.2, accuracy: 0.0001)
        XCTAssertEqual(initialSendReadout.sendAGain, 0.4, accuracy: 0.0001)
        XCTAssertEqual(initialSendReadout.sendBGain, 0.25, accuracy: 0.0001)

        let fullSyncsBeforeMutation = graph.audioInputFullRoutingSyncCountForTesting
        let scopedUpdatesBeforeMutation = graph.audioInputScopedRoutingUpdateCountForTesting
        let tapInstallsBeforeMutation = graph.masterMeterTapInstallCountForTesting
        let tapRemovesBeforeMutation = graph.masterMeterTapRemoveCountForTesting
        let tapGenerationBeforeMutation = graph.masterMeterTapGenerationForTesting

        session.setTrackOutputBus(trackID: trackID, busID: mutatedBusID)

        let outputBusReadout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let outputBusSendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        let mutatedBus = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: mutatedBusID))
        XCTAssertTrue(outputBusReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertTrue(outputBusSendReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertTrue(outputBusSendReadout.sendADestination === sendA.inputMixer)
        XCTAssertTrue(outputBusSendReadout.sendBDestination === sendB.inputMixer)
        XCTAssertEqual(outputBusReadout.outputVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(outputBusReadout.pan, -0.2, accuracy: 0.0001)
        XCTAssertEqual(outputBusSendReadout.sendAGain, 0.4, accuracy: 0.0001)
        XCTAssertEqual(outputBusSendReadout.sendBGain, 0.25, accuracy: 0.0001)
        XCTAssertEqual(graph.audioInputFullRoutingSyncCountForTesting, fullSyncsBeforeMutation)
        XCTAssertEqual(graph.audioInputScopedRoutingUpdateCountForTesting, scopedUpdatesBeforeMutation + 1)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, tapInstallsBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovesBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapGenerationForTesting, tapGenerationBeforeMutation)
        XCTAssertFalse(graph.engine.isRunning)

        controller.setMix(
            trackID: trackID,
            mix: TrackMixSettings(
                level: 0.9,
                pan: 0.35,
                isMuted: true,
                sendA: 0.1,
                sendB: 0.75
            )
        )

        let mutatedReadout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let mutatedSendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        XCTAssertTrue(mutatedReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertTrue(mutatedSendReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertTrue(mutatedSendReadout.sendADestination === sendA.inputMixer)
        XCTAssertTrue(mutatedSendReadout.sendBDestination === sendB.inputMixer)
        XCTAssertEqual(mutatedReadout.outputVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(mutatedReadout.pan, 0.35, accuracy: 0.0001)
        XCTAssertEqual(mutatedSendReadout.sendAGain, 0.1, accuracy: 0.0001)
        XCTAssertEqual(mutatedSendReadout.sendBGain, 0.75, accuracy: 0.0001)
        XCTAssertEqual(graph.audioInputFullRoutingSyncCountForTesting, fullSyncsBeforeMutation)
    }

    @MainActor
    func test_audioInputRouting_documentOutputBusMutationKeepsRunningGraphWhenSendsAreInactive() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(client: nil, endpoint: nil, mainAudioGraph: graph)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        let dryBusID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let mutatedBusID = UUID(uuidString: "abababab-cdcd-efef-1212-343434343434")!
        var project = Project.empty
        project.buses = [
            MixerBus(id: dryBusID, name: "Input Dry"),
            MixerBus(id: mutatedBusID, name: "Input Alt"),
        ]
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.setTrackOutputBus(trackID: trackID, busID: dryBusID)
        project.tracks[project.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.7,
            pan: -0.2,
            isMuted: false,
            sendA: 0,
            sendB: 0
        )

        controller.apply(documentModel: project)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: controller,
            debounceInterval: .seconds(100)
        )
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        try graph.start()
        defer { graph.stop() }
        XCTAssertTrue(graph.engine.isRunning)
        let fullSyncsBeforeMutation = graph.audioInputFullRoutingSyncCountForTesting
        let scopedUpdatesBeforeMutation = graph.audioInputScopedRoutingUpdateCountForTesting
        let tapInstallsBeforeMutation = graph.masterMeterTapInstallCountForTesting
        let tapRemovesBeforeMutation = graph.masterMeterTapRemoveCountForTesting
        let tapGenerationBeforeMutation = graph.masterMeterTapGenerationForTesting

        session.setTrackOutputBus(trackID: trackID, busID: mutatedBusID)

        let readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let mutatedBus = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: mutatedBusID))
        XCTAssertTrue(readout.dryDestination === mutatedBus.inputMixer)
        XCTAssertEqual(readout.outputVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(readout.pan, -0.2, accuracy: 0.0001)
        XCTAssertEqual(graph.audioInputFullRoutingSyncCountForTesting, fullSyncsBeforeMutation)
        XCTAssertEqual(graph.audioInputScopedRoutingUpdateCountForTesting, scopedUpdatesBeforeMutation + 1)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, tapInstallsBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovesBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapGenerationForTesting, tapGenerationBeforeMutation)
        XCTAssertTrue(graph.engine.isRunning)
    }

    @MainActor
    func test_audioInputRouting_documentOutputBusMutationPreservesActiveSendFanoutWhileRunning() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(client: nil, endpoint: nil, mainAudioGraph: graph)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        let dryBusID = UUID(uuidString: "23232323-4545-6767-8989-101010101010")!
        let mutatedBusID = UUID(uuidString: "bcbcbcbc-dede-fafa-2323-454545454545")!
        var project = Project.empty
        project.buses = [
            MixerBus(id: dryBusID, name: "Input Dry"),
            MixerBus(id: mutatedBusID, name: "Input Alt"),
        ]
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.setTrackOutputBus(trackID: trackID, busID: dryBusID)
        project.tracks[project.selectedTrackIndex].mix = TrackMixSettings(
            level: 0.7,
            pan: -0.2,
            isMuted: false,
            sendA: 0.4,
            sendB: 0.25
        )

        controller.apply(documentModel: project)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: controller,
            debounceInterval: .seconds(100)
        )
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        try graph.start()
        defer { graph.stop() }
        XCTAssertTrue(graph.engine.isRunning)
        let fullSyncsBeforeMutation = graph.audioInputFullRoutingSyncCountForTesting
        let scopedUpdatesBeforeMutation = graph.audioInputScopedRoutingUpdateCountForTesting
        let tapInstallsBeforeMutation = graph.masterMeterTapInstallCountForTesting
        let tapRemovesBeforeMutation = graph.masterMeterTapRemoveCountForTesting
        let tapGenerationBeforeMutation = graph.masterMeterTapGenerationForTesting

        session.setTrackOutputBus(trackID: trackID, busID: mutatedBusID)

        let outputBusReadout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        let sendReadout = try XCTUnwrap(controller.audioInputTrackSendReadoutForTesting(trackID: trackID))
        let mutatedBus = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: mutatedBusID))
        let sendA = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendA))
        let sendB = try XCTUnwrap(graph.sendBusReadoutForTesting(busID: .sendB))
        let fanout = try XCTUnwrap(sendReadout.sendFanoutNode)
        let sourceOutputs = graph.engine.outputConnectionPoints(for: outputBusReadout.outputMixer, outputBus: 0)

        XCTAssertTrue(outputBusReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertTrue(sendReadout.dryDestination === mutatedBus.inputMixer)
        XCTAssertEqual(sourceOutputs.count, 1)
        XCTAssertTrue(sourceOutputs[0].node === fanout)
        XCTAssertEqual(sendReadout.sendFanoutDestinations.count, 3)
        XCTAssertTrue(sendReadout.sendFanoutDestinations.contains { $0 === mutatedBus.inputMixer })
        XCTAssertTrue(sendReadout.sendFanoutDestinations.contains { $0 === sendReadout.sendAGainNode })
        XCTAssertTrue(sendReadout.sendFanoutDestinations.contains { $0 === sendReadout.sendBGainNode })
        XCTAssertTrue(sendReadout.sendADestination === sendA.inputMixer)
        XCTAssertTrue(sendReadout.sendBDestination === sendB.inputMixer)
        XCTAssertEqual(outputBusReadout.outputVolume, 0.7, accuracy: 0.0001)
        XCTAssertEqual(outputBusReadout.pan, -0.2, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendAGain, 0.4, accuracy: 0.0001)
        XCTAssertEqual(sendReadout.sendBGain, 0.25, accuracy: 0.0001)
        XCTAssertEqual(graph.audioInputFullRoutingSyncCountForTesting, fullSyncsBeforeMutation)
        XCTAssertEqual(graph.audioInputScopedRoutingUpdateCountForTesting, scopedUpdatesBeforeMutation + 1)
        XCTAssertEqual(graph.masterMeterTapInstallCountForTesting, tapInstallsBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapRemoveCountForTesting, tapRemovesBeforeMutation)
        XCTAssertEqual(graph.masterMeterTapGenerationForTesting, tapGenerationBeforeMutation)
        XCTAssertTrue(graph.engine.isRunning)
    }

    func test_audioInputRouting_loopModeWithoutLoopStaysSilent() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .loop))

        let runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        let readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertTrue(runtime.isSilent)
        XCTAssertEqual(readout.requestedSource, .silent)
        XCTAssertEqual(readout.connectedSource, .silent)
        XCTAssertEqual(readout.outputVolume, 0, accuracy: 0.0001)
        XCTAssertNil(readout.scheduledLoopFrameCount)
    }

    func test_audioInputRouting_loopPlaceholderUsesPlayerAndExcludesInputPath() throws {
        let controller = EngineController(client: nil, endpoint: nil, stepsPerBar: 4)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.markAudioInputLoopPlaceholder(trackID: trackID))
        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .loop))

        var readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.requestedSource, .input)

        controller.processTick(tickIndex: 4, now: 0.4)
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.requestedSource, .loop)
        XCTAssertEqual(readout.connectedSource, .loop)
        XCTAssertTrue(
            readout.loopPlayer.engine?.outputConnectionPoints(for: readout.loopPlayer, outputBus: 0).first?.node === readout.outputMixer
        )
        XCTAssertNil(readout.scheduledLoopFrameCount)

        XCTAssertTrue(controller.setAudioInputMonitorMode(trackID: trackID, mode: .input))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.requestedSource, .input)
        XCTAssertNotEqual(readout.connectedSource, .loop)
        XCTAssertNil(readout.scheduledLoopFrameCount)
        XCTAssertTrue(
            readout.loopPlayer.engine?.outputConnectionPoints(for: readout.loopPlayer, outputBus: 0).isEmpty ?? true
        )
    }

    func test_audioInputRouting_tracksMonoAndStereoChannelSelection() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono1))
        var readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.selectedChannel, .mono1)
        XCTAssertEqual(readout.requestedSource, .input)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono2))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.selectedChannel, .mono2)
        XCTAssertEqual(readout.requestedSource, .input)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .stereo))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.selectedChannel, .stereo)
        XCTAssertEqual(readout.requestedSource, .input)
    }

    func test_audioInputRouting_unavailableInputStaysSilentUntilValidChannelSelected() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 1
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)

        var readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.selectedChannel, .stereo)
        XCTAssertEqual(readout.requestedSource, .silent)
        XCTAssertEqual(readout.connectedSource, .silent)
        XCTAssertEqual(readout.outputVolume, 0, accuracy: 0.0001)
        XCTAssertFalse(controller.armAudioInput(trackID: trackID))
        let invalidRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(invalidRuntime.armState, .idle)

        XCTAssertTrue(controller.rerouteAudioInput(trackID: trackID, channel: .mono1))
        readout = try XCTUnwrap(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(readout.selectedChannel, .mono1)
        XCTAssertEqual(readout.requestedSource, .input)
        XCTAssertTrue(readout.connectedSource == .input || readout.connectedSource == .silent)
    }

    func test_audioInputRouting_tearsDownWhenTrackIsRemoved() throws {
        let controller = EngineController(client: nil, endpoint: nil)
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        controller.apply(documentModel: project)
        XCTAssertNotNil(controller.audioInputRoutingReadoutForTesting(trackID: trackID))

        project.removeSelectedTrack()
        controller.apply(documentModel: project)

        XCTAssertNil(controller.audioInputRuntime(for: trackID))
        XCTAssertNil(controller.audioInputRoutingReadoutForTesting(trackID: trackID))
    }
}

private func makeAudioInputSchedulingFixture(
    recordBarLength: Int
) -> (controller: EngineController, project: Project, trackID: UUID) {
    let controller = EngineController(client: nil, endpoint: nil, stepsPerBar: 4)
    controller.audioInputAvailableChannelCountOverrideForTesting = 2
    controller.audioInputCapturePlanOverrideForTesting = { _, bars in
        AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: max(1, bars * 4096))
    }
    var project = Project.empty
    project.appendTrack(trackType: .audioInput)
    let trackID = project.selectedTrackID
    project.tracks[project.selectedTrackIndex].recordBarLength = recordBarLength
    controller.apply(documentModel: project)
    return (controller, project, trackID)
}

private func makeAudioInputLoopBuffer(left: [Float], right: [Float]) -> AVAudioPCMBuffer {
    let frameCount = max(left.count, right.count)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
    buffer.frameLength = AVAudioFrameCount(frameCount)

    for frame in 0..<frameCount {
        buffer.floatChannelData![0][frame] = frame < left.count ? left[frame] : 0
        buffer.floatChannelData![1][frame] = frame < right.count ? right[frame] : 0
    }
    return buffer
}

private func XCTAssertAudioInputBufferSamples(
    _ buffer: AVAudioPCMBuffer,
    left: [Float],
    right: [Float],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(buffer.frameLength, AVAudioFrameCount(max(left.count, right.count)), file: file, line: line)
    XCTAssertEqual(buffer.format.channelCount, 2, file: file, line: line)
    guard let channels = buffer.floatChannelData else {
        return XCTFail("expected float channel data", file: file, line: line)
    }

    for frame in 0..<Int(buffer.frameLength) {
        XCTAssertEqual(channels[0][frame], frame < left.count ? left[frame] : 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(channels[1][frame], frame < right.count ? right[frame] : 0, accuracy: 0.0001, file: file, line: line)
    }
}

private func makeAuditionOverrideDocument() -> (Project, StepSequenceTrack) {
    let track = StepSequenceTrack(
        id: UUID(uuidString: "01010101-aaaa-bbbb-cccc-010101010101") ?? UUID(),
        name: "Audition Source",
        pitches: [60],
        stepPattern: [true],
        stepAccents: [false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 90,
        gateLength: 4
    )
    let generator = monoGeneratorEntry(
        id: UUID(uuidString: "02020202-aaaa-bbbb-cccc-020202020202")!,
        name: "Live Source",
        trackType: track.trackType,
        pattern: [true],
        pitch: 60,
        velocity: 90,
        gateLength: 4
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
    let patternBank = TrackPatternBank(
        trackID: track.id,
        slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
    )
    let document = Project(
        version: 1,
        tracks: [track],
        generatorPool: [generator],
        clipPool: [],
        layers: layers,
        routes: [],
        patternBanks: [patternBank],
        selectedTrackID: track.id,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    return (document, track)
}

private func monoGeneratorEntry(
    id: UUID,
    name: String,
    trackType: TrackType,
    pattern: [Bool],
    pitch: Int,
    velocity: Int,
    gateLength: Int
) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: id,
        name: name,
        trackType: trackType,
        kind: .monoGenerator,
        params: .mono(
            trigger: .native(euclideanAlgo(matching: pattern)),
            pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
            shape: NoteShape(velocity: velocity, gateLength: gateLength, accent: false)
        )
    )
}

private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}

private final class CapturingAudioSink: TrackPlaybackSink {
    let displayName = "Mock AU Instrument"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
    private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit? = nil
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var prepareCallCount = 0
    private(set) var receivedEvents: [[NoteEvent]] = []
    private(set) var receivedMixes: [TrackMixSettings] = []
    private(set) var receivedDestinations: [Destination] = []

    func prepareIfNeeded() {
        prepareCallCount += 1
    }

    func startIfNeeded() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func shutdown() {
        stopCallCount += 1
    }

    func setMix(_ mix: TrackMixSettings) {
        receivedMixes.append(mix)
    }

    func setDestination(_ destination: Destination) {
        receivedDestinations.append(destination)
        if case let .auInstrument(componentID, _) = destination {
            selectedInstrument = availableInstruments.first(where: { $0.audioComponentID == componentID }) ?? .builtInSynth
        }
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }

    func captureStateBlob() throws -> Data? {
        nil
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        receivedEvents.append(noteEvents)
    }
}
