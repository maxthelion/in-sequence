import AVFoundation
import XCTest
@testable import SequencerAI

/// Regression coverage for: routing a track's output to a freshly-created
/// mixer bus produced silence (the bus's signal never reached master), while
/// routing to master worked. Root cause: installMixerBuses rebuilt bus hosts
/// but — unlike installSendBuses — never re-wired the tracks routed to those
/// buses, so a track routed to a bus whose host did not yet exist (or whose
/// topology just rebuilt) was left on the preMaster fallback / a stale node
/// and the track→bus→master chain was never established.
final class MixerBusRoutingReconnectTests: XCTestCase {
    @MainActor
    func test_installMixerBuses_reconnectsTrackRoutedToBusInstalledAfterTheRoute() throws {
        let graph = MainAudioGraph()
        let source = AVAudioPlayerNode()
        let busID = UUID()
        graph.attach(source)

        // Route the track to a bus whose host does NOT exist yet. With no
        // host, the route fails safe to preMaster (the "plays on master"
        // behaviour) — but the user picked the bus.
        graph.connectTrackOutput(source, to: busID)
        XCTAssertTrue(
            graph.trackOutputDestinationForTesting(source) === graph.preMasterMixer,
            "with no bus host the route falls back to preMaster"
        )

        // The bus host is installed afterwards (the document apply that adds
        // the bus). Before the fix this pass ignored the already-routed track,
        // so it stayed on preMaster and the bus stayed silent.
        graph.installMixerBuses([MixerBus(id: busID, name: "Drum Bus")])

        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertTrue(
            graph.trackOutputDestinationForTesting(source) === busReadout.inputMixer,
            "after the bus host is installed the track must be re-wired to the bus input mixer"
        )
        XCTAssertTrue(
            busReadout.terminalOutputNode === graph.preMasterMixer,
            "bus terminal must reach preMaster so the chain track→bus→master is complete"
        )
    }

    /// Live-engine end-to-end: drum (sample) track routed to a fresh bus mid
    /// session reaches master through the bus. Uses manual rendering so the
    /// engine runs without booting CoreAudio (the HALC proxy stall).
    @MainActor
    func test_liveEngine_drumTrackRoutedToFreshBus_reachesMasterThroughBus() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bus-route-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("kick", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: root.appendingPathComponent("kick/k.wav"))
        let library = AudioSampleLibrary(libraryRoot: root)
        let sampleID = AudioSampleLibrary.stableID(forRelativePath: "kick/k.wav")

        let graph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: graph)
        let controller = EngineController(
            client: nil, endpoint: nil,
            mainAudioGraph: graph, sampleEngine: sampleEngine, sampleLibrary: library
        )
        let drum = StepSequenceTrack(
            name: "Kick", pitches: [60], stepPattern: [true], stepAccents: [false],
            destination: .sample(sampleID: sampleID, settings: .default), velocity: 100, gateLength: 2
        )
        var doc = Project(version: 1, tracks: [drum], selectedTrackID: drum.id)
        controller.apply(documentModel: doc)
        controller.start()

        let busID = doc.addMixerBus(name: "Drum Bus")
        controller.apply(documentModel: doc)
        doc.setTrackOutputBus(trackID: drum.id, busID: busID)
        controller.apply(documentModel: doc)

        let busReadout = try XCTUnwrap(graph.mixerBusReadoutForTesting(busID: busID))
        // A bus-routed SAMPLE track sums through its bus voice pool's voice
        // mixers (no per-track filter node), so verify the voice mixers feed the
        // bus and the bus reaches master.
        let voiceMixers = sampleEngine.busVoiceMixersForTesting(trackID: drum.id)
        let busOuts = graph.engine.outputConnectionPoints(for: busReadout.inputMixer, outputBus: 0).compactMap(\.node)
        controller.stop()

        XCTAssertFalse(voiceMixers.isEmpty, "bus-routed sample track has a bus voice pool")
        for mixer in voiceMixers {
            let outs = graph.engine.outputConnectionPoints(for: mixer, outputBus: 0).compactMap(\.node)
            XCTAssertTrue(outs.contains { $0 === busReadout.inputMixer }, "drum track voice feeds the bus")
        }
        XCTAssertTrue(busOuts.contains { $0 === graph.preMasterMixer }, "bus reaches master")
    }
}
