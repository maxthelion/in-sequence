import XCTest
@testable import SequencerAI

final class MixerMasterOutputTests: XCTestCase {
    func test_masterOutputLayoutUsesFixedColumnAtNormalWidths() {
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 540),
            .fullColumn(width: StudioMixerStripMetrics.masterWidth)
        )
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 900),
            .fullColumn(width: StudioMixerStripMetrics.masterWidth)
        )
    }

    func test_masterOutputLayoutUsesCompactStripBelowBreakpoint() {
        XCTAssertEqual(
            MasterOutputColumnLayout.presentation(for: 539.5),
            .compactStrip(width: 44)
        )
        XCTAssertTrue(MasterOutputColumnLayout.presentation(for: 320).usesCompactOverlay)
    }

    func test_masterOutputInsertsUseMasterBusChainNotDominantScene() {
        let sceneAID = UUID()
        let sceneBID = UUID()
        let sceneA = MasterBusScene(id: sceneAID, name: "Intro", inserts: [.filter()])
        let sceneB = MasterBusScene(id: sceneBID, name: "Break", inserts: [.bitcrusher()])
        var masterBus = MasterBusState(
            scenes: [sceneA, sceneB],
            activeSceneID: sceneAID,
            abSelection: MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneBID, crossfader: 1)
        )

        masterBus.addMasterInsert(.filter())

        XCTAssertEqual(masterBus.masterInserts.count, 1)
        XCTAssertEqual(masterBus.scene(id: sceneAID)?.inserts.count, 1)
        XCTAssertEqual(masterBus.scene(id: sceneBID)?.inserts.count, 1)
    }

    func test_masterOutputGainScaleKeepsUnityNearApprovedFaderThrow() {
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: 1), 2, accuracy: 0.0001)
        XCTAssertEqual(MasterOutputGainScale.gain(forPosition: MasterOutputGainScale.unityPosition), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(MasterOutputGainScale.unityPosition, 0.75)
        XCTAssertLessThan(MasterOutputGainScale.unityPosition, 0.80)
        XCTAssertEqual(MasterOutputGainScale.dbLabel(forGain: 1), "0 dB")
        XCTAssertEqual(MasterOutputGainScale.dbLabel(forGain: 0), "-inf")
    }

    func test_meterScaleAndClipActionReflectTransientDisplayState() {
        let state = MasterMeterDisplayState(
            leftPeakDBFS: -12,
            rightPeakDBFS: -6,
            leftPeakHoldDBFS: -9,
            rightPeakHoldDBFS: -3,
            isClipLatched: true
        )

        XCTAssertGreaterThan(MasterMeterLevelScale.normalized(state.rightPeakDBFS), MasterMeterLevelScale.normalized(state.leftPeakDBFS))
        XCTAssertTrue(state.isClearClipActionable)
        XCTAssertEqual(MasterMeterLevelScale.normalized(MasterMeterDisplayState.silenceDBFS), 0)
        XCTAssertEqual(MasterMeterLevelScale.normalized(3), 1)
        XCTAssertEqual(MasterMeterLevelScale.warningDBFS, -18)
        XCTAssertEqual(MasterMeterLevelScale.dangerDBFS, -1)
        XCTAssertLessThan(MasterMeterLevelScale.normalized(MasterMeterLevelScale.warningDBFS), MasterMeterLevelScale.normalized(MasterMeterLevelScale.dangerDBFS))
    }

    func test_clearClipControlKeepsLegibleFooterSizeAtNormalColumnWidth() {
        XCTAssertGreaterThanOrEqual(MasterOutputClearClipControlMetrics.minWidth, 34)
        XCTAssertGreaterThanOrEqual(MasterOutputClearClipControlMetrics.minHeight, 22)
        XCTAssertLessThanOrEqual(
            MasterOutputClearClipControlMetrics.minWidth,
            MasterOutputColumnLayout.fullColumnWidth * 0.3
        )
    }

    func test_sendDisplayModelMakesZeroAndNonZeroStatesDistinct() {
        XCTAssertEqual(MixerSendDisplayModel.percentLabel(for: 0), "0%")
        XCTAssertEqual(MixerSendDisplayModel.percentLabel(for: 0.375), "38%")
        XCTAssertEqual(MixerSendDisplayModel.percentLabel(for: 4), "100%")
        XCTAssertFalse(MixerSendDisplayModel.isNonZero(0))
        XCTAssertTrue(MixerSendDisplayModel.isNonZero(0.25))
    }

    func test_mixerRoutingDisplayUsesMasterFallbackAndBusName() {
        let busID = UUID()
        var track = StepSequenceTrack.default
        let bus = MixerBus(id: busID, name: "Drums")

        XCTAssertEqual(MixerRoutingDisplayModel.outputTitle(for: track, buses: [bus]), "Master")

        track.outputBusID = busID

        XCTAssertEqual(MixerRoutingDisplayModel.outputTitle(for: track, buses: [bus]), "Drums")
        XCTAssertEqual(MixerRoutingDisplayModel.outputTitle(for: track, buses: []), "Master")
    }

    func test_mixerRoutingDisplayListsAffectedTracksForBusDeleteConfirmation() {
        let busID = UUID()
        var kick = StepSequenceTrack.default
        kick.id = UUID()
        kick.name = "Kick"
        kick.outputBusID = busID
        var lead = StepSequenceTrack.default
        lead.id = UUID()
        lead.name = "Lead"
        var snare = StepSequenceTrack.default
        snare.id = UUID()
        snare.name = "Snare"
        snare.outputBusID = busID

        XCTAssertEqual(
            MixerRoutingDisplayModel.affectedTrackNames(for: busID, tracks: [kick, lead, snare]),
            ["Kick", "Snare"]
        )
    }

    func test_sharedMixerInsertRowsUseNameOnlyGrammarInputs() {
        var masterInsert = MasterBusInsert.filter()
        masterInsert.name = "808 Bus Crunch"
        masterInsert.isEnabled = false

        var bus = MixerBus(name: "808 Bus", inserts: [masterInsert])

        XCTAssertEqual(bus.inserts.map(\.name), ["808 Bus Crunch"])
        XCTAssertFalse(bus.inserts.contains { $0.name.contains("Filter /") })

        bus.inserts[0].isEnabled = true
        XCTAssertTrue(bus.inserts[0].isEnabled)
    }
}
