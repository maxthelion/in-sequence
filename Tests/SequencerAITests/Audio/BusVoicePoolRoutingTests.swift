import AVFoundation
import XCTest
@testable import SequencerAI

/// Regression coverage for docs/bugs/20260626-route-track-to-mixer-bus-goes-silent
/// and the metering cluster (route-to-bus click / routed-track meter).
///
/// Failures fixed across these:
///
/// 1. Single-track silence — a sole sample track routed to a bus was inaudible.
///    The bus input mixer's OUTPUT edge to preMaster was silently dropped by
///    AVAudioEngine because the bus had no inputs when that edge was wired at
///    install time (a mixer with no inputs has no resolvable output format), and
///    nothing re-established it once a track fed the bus.
///
/// 2. Multi-track / drum-kit collision — tracks routed to the same bus must each
///    land on a DISTINCT bus input. Each track now sums its 4 voices into a single
///    per-track sum node and connects THAT once to the bus (one input per track),
///    so a second routed track can never overwrite the first.
///
/// 3. Routed-track SOURCE meter (#62) — the per-track sum node is the track's own
///    pre-bus output and is registered as the track's meter source, so a routed
///    track still meters its own level (track<N>Peak), independent of the bus.
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

        // Every voice mixer feeds the per-track sum node.
        let sumMixer = try XCTUnwrap(engine.busTrackSumMixerForTesting(trackID: trackID))
        let mixers = engine.busVoiceMixersForTesting(trackID: trackID)
        XCTAssertEqual(mixers.count, 4)
        for mixer in mixers {
            let outs = graph.engine.outputConnectionPoints(for: mixer, outputBus: 0)
            XCTAssertTrue(outs.contains { $0.node === sumMixer }, "voice mixer feeds the per-track sum node")
        }

        // The per-track sum node feeds the bus input mixer (one input per track).
        let sumOuts = graph.engine.outputConnectionPoints(for: sumMixer, outputBus: 0)
        XCTAssertTrue(sumOuts.contains { $0.node === busInput }, "per-track sum node feeds the bus")

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

        // Each track contributes ONE input to the bus (its per-track sum node),
        // and the two inputs must be distinct (no collision).
        var occupied: [Int] = []
        for trackID in [track1, track2] {
            let sumMixer = try XCTUnwrap(engine.busTrackSumMixerForTesting(trackID: trackID))
            let bus = graph.engine.outputConnectionPoints(for: sumMixer, outputBus: 0)
                .first(where: { $0.node === busInput })?.bus
            let unwrapped = try XCTUnwrap(bus, "per-track sum node must reach the bus (was overwritten on collision)")
            occupied.append(unwrapped)
        }

        XCTAssertEqual(occupied.count, 2)
        XCTAssertEqual(Set(occupied).count, 2, "no input-bus collisions across tracks")
        XCTAssertTrue(graph.mixerBusTerminalReachesPreMaster(busID: busID))
    }

    /// Routing a track back to master frees its bus input bus; a later track
    /// re-fills it rather than leaking past.
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

        func busInputIndex(for trackID: UUID) throws -> Int {
            let sumMixer = try XCTUnwrap(engine.busTrackSumMixerForTesting(trackID: trackID))
            let bus = graph.engine.outputConnectionPoints(for: sumMixer, outputBus: 0)
                .first(where: { $0.node === busInput })?.bus
            return try XCTUnwrap(bus, "per-track sum node must reach the bus")
        }

        for trackID in [track1, track2] {
            engine.prepareTrack(trackID: trackID)
            engine.setTrackOutputBus(trackID: trackID, busID: busID)
        }
        // track1 -> input 0, track2 -> input 1. Send track2 back to master.
        let track2Index = try busInputIndex(for: track2)
        engine.setTrackOutputBus(trackID: track2, busID: nil)

        engine.prepareTrack(trackID: track3)
        engine.setTrackOutputBus(trackID: track3, busID: busID)

        // track3 re-fills the input freed by track2 (lowest free), not a leaked higher one.
        XCTAssertEqual(try busInputIndex(for: track3), track2Index,
                       "freed input bus must be re-filled, not leaked")
    }

    /// #62: a track routed to a bus keeps its OWN meter source on its pre-bus
    /// output (the per-track sum node), so the source track meters regardless of
    /// where it is routed.
    @MainActor
    func test_busRoutedTrack_meterSourceIsItsOwnSumNode() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let trackID = UUID()
        let busID = UUID()

        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])
        engine.prepareTrack(trackID: trackID)
        engine.setTrackOutputBus(trackID: trackID, busID: busID)

        let sumMixer = try XCTUnwrap(engine.busTrackSumMixerForTesting(trackID: trackID))
        XCTAssertTrue(graph.trackMeterSourceNodeForTesting(trackID: trackID) === sumMixer,
                      "bus-routed track must meter its own pre-bus sum node")
    }
}
