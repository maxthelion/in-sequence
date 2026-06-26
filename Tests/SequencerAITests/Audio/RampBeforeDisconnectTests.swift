import AVFoundation
import XCTest
@testable import SequencerAI

/// Coverage for the ramp-before-disconnect click fix
/// (docs/bugs/20260625-routing-hard-disconnect-clicks): a SOUNDING track's
/// output must never be hard-disconnected mid-signal. The live single-track
/// edit paths ramp the track's per-track gain stage to silence, splice the
/// graph on silence, then ramp back.
final class RampBeforeDisconnectTests: XCTestCase {
    /// Engine stopped → no ramp path; the reconnect is synchronous (setup /
    /// offline-render / test behaviour is unchanged).
    @MainActor
    func test_reconnect_engineStopped_takesSynchronousPath_noRamp() throws {
        let graph = MainAudioGraph()
        let source = AVAudioMixerNode()
        graph.attach(source)
        source.outputVolume = 0.8 // set after attach (attach resets to default 1.0)
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])

        graph.connectTrackOutput(source, to: nil)
        // Engine is not running, so even a sounding mixer node takes the plain
        // synchronous reconnect — the destination is updated immediately and the
        // ramp path is never entered.
        XCTAssertEqual(graph.rampedReconnectCountForTesting, 0)
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === graph.preMasterMixer)

        graph.connectTrackOutput(source, to: busID)
        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer)
        XCTAssertEqual(graph.rampedReconnectCountForTesting, 0)
    }

    /// Engine stopped AND a silent (muted / level-0) mixer source still takes
    /// the synchronous path: a hard disconnect on silence does not click, and
    /// ramping a silent node back up would itself click.
    @MainActor
    func test_reconnect_silentSource_takesSynchronousPath_noRamp() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        try graph.start()

        let source = AVAudioMixerNode()
        graph.attach(source)
        source.outputVolume = 0 // muted / silent (set after attach; attach resets to 1.0)
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])

        graph.connectTrackOutput(source, to: busID)
        // Silent source → no ramp, immediate reconnect.
        XCTAssertEqual(graph.rampedReconnectCountForTesting, 0)
        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer)

        graph.stop()
    }

    /// Engine running + sounding mixer-node source → the ramp-to-silence path is
    /// taken (count increments), and after the ~12 ms down-ramp the deferred
    /// reconnect lands on the new destination and the gain stage ramps back to
    /// its pre-edit level (no residual silence).
    @MainActor
    func test_reconnect_runningSoundingSource_ramps_thenReconnectsAndRestoresLevel() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let source = AVAudioMixerNode()
        graph.attach(source)
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])

        // Establish the initial routing (to master) while STOPPED — synchronous,
        // no ramp — so the live edit under test is a single, deterministic op.
        graph.connectTrackOutput(source, to: nil)
        source.outputVolume = 0.8 // sounding (set after the stopped setup)
        XCTAssertEqual(graph.rampedReconnectCountForTesting, 0)

        // Now go live and do ONE bus reassign of the sounding track.
        try graph.start()
        let rampedBefore = graph.rampedReconnectCountForTesting
        graph.connectTrackOutput(source, to: busID)
        XCTAssertEqual(
            graph.rampedReconnectCountForTesting, rampedBefore + 1,
            "a live bus reassign of a sounding track must take the ramp-to-silence path"
        )

        // The reconnect is deferred until the down-ramp reaches silence (~12 ms),
        // so spin the runloop until the destination lands on the bus.
        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        let reconnected = expectation(description: "deferred reconnect lands on bus")
        let deadline = Date().addingTimeInterval(2.0)
        func poll() {
            if graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer {
                reconnected.fulfill()
                return
            }
            if Date() > deadline {
                return // let the wait fail with a clear message
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() }
        }
        poll()
        wait(for: [reconnected], timeout: 3.0)
        XCTAssertTrue(graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer)

        // After the up-ramp settles, the gain stage is restored to its pre-edit
        // level — the dip to silence was transient, not a lasting mute.
        let restored = expectation(description: "gain stage ramps back to level")
        let levelDeadline = Date().addingTimeInterval(2.0)
        func pollLevel() {
            if abs(source.outputVolume - 0.8) < 0.01 {
                restored.fulfill()
                return
            }
            if Date() > levelDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { pollLevel() }
        }
        pollLevel()
        wait(for: [restored], timeout: 3.0)
        XCTAssertEqual(source.outputVolume, 0.8, accuracy: 0.02)

        graph.stop()
    }

    /// Regression for the intermittent route-to-master / drum-part-add silence
    /// (docs/bugs/20260626-route-to-master-intermittent-silence): when two
    /// ramp-to-silence cycles overlap on the SAME gain stage (a second routing
    /// splice arriving while the first's ~12 ms dip is still in flight), the
    /// second cycle used to capture the first's MID-DIP `outputVolume` as its
    /// "restore" level and ramp back to that near-zero transient — leaving the
    /// track stuck silent. The fix captures the restore level from the ramp's
    /// recorded SETTLED target, not the live volume, so the node always returns
    /// to its true rest level regardless of interleaving.
    @MainActor
    func test_overlappingRoutingSplices_restoreToTrueLevel_notMidDipTransient() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        // Send buses must exist so the track routes its dry signal THROUGH its
        // persistent fanout — the exact gain stage the route-to-master rebuild
        // ramps to silence.
        graph.installSendBuses([.sendA, .sendB])
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "FX")])

        // A non-mixer source (track filter terminal) → its gain stage is the
        // fanout, not the source itself.
        let source = SamplerFilterNode().avNode
        graph.attach(source)

        // First splice while STOPPED — synchronous; this creates the persistent
        // fanout (rest level 1.0) and records its settled target.
        graph.connectTrackOutput(source, to: nil)
        let fanout = try XCTUnwrap(graph.trackGainStageForTesting(source))
        XCTAssertEqual(fanout.outputVolume, 1.0, accuracy: 0.001)

        // Go live so the splices below take the ramp-to-silence (dip) path.
        try graph.start()

        // Splice #1 kicks a ~12 ms down-ramp dip on the fanout (on MixerGainRamp's
        // background queue). Wait until the dip is genuinely IN FLIGHT (the live
        // outputVolume has fallen well below the rest level) — this is the exact
        // window in which a second routing splice arrives in the real bug.
        graph.connectTrackOutput(source, to: busID)
        let dipping = expectation(description: "fanout dip is in flight (volume below rest level)")
        let dipDeadline = Date().addingTimeInterval(1.0)
        func awaitDip() {
            if fanout.outputVolume < 0.7 {
                dipping.fulfill()
                return
            }
            if Date() > dipDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { awaitDip() }
        }
        awaitDip()
        wait(for: [dipping], timeout: 2.0)

        // Splice #2 arrives mid-dip. With the OLD code it captured the fanout's
        // mid-dip outputVolume (< 0.7) as its restore level and ramped "back" to
        // that transient — leaving the track quiet/silent. With the fix it reads
        // the recorded SETTLED level (1.0) instead.
        graph.connectTrackOutput(source, to: nil)

        // After both dips and the up-ramp settle, the fanout must be back at its
        // true rest level (1.0), not stuck at a mid-dip transient.
        let restored = expectation(description: "fanout restores to rest level after overlapping splices")
        let deadline = Date().addingTimeInterval(3.0)
        func poll() {
            if fanout.outputVolume > 0.95 {
                restored.fulfill()
                return
            }
            if Date() > deadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { poll() }
        }
        poll()
        wait(for: [restored], timeout: 4.0)
        XCTAssertGreaterThan(
            fanout.outputVolume, 0.95,
            "overlapping routing splices must restore the gain stage to its true rest level, not a mid-dip transient"
        )

        graph.stop()
    }

    /// A SOUNDING sample track's teardown (`removeTrack`) must ramp its output
    /// chokepoint to silence BEFORE detaching the node — never hard-cut a
    /// sounding node (Hard Rule 5). Regression for the 2026-06-26 adversarial
    /// review finding that `SamplePlaybackEngine` sample-track teardown skipped
    /// the ramp the rest of the graph uses, so removing a mid-decay drum part
    /// clicked. The dictionary removal stays synchronous (engine-truth readback
    /// drops immediately); only the physical detach is deferred behind the fade.
    @MainActor
    func test_removeTrack_soundingSampleTrack_rampsChokepointToSilenceBeforeDetach() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        try engine.start()
        defer { engine.stop() }

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        // Make the track's output chokepoint sounding (a hard-cut here would click).
        let chokepoint = try XCTUnwrap(engine.trackOutputChokepointNodeForTesting(trackID: trackID))
        chokepoint.outputVolume = 0.8

        let rampsBefore = engine.sampleTeardownRampCountForTesting
        engine.removeTrack(trackID: trackID)

        // The teardown took the ramp-to-silence path, not a hard-cut.
        XCTAssertEqual(
            engine.sampleTeardownRampCountForTesting, rampsBefore + 1,
            "removing a sounding sample track must ramp the chokepoint to silence, not hard-cut"
        )
        // Dictionary removal is synchronous — engine-truth readback drops at once.
        XCTAssertNil(engine.trackOutputGainForTesting(trackID: trackID))
        XCTAssertFalse(engine.preparedTrackIDs.contains(trackID))

        // The chokepoint fades to silence before the deferred (~12 ms) detach.
        let faded = expectation(description: "chokepoint ramps to silence")
        let deadline = Date().addingTimeInterval(2.0)
        func poll() {
            if chokepoint.outputVolume <= 0.001 {
                faded.fulfill()
                return
            }
            if Date() > deadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { poll() }
        }
        poll()
        wait(for: [faded], timeout: 3.0)
        XCTAssertEqual(chokepoint.outputVolume, 0, accuracy: 0.001)
    }

    /// Route-switch CLICK fix (docs/bugs/20260626-route-switch-teardown-hard-cut
    /// and docs/bugs/20260626-route-to-bus-click): re-routing a SOUNDING sample
    /// track between a bus and master must ramp the OUTGOING route's chokepoint
    /// to silence BEFORE the hard disconnect (Hard Rule 5), not hard-cut it.
    ///
    /// This is the deterministic complement to the routing-stress rig's coarse
    /// CLICK metric (which did not catch this click). It asserts:
    /// 1. the outgoing chokepoint took the ramp-to-silence (crossfade) path
    ///    rather than a hard-cut (crossfade count increments + it fades to 0);
    /// 2. NO REGRESSION TO SILENCE — after the switch settles the track is on
    ///    its new destination AND its NEW chokepoint is restored to a sounding
    ///    level (the route-to-master-silence regression the naïve defer caused).
    @MainActor
    func test_routeSwitch_busToMaster_soundingTrack_crossfades_notHardCut_andStaysAudible() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let busID = UUID()
        graph.installSendBuses([.sendA, .sendB])
        graph.installMixerBuses([MixerBus(id: busID, name: "FX")])
        let engine = SamplePlaybackEngine(audioGraph: graph)
        try engine.start()
        defer { engine.stop() }

        let trackID = UUID()
        // Route the track to the bus and set a sounding fader level so the
        // outgoing (bus) chokepoint is mid-signal when we switch.
        engine.setTrackOutputBus(trackID: trackID, busID: busID)
        engine.setTrackMix(trackID: trackID, level: 0.8, pan: 0)
        let busChokepoint = try XCTUnwrap(engine.busTrackSumMixerForTesting(trackID: trackID))
        busChokepoint.outputVolume = 0.8 // ensure sounding regardless of ramp timing

        // Switch back to master — the route-switch under test.
        let crossfadesBefore = engine.sampleRouteCrossfadeCountForTesting
        engine.setTrackOutputBus(trackID: trackID, busID: nil)
        XCTAssertEqual(
            engine.sampleRouteCrossfadeCountForTesting, crossfadesBefore + 1,
            "a bus→master switch of a sounding track must ramp the outgoing chokepoint to silence, not hard-cut"
        )

        // The OUTGOING bus chokepoint fades to silence before its deferred teardown.
        let faded = expectation(description: "outgoing bus chokepoint fades to silence")
        let fadeDeadline = Date().addingTimeInterval(2.0)
        func pollFade() {
            if busChokepoint.outputVolume <= 0.001 {
                faded.fulfill()
                return
            }
            if Date() > fadeDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { pollFade() }
        }
        pollFade()
        wait(for: [faded], timeout: 3.0)

        // NO REGRESSION: after the deferred teardown→rebuild runs, the track is
        // MASTER-routed (no bus pool) and its new chokepoint is restored to a
        // sounding level — not stuck silent (the prior naïve-defer failure).
        let settled = expectation(description: "track re-routes to master and stays audible")
        let settleDeadline = Date().addingTimeInterval(3.0)
        func pollSettled() {
            if engine.busTrackSumMixerForTesting(trackID: trackID) == nil,
               let chokepoint = engine.trackOutputChokepointNodeForTesting(trackID: trackID),
               chokepoint.outputVolume > 0.5 {
                settled.fulfill()
                return
            }
            if Date() > settleDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { pollSettled() }
        }
        pollSettled()
        wait(for: [settled], timeout: 4.0)
        XCTAssertNil(
            engine.busTrackSumMixerForTesting(trackID: trackID),
            "after bus→master the track must have no bus voice pool"
        )
        let masterChokepoint = try XCTUnwrap(engine.trackOutputChokepointNodeForTesting(trackID: trackID))
        XCTAssertGreaterThan(
            masterChokepoint.outputVolume, 0.5,
            "bus→master must NOT regress to silence — the new master chokepoint must be restored to its configured level"
        )
    }

    /// Mirror of the above for the master→bus direction (the route-to-bus click,
    /// docs/bugs/20260626-route-to-bus-click): the outgoing MASTER chokepoint
    /// (the track mixer) must ramp to silence before its hard disconnect, and the
    /// track must land on the bus still audible.
    @MainActor
    func test_routeSwitch_masterToBus_soundingTrack_crossfades_notHardCut_andStaysAudible() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let busID = UUID()
        graph.installSendBuses([.sendA, .sendB])
        graph.installMixerBuses([MixerBus(id: busID, name: "FX")])
        let engine = SamplePlaybackEngine(audioGraph: graph)
        try engine.start()
        defer { engine.stop() }

        let trackID = UUID()
        // Master-routed, sounding.
        engine.prepareTrack(trackID: trackID)
        engine.setTrackMix(trackID: trackID, level: 0.8, pan: 0)
        let masterChokepoint = try XCTUnwrap(engine.trackOutputChokepointNodeForTesting(trackID: trackID))
        masterChokepoint.outputVolume = 0.8

        // Switch to the bus — the route-switch under test (Site 2).
        let crossfadesBefore = engine.sampleRouteCrossfadeCountForTesting
        engine.setTrackOutputBus(trackID: trackID, busID: busID)
        XCTAssertEqual(
            engine.sampleRouteCrossfadeCountForTesting, crossfadesBefore + 1,
            "a master→bus switch of a sounding track must ramp the outgoing chokepoint to silence, not hard-cut"
        )

        // Outgoing MASTER chokepoint fades to silence before its deferred teardown.
        let faded = expectation(description: "outgoing master chokepoint fades to silence")
        let fadeDeadline = Date().addingTimeInterval(2.0)
        func pollFade() {
            if masterChokepoint.outputVolume <= 0.001 {
                faded.fulfill()
                return
            }
            if Date() > fadeDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { pollFade() }
        }
        pollFade()
        wait(for: [faded], timeout: 3.0)

        // NO REGRESSION: track lands on the bus with a sounding chokepoint.
        let settled = expectation(description: "track re-routes to bus and stays audible")
        let settleDeadline = Date().addingTimeInterval(3.0)
        func pollSettled() {
            if let sumMixer = engine.busTrackSumMixerForTesting(trackID: trackID),
               sumMixer.outputVolume > 0.5 {
                settled.fulfill()
                return
            }
            if Date() > settleDeadline { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { pollSettled() }
        }
        pollSettled()
        wait(for: [settled], timeout: 4.0)
        let sumMixer = try XCTUnwrap(
            engine.busTrackSumMixerForTesting(trackID: trackID),
            "after master→bus the track must have a bus voice pool"
        )
        XCTAssertGreaterThan(
            sumMixer.outputVolume, 0.5,
            "master→bus must NOT regress to silence — the new bus sum chokepoint must be restored to its configured level"
        )
    }
}
