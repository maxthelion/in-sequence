import AVFoundation
import XCTest
@testable import SequencerAI

final class EngineControllerPhraseNavigationTests: XCTestCase {
    func test_startInitializesCurrentAndBasisFromSelectedPhrase() throws {
        let fixture = makePhraseNavigationFixture(selectedPhraseIndex: 1)

        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[1].id)

        fixture.controller.stop()
    }

    func test_queueSetsQueuedAndBasisWithoutChangingCurrentOrSnapshotSelection() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_queueReplacementKeepsCurrentPhraseAndUsesLatestQueuedTarget() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[2].id))

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_immediateSwitchClearsQueueAndStartsTargetAtLocalStepZero() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        fixture.controller.processTick(tickIndex: 0, now: 0)
        fixture.sink.reset()
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[2].id))

        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.sink.playedPitches, [72])
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_queuedPhrasePromotesAtCurrentPhraseCycleBoundary() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.queuedPhraseID, fixture.phrases[1].id)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)

        fixture.sink.reset()
        fixture.controller.processTick(tickIndex: 2, now: 0.2)
        XCTAssertEqual(fixture.sink.playedPitches, [72])

        fixture.controller.stop()
    }

    func test_playbackStartAppliesCurrentPhraseSceneStateToMasterBus() throws {
        let scenes = phraseNavigationScenes()
        let fixture = makePhraseNavigationFixture(
            masterBus: scenes.masterBus
        ) { phrases in
            phrases[0].sceneState = PhraseSceneState(
                sceneAID: scenes.a.id,
                sceneBID: scenes.b.id,
                crossfader: 0.31
            )
        }

        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(
            fixture.controller.masterBusState.abSelection,
            MasterBusABSelection(sceneAID: scenes.a.id, sceneBID: scenes.b.id, crossfader: 0.31)
        )

        fixture.controller.stop()
    }

    func test_queuedPhraseBoundaryAppliesNextPhraseSceneStateToMasterBus() throws {
        let scenes = phraseNavigationScenes()
        let fixture = makePhraseNavigationFixture(
            masterBus: scenes.masterBus
        ) { phrases in
            phrases[0].sceneState = PhraseSceneState(
                sceneAID: scenes.a.id,
                sceneBID: scenes.b.id,
                crossfader: 0.15
            )
            phrases[1].sceneState = PhraseSceneState(
                sceneAID: scenes.b.id,
                sceneBID: scenes.c.id,
                crossfader: 0.82
            )
        }
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(
            fixture.controller.masterBusState.abSelection,
            MasterBusABSelection(sceneAID: scenes.a.id, sceneBID: scenes.b.id, crossfader: 0.15)
        )

        fixture.controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(
            fixture.controller.masterBusState.abSelection,
            MasterBusABSelection(sceneAID: scenes.b.id, sceneBID: scenes.c.id, crossfader: 0.82)
        )

        fixture.controller.stop()
    }

    func test_repeatCountOneAdvancesToNextPhraseAtFirstCycleBoundary() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 1
        }
        startEngineForManualTicks(fixture.controller)

        fixture.controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.sink.reset()
        fixture.controller.processTick(tickIndex: 2, now: 0.2)
        XCTAssertEqual(fixture.sink.playedPitches, [72])

        fixture.controller.stop()
    }

    func test_finiteRepeatCountHigherThanOneAdvancesOnlyAfterRequestedCycles() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 4
        }
        startEngineForManualTicks(fixture.controller)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 1)

        fixture.controller.processTick(tickIndex: 3, now: 0.3)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 2)
        assertPhraseButtonPlayingBadge(in: fixture, isVisibleOnlyFor: fixture.phrases[0].id)

        fixture.controller.processTick(tickIndex: 5, now: 0.5)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 3)

        fixture.controller.processTick(tickIndex: 7, now: 0.7)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_repeatCountZeroStaysOnCurrentPhraseWithoutAutomaticAdvancement() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 0
        }
        startEngineForManualTicks(fixture.controller)

        fixture.controller.processTick(tickIndex: 3, now: 0.3)
        assertPhraseButtonPlayingBadge(in: fixture, isVisibleOnlyFor: fixture.phrases[0].id)

        for tickIndex in 4...7 {
            fixture.controller.processTick(tickIndex: UInt64(tickIndex), now: TimeInterval(tickIndex) / 10)
        }

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_loopEnabledStaysOnCurrentPhraseEvenWithFiniteRepeatCount() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 1
            phrases[0].loopEnabled = true
        }
        startEngineForManualTicks(fixture.controller)

        processTicks(fixture.controller, through: 7)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_queuedPhrasePromotesAtBoundaryEvenWhenCurrentPhraseLoops() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 0
            phrases[0].loopEnabled = true
        }
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        fixture.controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[1].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)
        assertPhraseButtonPlayingBadge(in: fixture, isVisibleOnlyFor: fixture.phrases[1].id)

        fixture.controller.stop()
    }

    func test_finalFinitePhraseWrapsToFirstPhrase() throws {
        let fixture = makePhraseNavigationFixture(selectedPhraseIndex: 2) { phrases in
            phrases[2].repeatCount = 1
        }
        startEngineForManualTicks(fixture.controller)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_onePhraseDocumentFiniteAdvancementResolvesBackAndResetsProgress() throws {
        let fixture = makePhraseNavigationFixture(phraseCount: 1) { phrases in
            phrases[0].repeatCount = 2
        }
        startEngineForManualTicks(fixture.controller)

        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 1)

        fixture.controller.processTick(tickIndex: 3, now: 0.3)
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_stopClearsQueuedPhraseState() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))

        fixture.controller.stop()

        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
    }

    func test_queuePhraseIsUnavailableWhileStoppedAndDoesNotAccumulateHiddenQueue() throws {
        let fixture = makePhraseNavigationFixture()

        XCTAssertFalse(fixture.controller.isRunning)
        XCTAssertFalse(fixture.controller.queuePhrase(fixture.phrases[1].id))

        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[0].id)
    }

    func test_stopClearsQueueAndRestartUsesStoppedSelectedPhrase() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        fixture.controller.stop()

        var updatedProject = fixture.project
        updatedProject.selectedPhraseID = fixture.phrases[2].id
        fixture.controller.apply(documentModel: updatedProject)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)

        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)

        fixture.controller.stop()
    }

    func test_applyReconcilesInvalidCurrentBasisAndQueuedPhrases() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))
        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))

        var updatedProject = fixture.project
        updatedProject.removePhrase(id: fixture.phrases[1].id)
        fixture.controller.apply(documentModel: updatedProject)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.currentPhraseCompletedCyclesForTesting, 0)

        fixture.controller.stop()
    }

    func test_playbackSnapshotInstallClearsInvalidQueuedPhraseAndKeepsValidCurrent() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.queuePhrase(fixture.phrases[1].id))

        var updatedProject = fixture.project
        updatedProject.removePhrase(id: fixture.phrases[1].id)
        fixture.controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: updatedProject))

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)

        fixture.controller.stop()
    }

    func test_playbackSnapshotInstallReconcilesInvalidCurrentToSelectedFallback() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))

        var updatedProject = fixture.project
        updatedProject.removePhrase(id: fixture.phrases[1].id)
        fixture.sink.reset()
        fixture.controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: updatedProject))
        fixture.controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.sink.playedPitches, [84])

        fixture.controller.stop()
    }

    func test_startReinitializesFromSnapshotSelectedPhraseAfterStoppedSelectionChange() throws {
        let fixture = makePhraseNavigationFixture()
        startEngineForManualTicks(fixture.controller)
        XCTAssertTrue(fixture.controller.switchPhraseNow(fixture.phrases[1].id))
        fixture.controller.stop()

        var updatedProject = fixture.project
        updatedProject.selectedPhraseID = fixture.phrases[2].id
        fixture.controller.apply(documentModel: updatedProject)
        startEngineForManualTicks(fixture.controller)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[2].id)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[2].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.selectedPhraseID, fixture.phrases[2].id)

        fixture.controller.stop()
    }

    func test_prepareTickDoesNotRepublishUnchangedPhraseNavigationState() throws {
        let fixture = makePhraseNavigationFixture { phrases in
            phrases[0].repeatCount = 0
        }
        startEngineForManualTicks(fixture.controller)
        let publicationCount = fixture.controller.phraseNavigationPublicationCountForTesting

        fixture.controller.processTick(tickIndex: 0, now: 0)
        fixture.controller.processTick(tickIndex: 1, now: 0.1)
        fixture.controller.processTick(tickIndex: 2, now: 0.2)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[0].id)
        XCTAssertNil(fixture.controller.queuedPhraseID)
        XCTAssertEqual(fixture.controller.basisPhraseID, fixture.phrases[0].id)
        XCTAssertEqual(fixture.controller.phraseNavigationPublicationCountForTesting, publicationCount)

        fixture.controller.stop()
    }

    func test_tickFallsBackToSnapshotSelectedPhraseWhenLiveCurrentIsUnset() throws {
        let fixture = makePhraseNavigationFixture(selectedPhraseIndex: 1)

        fixture.controller.processTick(tickIndex: 0, now: 0)

        XCTAssertEqual(fixture.sink.playedPitches, [72])
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.phrases[1].id)
    }

    func test_playbackSnapshotDoesNotCarryPhraseNavigationState() throws {
        let snapshot = SequencerSnapshotCompiler.compile(project: makePhraseNavigationFixture().project)
        let childNames = Set(Mirror(reflecting: snapshot).children.compactMap(\.label))

        XCTAssertFalse(childNames.contains("currentPhraseID"))
        XCTAssertFalse(childNames.contains("queuedPhraseID"))
        XCTAssertFalse(childNames.contains("basisPhraseID"))
        XCTAssertFalse(childNames.contains("phraseCycleStartTick"))
    }

    func test_stepOrderPendingToggleAppliesBeforeFirstBoundaryStepIsDispatched() throws {
        let stepOrderMap: [UInt8] = [3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0]
        let fixture = makeStepOrderBoundaryFixture(isEnabled: false, stepOrderMap: stepOrderMap)
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.requestStepOrderEnabled(
            true,
            phraseID: fixture.phraseID,
            enabledMapValues: stepOrderMap
        ))
        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.phraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.phraseID)?.stepOrderMap)

        for tickIndex in 0..<15 {
            fixture.controller.processTick(tickIndex: UInt64(tickIndex), now: TimeInterval(tickIndex) / 10)
        }

        XCTAssertEqual(fixture.sink.playedPitches, Array(60...74))
        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.phraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.phraseID)?.stepOrderMap)

        fixture.controller.processTick(tickIndex: 15, now: 1.5)

        XCTAssertEqual(fixture.sink.playedPitches, Array(60...75))
        XCTAssertNil(fixture.controller.stepOrderPendingToggle)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.phraseID)?.stepOrderMap, stepOrderMap)

        fixture.controller.processTick(tickIndex: 16, now: 1.6)

        XCTAssertEqual(fixture.sink.playedPitches.last, 63)

        fixture.controller.stop()
    }

    func test_stepOrderPendingToggleWaitsForRequestedPhraseBoundary() throws {
        let stepOrderMap: [UInt8] = [3, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0]
        let fixture = makePhraseSpecificStepOrderBoundaryFixture(stepOrderMap: stepOrderMap)
        startEngineForManualTicks(fixture.controller)

        XCTAssertTrue(fixture.controller.requestStepOrderEnabled(
            true,
            phraseID: fixture.pendingPhraseID,
            enabledMapValues: stepOrderMap
        ))
        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.currentPhraseID)
        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.pendingPhraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.pendingPhraseID)?.stepOrderMap)

        for tickIndex in 0..<15 {
            fixture.controller.processTick(tickIndex: UInt64(tickIndex), now: TimeInterval(tickIndex) / 10)
        }

        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.pendingPhraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.pendingPhraseID)?.stepOrderMap)

        fixture.controller.processTick(tickIndex: 15, now: 1.5)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.currentPhraseID)
        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.pendingPhraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.pendingPhraseID)?.stepOrderMap)

        XCTAssertTrue(fixture.controller.queuePhrase(fixture.pendingPhraseID))
        for tickIndex in 16..<31 {
            fixture.controller.processTick(tickIndex: UInt64(tickIndex), now: TimeInterval(tickIndex) / 10)
        }

        XCTAssertEqual(fixture.controller.stepOrderPendingToggle, StepOrderPendingToggleRequest(phraseID: fixture.pendingPhraseID, requestedEnabled: true))
        XCTAssertNil(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.pendingPhraseID)?.stepOrderMap)

        fixture.controller.processTick(tickIndex: 31, now: 3.1)

        XCTAssertEqual(fixture.controller.currentPhraseID, fixture.pendingPhraseID)
        XCTAssertNil(fixture.controller.stepOrderPendingToggle)
        XCTAssertEqual(fixture.controller.currentPlaybackSnapshotForTesting.phraseBuffer(for: fixture.pendingPhraseID)?.stepOrderMap, stepOrderMap)

        fixture.controller.stop()
    }
}

