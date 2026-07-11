import AVFoundation
import XCTest
@testable import SequencerAI

/// Mutation-path guard for the scene-FX AU-attenuation bug
/// (docs/bugs/20260702-143000-scene-fx-attenuates-au-track-until-restart).
///
/// The mutation under test is the exact live path the Scenes workspace drives:
/// `MasterBusHost.apply` with a scene-insert topology change →
/// `MainAudioGraph.installMasterChains` while the engine remains running behind
/// its dedicated topology gate. The AU-branch stand-in is an `AVAudioSourceNode` sine feeding an
/// output mixer routed exactly like `AudioInstrumentHost`'s (`connectTrackOutput`
/// through the persistent send fanout) — like a real AU it has no play() state,
/// so it keeps rendering across the restart.
///
/// These assertions pin the GAIN/WIRING half of the bug space: after the
/// insert is added and after it is removed, no gain stage on the AU branch may
/// be left attenuated and the branch must still reach master (rendered RMS).
/// The live-HAL render timeline must not reset for this mutation; the routing
/// lint enforces that master topology changes contain no engine stop/start.
final class SceneFXMutationAUBranchTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 1, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scene-fx-au-branch-\(UUID().uuidString).wav")
    }

    /// Renders `frames` offline and returns the master-render RMS, or nil when
    /// the master tap delivered NO buffers. On a CoreAudio-degraded host
    /// (HALC_ShellObject proxy errors — see the MasterRenderTests precedent)
    /// the offline meter/render taps can go blind even though the graph edits
    /// under test executed fine; the caller skips the loudness half then
    /// (verify on a healthy host / after `sudo killall coreaudiod`) while the
    /// gain/wiring asserts stay hard.
    private func renderedRMS(
        graph: MainAudioGraph,
        frames: AVAudioFrameCount
    ) throws -> Double? {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(graph.startMasterRender(to: url))
        try graph.renderOfflineForTesting(frameCount: frames)
        XCTAssertEqual(graph.stopMasterRender(), url)

        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return nil }
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        var sum: Double = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += Double(data[index]) * Double(data[index])
        }
        return (sum / Double(buffer.frameLength)).squareRoot()
    }

    @MainActor
    func test_addAndRemoveSceneInsert_whileRunning_leavesAUBranchGainAndAudibilityIntact() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let graph = MainAudioGraph()
        // Isolation convention (bug 20260702-140500): stop the graph at
        // teardown so it never deallocates with live taps/engine state that
        // could leak into the next suite.
        addTeardownBlock { graph.stop() }
        // Production shape: send buses exist, so the track's dry signal routes
        // THROUGH its persistent fanout gain stage.
        graph.installSendBuses([.sendA, .sendB])
        let masterBusHost = MasterBusHost()
        masterBusHost.attach(to: graph)

        // AU-branch stand-in: a render-block sine (no play() state — survives
        // a live topology edit, like a real AU) → the host-style output mixer.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        var phase: Double = 0
        let increment = 2.0 * Double.pi * 220.0 / 44_100.0
        let sine = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = Float(sin(phase)) * 0.5
                phase += increment
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        graph.attach(sine)
        let auOutputMixer = AVAudioMixerNode()
        graph.attach(auOutputMixer)
        graph.connect(sine, to: auOutputMixer, format: format)
        auOutputMixer.outputVolume = 0.8
        graph.connectTrackOutput(auOutputMixer, to: nil, ramped: false)

        try graph.start()
        // For a mixer source (the AU host shape) the routing gain stage IS the
        // output mixer itself — the same node a splice dip would ramp.
        let gainStage = try XCTUnwrap(graph.trackGainStageForTesting(auOutputMixer))
        XCTAssertTrue(gainStage === auOutputMixer)

        let baselineRMSOrNil = try renderedRMS(graph: graph, frames: 22_050)
        if let baseline = baselineRMSOrNil {
            XCTAssertGreaterThan(baseline, 0.01, "AU-branch stand-in must be audible at master before the mutation")
        }

        // THE MUTATION (owner repro step 2): add an FX insert to Scene A while
        // the engine runs. Topology change is gated, rebuilt, and restored
        // without resetting the live render timeline.
        var state = MasterBusState.default
        state.addInsert(.filter(), sceneID: state.activeSceneID)
        masterBusHost.apply(state)
        waitUntil {
            graph.masterBranchesForTesting.contains { !$0.nodes.isEmpty }
        }

        XCTAssertTrue(graph.isEngineRunning, "master-chain rebuild must leave the engine running")
        XCTAssertTrue(graph.masterBranchesForTesting.contains { !$0.nodes.isEmpty })
        XCTAssertEqual(
            auOutputMixer.outputVolume, 0.8, accuracy: 0.001,
            "the AU host's output mixer gain (the track's routing gain stage) must be untouched by a master-bus mutation"
        )
        if let baseline = baselineRMSOrNil, let withInsertRMS = try renderedRMS(graph: graph, frames: 22_050) {
            XCTAssertEqual(
                withInsertRMS, baseline, accuracy: baseline * 0.15,
                "a neutral scene filter (low-pass 12 kHz over a 220 Hz sine) must not attenuate the AU branch"
            )
        }

        // Owner repro step 4: REMOVE the FX — the level must be fully restored
        // (the bug left the attenuation sticky until transport restart).
        masterBusHost.apply(.default)
        waitUntil {
            !graph.masterBranchesForTesting.isEmpty &&
                graph.masterBranchesForTesting.allSatisfy(\.nodes.isEmpty)
        }

        XCTAssertTrue(graph.isEngineRunning, "insert removal must leave the engine running")
        XCTAssertTrue(graph.masterBranchesForTesting.allSatisfy(\.nodes.isEmpty))
        XCTAssertEqual(
            auOutputMixer.outputVolume, 0.8, accuracy: 0.001,
            "insert removal must leave the AU output mixer gain at its settled level — no sticky attenuation"
        )
        if let baseline = baselineRMSOrNil, let removedRMS = try renderedRMS(graph: graph, frames: 22_050) {
            XCTAssertEqual(
                removedRMS, baseline, accuracy: baseline * 0.15,
                "after removing the scene FX the AU branch must be back at its baseline level — no sticky attenuation"
            )
        }

        graph.stop()

        if baselineRMSOrNil == nil {
            throw XCTSkip(
                "master render tap delivered no buffers — CoreAudio-degraded host (HALC proxy errors); " +
                "gain/wiring asserts above ran and passed; re-check the RMS half after a coreaudiod restart"
            )
        }
    }
}
