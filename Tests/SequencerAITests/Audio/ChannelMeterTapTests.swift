import AVFoundation
import XCTest
@testable import SequencerAI

/// Channel meter taps generalize the master tap: installed at graph build
/// time on each strip's node, removed/reinstalled across every rebuild.
final class ChannelMeterTapTests: XCTestCase {
    @MainActor
    func test_installMixerBusesTapsEachBusInputMixer() {
        let graph = MainAudioGraph()
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 0)

        graph.installMixerBuses([
            MixerBus(id: UUID(), name: "Drums"),
            MixerBus(id: UUID(), name: "Synths"),
        ])

        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 2)
    }

    @MainActor
    func test_installSendBusesTapsBothFixedSendMixers() {
        let graph = MainAudioGraph()

        graph.installSendBuses([.sendA, .sendB])

        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 2)
    }

    @MainActor
    func test_trackMeterSourceRegistrationTapsNodeAndDetachClearsIt() {
        let graph = MainAudioGraph()
        let trackID = UUID()
        let source = AVAudioMixerNode()
        graph.attach(source)
        graph.connectTrackOutput(source, to: nil)

        graph.setTrackMeterSources(trackIDs: [trackID], node: source)

        XCTAssertEqual(graph.trackMeterSourceCountForTesting, 1)
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 1)

        graph.disconnectOutput(source)
        graph.detach(source)

        XCTAssertEqual(graph.trackMeterSourceCountForTesting, 0)
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 0)
    }

    @MainActor
    func test_sharedHostNodeMetersAllItsTracksFromOneTap() {
        let graph = MainAudioGraph()
        let source = AVAudioMixerNode()
        graph.attach(source)
        graph.connectTrackOutput(source, to: nil)

        graph.setTrackMeterSources(trackIDs: [UUID(), UUID()], node: source)

        XCTAssertEqual(graph.trackMeterSourceCountForTesting, 2)
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 1)
    }

    @MainActor
    func test_emptyRegistrationUnregistersNode() {
        let graph = MainAudioGraph()
        let trackID = UUID()
        let source = AVAudioMixerNode()
        graph.attach(source)
        graph.connectTrackOutput(source, to: nil)
        graph.setTrackMeterSources(trackIDs: [trackID], node: source)
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 1)

        graph.setTrackMeterSources(trackIDs: [], node: source)

        XCTAssertEqual(graph.trackMeterSourceCountForTesting, 0)
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 0)
    }

    @MainActor
    func test_channelTapsReinstallAcrossGraphRebuilds() {
        let graph = MainAudioGraph()
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])
        let installsAfterFirst = graph.channelMeterTapInstallCountForTesting
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 1)

        // Any rebuild path removes and reinstalls the channel taps with the
        // master tap.
        graph.installSendBuses([.sendA, .sendB])

        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 3)
        XCTAssertGreaterThan(graph.channelMeterTapInstallCountForTesting, installsAfterFirst)
        XCTAssertGreaterThan(graph.channelMeterTapRemoveCountForTesting, 0)
    }

    @MainActor
    func test_removedBusLosesItsMeterTap() {
        let graph = MainAudioGraph()
        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "Drums")])
        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 1)

        graph.installMixerBuses([])

        XCTAssertEqual(graph.channelMeterTappedNodeCountForTesting, 0)
    }
}