private struct PhraseNavigationFixture {
    let controller: EngineController
    let sink: PhraseNavigationAudioSink
    let project: Project
    let phrases: [PhraseModel]
}

private struct StepOrderBoundaryFixture {
    let controller: EngineController
    let sink: PhraseNavigationAudioSink
    let phraseID: UUID
}

private struct PhraseSpecificStepOrderBoundaryFixture {
    let controller: EngineController
    let sink: PhraseNavigationAudioSink
    let currentPhraseID: UUID
    let pendingPhraseID: UUID
}

private func makePhraseNavigationFixture(
    selectedPhraseIndex: Int = 0,
    phraseCount: Int = 3,
    masterBus: MasterBusState = .default,
    configurePhrases: (inout [PhraseModel]) -> Void = { _ in }
) -> PhraseNavigationFixture {
    let sink = PhraseNavigationAudioSink()
    let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink, stepsPerBar: 2)
    let trackID = UUID(uuidString: "11111111-aaaa-bbbb-cccc-111111111111")!
    let generatorAID = UUID(uuidString: "22222222-aaaa-bbbb-cccc-222222222222")!
    let generatorBID = UUID(uuidString: "33333333-aaaa-bbbb-cccc-333333333333")!
    let generatorCID = UUID(uuidString: "44444444-aaaa-bbbb-cccc-444444444444")!
    let track = StepSequenceTrack(
        id: trackID,
        name: "Phrase Nav Track",
        pitches: [60],
        stepPattern: [true, true],
        stepAccents: [false, false],
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 1
    )
    let generators = [
        phraseNavigationGenerator(id: generatorAID, name: "A", pattern: [true, true], pitch: 60),
        phraseNavigationGenerator(id: generatorBID, name: "B", pattern: [true, false], pitch: 72),
        phraseNavigationGenerator(id: generatorCID, name: "C", pattern: [true, false], pitch: 84),
    ]
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    var phrases = Array([
        phraseNavigationPhrase(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!, name: "Phrase A", slotIndex: 0, track: track, layers: layers),
        phraseNavigationPhrase(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2")!, name: "Phrase B", slotIndex: 1, track: track, layers: layers),
        phraseNavigationPhrase(id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc3")!, name: "Phrase C", slotIndex: 2, track: track, layers: layers),
    ].prefix(min(max(1, phraseCount), 3)))
    configurePhrases(&phrases)
    let patternBank = TrackPatternBank(
        trackID: track.id,
        slots: [
            TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorAID)),
            TrackPatternSlot(slotIndex: 1, sourceRef: .generator(generatorBID)),
            TrackPatternSlot(slotIndex: 2, sourceRef: .generator(generatorCID)),
        ]
    )
    let selectedPhraseID = phrases[min(max(0, selectedPhraseIndex), phrases.count - 1)].id
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: generators,
        clipPool: [],
        layers: layers,
        routes: [],
        masterBus: masterBus,
        patternBanks: [patternBank],
        selectedTrackID: track.id,
        phrases: phrases,
        selectedPhraseID: selectedPhraseID
    )
    controller.apply(documentModel: project)
    return PhraseNavigationFixture(controller: controller, sink: sink, project: project, phrases: phrases)
}

