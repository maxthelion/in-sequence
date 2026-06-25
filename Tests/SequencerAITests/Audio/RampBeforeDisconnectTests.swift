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
}
