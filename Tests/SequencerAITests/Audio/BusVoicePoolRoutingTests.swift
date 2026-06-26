import AVFoundation
import XCTest
@testable import SequencerAI

/// Regression coverage for docs/bugs/20260626-route-track-to-mixer-bus-goes-silent.
///
/// Two distinct failures, both fixed here:
///
/// 1. Single-track silence — a sole sample track routed to a bus was inaudible.
///    The bus input mixer's OUTPUT edge to preMaster was silently dropped by
///    AVAudioEngine because the bus had no inputs when that edge was wired at
///    install time (a mixer with no inputs has no resolvable output format), and
///    nothing re-established it once a track fed the bus. The voice chain looked
///    live but dead-ended at the bus.
///
/// 2. Multi-track / drum-kit collision — every track routed to the SAME bus
///    connected its 4 voice mixers to the bus's input buses 0..3 (a hardcoded
///    per-track index), so a second routed track overwrote the first. Only one
///    part reached the bus.
///
/// The fix: each voice mixer lands on a UNIQUE free input bus across the whole
/// bus, and connecting a voice (re)asserts the bus terminal -> preMaster edge.
/// The fast-path gate now also verifies the bus reaches preMaster.
final class BusVoicePoolRoutingTests: XCTestCase {
    @MainActor
    func test_singleTrackRoutedToBus_busReachesPreMaster() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let trackID = UUID()
        let busID = UUID()

        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])
        engine.prepareTrack(trackID: trackID)
        engine.setTrackOutputBus(trackID: trackID, busID: busID)

        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        let busInput = busReadout.inputMixer

        // Every voice mixer feeds the bus input mixer.
        let mixers = engine.busVoiceMixersForTesting(trackID: trackID)
        XCTAssertEqual(mixers.count, 4)
        for mixer in mixers {
            let outs = graph.engine.outputConnectionPoints(for: mixer, outputBus: 0)
            XCTAssertTrue(outs.contains { $0.node === busInput }, "voice mixer feeds the bus")
        }

        // The whole chain is live: the bus's output edge reaches preMaster.
        // This was outputConnectionPoints(count: 0) before the fix — the silence.
        let busOuts = graph.engine.outputConnectionPoints(for: busInput, outputBus: 0)
        XCTAssertTrue(busOuts.contains { $0.node === graph.preMasterMixer },
                      "bus input mixer must reach preMaster (was silently dropped = silence)")
        XCTAssertTrue(graph.mixerBusTerminalReachesPreMaster(busID: busID))
    }

    @MainActor
    func test_twoTracksRoutedToSameBus_distinctInputBuses_noCollision() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let busID = UUID()
        let track1 = UUID()
        let track2 = UUID()

        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])
        let busInput = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID)).inputMixer

        for trackID in [track1, track2] {
            engine.prepareTrack(trackID: trackID)
            engine.setTrackOutputBus(trackID: trackID, busID: busID)
        }

        var occupied: [Int] = []
        for trackID in [track1, track2] {
            for mixer in engine.busVoiceMixersForTesting(trackID: trackID) {
                let bus = graph.engine.outputConnectionPoints(for: mixer, outputBus: 0)
                    .first(where: { $0.node === busInput })?.bus
                let unwrapped = try XCTUnwrap(bus, "voice mixer must reach the bus (was overwritten on collision)")
                occupied.append(unwrapped)
            }
        }

        // 2 tracks × 4 voices = 8 mixers, each on a DISTINCT bus input.
        XCTAssertEqual(occupied.count, 8)
        XCTAssertEqual(Set(occupied).count, 8, "no input-bus collisions across tracks")
        XCTAssertTrue(graph.mixerBusTerminalReachesPreMaster(busID: busID))
    }

    /// Routing a track back to master frees its bus input buses; a later track
    /// re-fills them rather than leaking past.
    @MainActor
    func test_rerouteBackToMaster_freesBusInputBuses_noLeak() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let busID = UUID()
        let track1 = UUID()
        let track2 = UUID()
        let track3 = UUID()

        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])
        let busInput = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID)).inputMixer

        for trackID in [track1, track2] {
            engine.prepareTrack(trackID: trackID)
            engine.setTrackOutputBus(trackID: trackID, busID: busID)
        }
        // track1 -> 0..3, track2 -> 4..7. Send track2 back to master.
        engine.setTrackOutputBus(trackID: track2, busID: nil)

        engine.prepareTrack(trackID: track3)
        engine.setTrackOutputBus(trackID: track3, busID: busID)

        var t3buses = Set<Int>()
        for mixer in engine.busVoiceMixersForTesting(trackID: track3) {
            if let bus = graph.engine.outputConnectionPoints(for: mixer, outputBus: 0)
                .first(where: { $0.node === busInput })?.bus { t3buses.insert(bus) }
        }
        XCTAssertEqual(t3buses, [4, 5, 6, 7], "freed input buses must be re-filled, not leaked")
    }
}