private func makeStepOrderBoundaryFixture(
    isEnabled: Bool,
    stepOrderMap: [UInt8]
) -> StepOrderBoundaryFixture {
    let sink = PhraseNavigationAudioSink()
    let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink, stepsPerBar: 16)
    let trackID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let mapID = UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!
    let track = StepSequenceTrack(
        id: trackID,
        name: "Step Order Boundary Track",
        pitches: [60],
        stepPattern: Array(repeating: true, count: 16),
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 1
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    var phrase = PhraseModel.default(
        tracks: [track],
        layers: layers,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: []
    )
    phrase.lengthBars = 1
    phrase.stepsPerBar = 16
    phrase.stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: isEnabled)

    var clipPool: [ClipPoolEntry] = []
    var slots: [TrackPatternSlot] = []
    for step in 0..<16 {
        let clipID = UUID(uuidString: String(format: "bbbbbbbb-%04d-0000-0000-000000000000", step))!
        clipPool.append(
            ClipPoolEntry(
                id: clipID,
                name: "Source Step \(step)",
                trackType: track.trackType,
                content: .noteGrid(
                    lengthSteps: 16,
                    steps: (0..<16).map { clipStep in
                        guard clipStep == step else { return .empty }
                        return ClipStep(
                            main: ClipLane(
                                chance: 1,
                                notes: [
                                    ClipStepNote(
                                        pitch: 60 + step,
                                        velocity: 100,
                                        lengthSteps: 1
                                    )
                                ]
                            ),
                            fill: nil
                        )
                    }
                )
            )
        )
        slots.append(TrackPatternSlot(slotIndex: step, sourceRef: .clip(clipID)))
    }
    phrase.setCell(
        .steps((0..<16).map { .index($0) }),
        for: "pattern",
        trackID: trackID
    )

    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: clipPool,
        layers: layers,
        routes: [],
        patternBanks: [TrackPatternBank(trackID: trackID, slots: slots)],
        stepOrderMaps: [StepOrderMap(id: mapID, name: "Boundary", values: stepOrderMap)],
        selectedTrackID: trackID,
        phrases: [phrase],
        selectedPhraseID: phrase.id
    )
    controller.apply(documentModel: project)
    return StepOrderBoundaryFixture(controller: controller, sink: sink, phraseID: phrase.id)
}

