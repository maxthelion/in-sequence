import AVFoundation
import SwiftUI
import XCTest
@testable import SequencerAI

final class EngineControllerAudioInputPublicationTests: XCTestCase {
    func test_audioInputPublication_copiesLiveLevelSnapshotToRuntime() throws {
        let (controller, _, trackID) = makeAudioInputPublicationFixture(recordBarLength: 1)
        let buffer = makeBuffer(left: [0.1, -0.4, 0.2], right: [0.2, -0.8, 0.1])

        controller.recordAudioInputBufferForTesting(trackID: trackID, buffer: buffer)
        waitForAudioInputPublication(controller)

        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.liveLevel.leftPeak, 0.4, accuracy: 0.0001)
        XCTAssertEqual(runtime.liveLevel.rightPeak, 0.8, accuracy: 0.0001)

        buffer.floatChannelData?[0][1] = 0
        buffer.floatChannelData?[1][1] = 0
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.liveLevel.leftPeak, 0.4, accuracy: 0.0001)
        XCTAssertEqual(runtime.liveLevel.rightPeak, 0.8, accuracy: 0.0001)
    }

    func test_audioInputPublication_streamsProgressAndFinalBucketsFromCapturedLoopData() throws {
        let (controller, _, trackID) = makeAudioInputPublicationFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.recordAudioInputBufferForTesting(
            trackID: trackID,
            buffer: makeBuffer(left: [0.1, 0.25, -0.5, 0.35], right: [0.2, 0.45, -0.7, 0.1])
        )
        waitForAudioInputPublication(controller)

        var runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .recording)
        XCTAssertEqual(runtime.recordingProgress, 0, accuracy: 0.0001)
        XCTAssertFalse(runtime.captureWaveformBuckets.isEmpty)
        XCTAssertTrue(runtime.waveformBuckets.isEmpty)

        controller.processTick(tickIndex: 6, now: 0.6)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.recordingProgress, 0.5, accuracy: 0.0001)

        controller.processTick(tickIndex: 8, now: 0.8)
        runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .hasLoop)
        XCTAssertEqual(runtime.recordingProgress, 1, accuracy: 0.0001)
        XCTAssertTrue(runtime.captureWaveformBuckets.isEmpty)
        XCTAssertFalse(runtime.waveformBuckets.isEmpty)
        XCTAssertGreaterThan(runtime.waveformBuckets.max() ?? 0, 0.45)
    }

    func test_audioInputPublication_rerecordReplacesCompletedWaveformBuckets() throws {
        let (controller, _, trackID) = makeAudioInputPublicationFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.recordAudioInputBufferForTesting(trackID: trackID, buffer: makeConstantBuffer(amplitude: 0.2))
        waitForAudioInputPublication(controller)
        controller.processTick(tickIndex: 8, now: 0.8)

        let firstRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        let firstLoopID = try XCTUnwrap(firstRuntime.recordedLoopID)
        let firstPeak = try XCTUnwrap(firstRuntime.waveformBuckets.max())

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 12))
        controller.processTick(tickIndex: 12, now: 1.2)
        controller.recordAudioInputBufferForTesting(trackID: trackID, buffer: makeConstantBuffer(amplitude: 0.85))
        waitForAudioInputPublication(controller)
        controller.processTick(tickIndex: 16, now: 1.6)

        let secondRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        let secondLoopID = try XCTUnwrap(secondRuntime.recordedLoopID)
        let secondPeak = try XCTUnwrap(secondRuntime.waveformBuckets.max())
        XCTAssertNotEqual(secondLoopID, firstLoopID)
        XCTAssertGreaterThan(secondPeak, firstPeak + 0.5)
    }

    func test_audioInputRuntimePublication_exposesCopiedSnapshotsNotCaptureBuffers() throws {
        let (controller, _, trackID) = makeAudioInputPublicationFixture(recordBarLength: 1)

        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.recordAudioInputBufferForTesting(trackID: trackID, buffer: makeConstantBuffer(amplitude: 0.6))
        waitForAudioInputPublication(controller)

        let runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertFalse(runtime.captureWaveformBuckets.isEmpty)
        XCTAssertFalse(Mirror(reflecting: runtime).children.contains { $0.value is AVAudioPCMBuffer })

        var copiedBuckets = runtime.captureWaveformBuckets
        copiedBuckets[0] = 0

        let freshRuntime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertGreaterThan(freshRuntime.captureWaveformBuckets.max() ?? 0, 0.5)
    }

    func test_audioInputPublication_engineInitializerInstallsGraphCaptureHandler() {
        let graph = MainAudioGraph()

        _ = EngineController(
            client: nil,
            endpoint: nil,
            mainAudioGraph: graph,
            publishesAudioInputCapture: true
        )

        XCTAssertTrue(graph.audioInputCaptureHandlerInstalledForTesting)
    }

    @MainActor
    func test_audioInputPublication_productionDocumentSessionEnablesCapturePublication() {
        let document = SeqAIDocument()
        let binding = Binding<SeqAIDocument>(
            get: { document },
            set: { _ in }
        )

        let session = SequencerDocumentSession(document: binding)

        XCTAssertTrue(session.engineController.audioInputCapturePublicationEnabledForTesting)
    }

    private func waitForAudioInputPublication(_ controller: EngineController) {
        controller.drainAudioInputCapturePublicationForTesting()
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

private func makeAudioInputPublicationFixture(
    recordBarLength: Int
) -> (controller: EngineController, project: Project, trackID: UUID) {
    let controller = EngineController(
        client: nil,
        endpoint: nil,
        stepsPerBar: 4,
        publishesAudioInputCapture: true
    )
    controller.audioInputAvailableChannelCountOverrideForTesting = 2
    controller.bypassAudioInputRoutingSyncForTesting = true
    var project = Project.empty
    project.appendTrack(trackType: .audioInput)
    let trackID = project.selectedTrackID
    project.tracks[project.selectedTrackIndex].recordBarLength = recordBarLength
    controller.apply(documentModel: project)
    return (controller, project, trackID)
}

private func makeConstantBuffer(amplitude: Float) -> AVAudioPCMBuffer {
    makeBuffer(
        left: Array(repeating: amplitude, count: 16),
        right: Array(repeating: amplitude, count: 16)
    )
}

private func makeBuffer(left: [Float], right: [Float]) -> AVAudioPCMBuffer {
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
