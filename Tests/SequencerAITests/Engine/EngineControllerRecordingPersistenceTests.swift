import AVFoundation
import XCTest
@testable import SequencerAI

/// Completed audio-input captures must land in the recording library
/// (WAV + sidecar) without the tick path or main blocking on disk IO, and a
/// failed write must leave the in-session loop fully functional.
final class EngineControllerRecordingPersistenceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeFixture(
        recordingLibrary: RecordingLibrary?
    ) -> (controller: EngineController, trackID: UUID) {
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 4,
            publishesAudioInputCapture: true,
            recordingLibrary: recordingLibrary
        )
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        controller.audioInputCapturePlanOverrideForTesting = { _, bars in
            AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: max(1, bars * 4096))
        }
        controller.bypassAudioInputRoutingSyncForTesting = true
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.tracks[project.selectedTrackIndex].recordBarLength = 1
        project.tracks[project.selectedTrackIndex].name = "Guitar"
        controller.apply(documentModel: project)
        return (controller, trackID)
    }

    private func completeOneCapture(_ controller: EngineController, trackID: UUID) {
        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: 4))
        controller.processTick(tickIndex: 4, now: 0.4)
        controller.recordAudioInputBufferForTesting(trackID: trackID, buffer: makeConstantStereoBuffer(amplitude: 0.5))
        controller.drainAudioInputCapturePublicationForTesting()
        controller.processTick(tickIndex: 8, now: 0.8)
    }

    func test_completedCapture_persistsWavAndSidecar_andTagsRuntimeWithAssetID() throws {
        let library = RecordingLibrary(libraryRoot: tempRoot)
        let (controller, trackID) = makeFixture(recordingLibrary: library)

        let persisted = expectation(description: "recording persisted")
        var persistedAsset: RecordingAsset?
        controller.recordingPersistenceObserverForTesting = { result in
            persistedAsset = try? result.get()
            persisted.fulfill()
        }

        completeOneCapture(controller, trackID: trackID)
        wait(for: [persisted], timeout: 5)

        let asset = try XCTUnwrap(persistedAsset)
        XCTAssertEqual(asset.sourceTrackName, "Guitar")
        XCTAssertEqual(asset.barCount, 1)
        XCTAssertEqual(asset.bpm, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: asset).path))

        // Session N+1 sees the take.
        XCTAssertEqual(RecordingLibrary(libraryRoot: tempRoot).recording(id: asset.id)?.name, asset.name)

        // The runtime carries the library asset ID once the write lands.
        let runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .hasLoop)
        XCTAssertEqual(runtime.recordedLibraryAssetID, asset.id)
    }

    func test_writeFailure_isTolerated_loopKeepsPlayingFromMemory() throws {
        // Block the recordings directory path so every write fails.
        let blockedPath = tempRoot.appendingPathComponent(RecordingLibrary.recordingsDirectoryName)
        try Data("not a directory".utf8).write(to: blockedPath)
        let library = RecordingLibrary(libraryRoot: tempRoot)
        let (controller, trackID) = makeFixture(recordingLibrary: library)

        let failed = expectation(description: "persistence failed")
        controller.recordingPersistenceObserverForTesting = { result in
            if case .failure = result {
                failed.fulfill()
            } else {
                XCTFail("expected the write to fail")
            }
        }

        completeOneCapture(controller, trackID: trackID)
        wait(for: [failed], timeout: 5)

        let runtime = try XCTUnwrap(controller.audioInputRuntime(for: trackID))
        XCTAssertEqual(runtime.armState, .hasLoop, "failed write must not break the session loop")
        XCTAssertNotNil(runtime.recordedLoopID)
        XCTAssertNil(runtime.recordedLibraryAssetID)
        XCTAssertFalse(runtime.waveformBuckets.isEmpty, "completed waveform stays available from memory")
        XCTAssertTrue(library.recordings.isEmpty)
    }
}

private func makeConstantStereoBuffer(amplitude: Float) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
    buffer.frameLength = 16
    for frame in 0..<16 {
        buffer.floatChannelData![0][frame] = amplitude
        buffer.floatChannelData![1][frame] = amplitude
    }
    return buffer
}