private func makePhraseSpecificStepOrderBoundaryFixture(
    stepOrderMap: [UInt8]
) -> PhraseSpecificStepOrderBoundaryFixture {
    let sink = PhraseNavigationAudioSink()
    let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink, stepsPerBar: 16)
    let trackID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    let mapID = UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!
    let currentPhraseID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!
    let pendingPhraseID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2")!
    let track = StepSequenceTrack(
        id: trackID,
        name: "Phrase-Specific Step Order Track",
        pitches: [60],
        stepPattern: Array(repeating: true, count: 16),
        destination: .auInstrument(componentID: AudioInstrumentChoice.builtInSynth.audioComponentID, stateBlob: nil),
        velocity: 100,
        gateLength: 1
    )
    let layers = PhraseLayerDefinition.defaultSet(for: [track])
    var currentPhrase = stepOrderBoundaryPhrase(
        id: currentPhraseID,
        name: "Current",
        track: track,
        layers: layers,
        mapID: mapID,
        isEnabled: false
    )
    currentPhrase.loopEnabled = true
    let pendingPhrase = stepOrderBoundaryPhrase(
        id: pendingPhraseID,
        name: "Pending",
        track: track,
        layers: layers,
        mapID: mapID,
        isEnabled: false
    )
    let (clipPool, slots) = stepOrderBoundaryClipPoolAndSlots(track: track)
    let project = Project(
        version: 1,
        tracks: [track],
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: clipPool,
        layers: layers,
        routes: [],
        patternBanks: [TrackPatternBank(trackID: trackID, slots: slots)],
        stepOrderMaps: [StepOrderMap(id: mapID, name: "Boundary", values: stepOrderMap)],
        selectedTrackID: trackID,
        phrases: [currentPhrase, pendingPhrase],
        selectedPhraseID: currentPhraseID
    )
    controller.apply(documentModel: project)
    return PhraseSpecificStepOrderBoundaryFixture(
        controller: controller,
        sink: sink,
        currentPhraseID: currentPhraseID,
        pendingPhraseID: pendingPhraseID
    )
}

private func stepOrderBoundaryPhrase(
    id: UUID,
    name: String,
    track: StepSequenceTrack,
    layers: [PhraseLayerDefinition],
    mapID: StepOrderMapID,
    isEnabled: Bool
) -> PhraseModel {
    var phrase = PhraseModel.default(
        tracks: [track],
        layers: layers,
        generatorPool: GeneratorPoolEntry.defaultPool,
        clipPool: []
    )
    phrase.id = id
    phrase.name = name
    phrase.lengthBars = 1
    phrase.stepsPerBar = 16
    phrase.stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: isEnabled)
    phrase.setCell(
        .steps((0..<16).map { .index($0) }),
        for: "pattern",
        trackID: track.id
    )
    return phrase
}

private func stepOrderBoundaryClipPoolAndSlots(track: StepSequenceTrack) -> ([ClipPoolEntry], [TrackPatternSlot]) {
    var clipPool: [ClipPoolEntry] = []
    var slots: [TrackPatternSlot] = []
    for step in 0..<16 {
        let clipID = UUID(uuidString: String(format: "bbbbbbbb-%04d-0000-0000-000000000000", step))!
        clipPool.append(
            ClipPoolEntry(
                id: clipID,
                name: "Source Step \(step)",
                trackType: track.trackType,
                content: .noteGrid(
                    lengthSteps: 16,
                    steps: (0..<16).map { clipStep in
                        guard clipStep == step else { return .empty }
                        return ClipStep(
                            main: ClipLane(
                                chance: 1,
                                notes: [
                                    ClipStepNote(
                                        pitch: 60 + step,
                                        velocity: 100,
                                        lengthSteps: 1
                                    )
                                ]
                            ),
                            fill: nil
                        )
                    }
                )
            )
        )
        slots.append(TrackPatternSlot(slotIndex: step, sourceRef: .clip(clipID)))
    }
    return (clipPool, slots)
}

private func startEngineForManualTicks(_ controller: EngineController) {
    controller.start()
    controller.clock.stop()
}

private func processTicks(_ controller: EngineController, through finalTickIndex: UInt64) {
    for tickIndex in 0...finalTickIndex {
        controller.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) / 10)
    }
}

private func assertPhraseButtonPlayingBadge(
    in fixture: PhraseNavigationFixture,
    isVisibleOnlyFor expectedPhraseID: UUID,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for phrase in fixture.phrases {
        XCTAssertEqual(
            PhraseButtonControlPresentation.isPlayingBadgeVisible(
                phraseID: phrase.id,
                engineIsRunning: fixture.controller.isRunning,
                currentPhraseID: fixture.controller.currentPhraseID
            ),
            phrase.id == expectedPhraseID,
            "Phrase button playing badge should follow EngineController.currentPhraseID for \(phrase.name)",
            file: file,
            line: line
        )
    }
}

private func phraseNavigationPhrase(
    id: UUID,
    name: String,
    slotIndex: Int,
    track: StepSequenceTrack,
    layers: [PhraseLayerDefinition]
) -> PhraseModel {
    var phrase = PhraseModel.default(tracks: [track], layers: layers)
    phrase.id = id
    phrase.name = name
    phrase.lengthBars = 1
    phrase.stepsPerBar = 2
    phrase.setPatternIndex(slotIndex, for: track.id, layers: layers)
    return phrase.synced(with: [track], layers: layers)
}

private func phraseNavigationGenerator(
    id: UUID,
    name: String,
    pattern: [Bool],
    pitch: Int
) -> GeneratorPoolEntry {
    GeneratorPoolEntry(
        id: id,
        name: name,
        trackType: .monoMelodic,
        kind: .monoGenerator,
        params: .mono(
            trigger: .native(euclideanAlgo(matching: pattern)),
            pitch: .native(.manual(pitches: [pitch], pickMode: .sequential)),
            shape: NoteShape(velocity: 100, gateLength: 1, accent: false)
        )
    )
}

private func phraseNavigationScenes() -> (
    a: MasterBusScene,
    b: MasterBusScene,
    c: MasterBusScene,
    masterBus: MasterBusState
) {
    let sceneA = MasterBusScene(id: UUID(uuidString: "aaaaaaaa-1111-2222-3333-000000000001")!, name: "Scene A")
    let sceneB = MasterBusScene(id: UUID(uuidString: "bbbbbbbb-1111-2222-3333-000000000002")!, name: "Scene B")
    let sceneC = MasterBusScene(id: UUID(uuidString: "cccccccc-1111-2222-3333-000000000003")!, name: "Scene C")
    return (
        sceneA,
        sceneB,
        sceneC,
        MasterBusState(
            scenes: [sceneA, sceneB, sceneC],
            activeSceneID: sceneA.id,
            abSelection: MasterBusABSelection(sceneAID: sceneA.id, sceneBID: sceneB.id, crossfader: 0)
        )
    )
}

private final class PhraseNavigationAudioSink: TrackPlaybackSink {
    let displayName = "Phrase Navigation Sink"
    var isAvailable = true
    let availableInstruments = [AudioInstrumentChoice.builtInSynth]
    var selectedInstrument: AudioInstrumentChoice = .builtInSynth
    var currentAudioUnit: AVAudioUnit?
    private(set) var playedEvents: [[NoteEvent]] = []

    var playedPitches: [UInt8] {
        playedEvents.flatMap { $0 }.map(\.pitch)
    }

    func prepareIfNeeded() {}
    func startIfNeeded() {}
    func stop() {}
    func shutdown() {}
    func setMix(_ mix: TrackMixSettings) {}
    func setDestination(_ destination: Destination) {}
    func selectInstrument(_ choice: AudioInstrumentChoice) {
        selectedInstrument = choice
    }
    func captureStateBlob() throws -> Data? { nil }
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        playedEvents.append(noteEvents)
    }
    func reset() {
        playedEvents.removeAll()
    }
}
