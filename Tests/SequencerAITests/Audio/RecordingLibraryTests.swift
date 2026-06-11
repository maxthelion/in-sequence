import AVFoundation
import XCTest
@testable import SequencerAI

final class RecordingLibraryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makePCM(frameCount: Int = 512, sampleRate: Double = 44_100, channels: Int = 2) -> AudioInputCapturedPCM {
        let channelData = (0..<channels).map { channel in
            (0..<frameCount).map { frame in
                Float(sin(Double(frame) * 0.1 + Double(channel))) * 0.5
            }
        }
        return AudioInputCapturedPCM(sampleRate: sampleRate, channels: channelData)
    }

    // MARK: - Round trip

    func test_storeRecording_roundTripsThroughFreshLibraryInstance() throws {
        let library = RecordingLibrary(libraryRoot: tempRoot)
        let pcm = makePCM(frameCount: 1024)

        let asset = try library.storeRecording(
            pcm: pcm,
            sourceTrackName: "Guitar",
            barCount: 2,
            bpm: 128
        )

        XCTAssertEqual(asset.name, "Guitar — 2 bars — take 1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: asset).path))

        // Session N+1: a fresh instance over the same root sees the take.
        let reloaded = RecordingLibrary(libraryRoot: tempRoot)
        let loaded = try XCTUnwrap(reloaded.recording(id: asset.id))
        XCTAssertEqual(loaded, asset)
        XCTAssertEqual(loaded.barCount, 2)
        XCTAssertEqual(loaded.bpm, 128)
        XCTAssertEqual(loaded.sourceTrackName, "Guitar")
        XCTAssertEqual(loaded.sampleRate, 44_100)
        XCTAssertEqual(loaded.channelCount, 2)
        XCTAssertEqual(loaded.lengthFrames, 1024)

        // The WAV itself is readable and frame-accurate.
        let file = try AVAudioFile(forReading: reloaded.fileURL(for: loaded))
        XCTAssertEqual(Int64(file.length), 1024)
        XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
    }

    func test_storedRecording_isBrowsableAsSampleWithSameStableID() throws {
        let library = RecordingLibrary(libraryRoot: tempRoot)
        let asset = try library.storeRecording(
            pcm: makePCM(),
            sourceTrackName: "Mic",
            barCount: 1,
            bpm: 120
        )

        let sampleLibrary = AudioSampleLibrary(libraryRoot: tempRoot)
        let recordings = sampleLibrary.samples(in: .recordings)
        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings.first?.id, asset.id, "recording asset ID must match the sample library's UUIDv5 ID")
        XCTAssertEqual(recordings.first?.name, asset.name)
    }

    func test_takeNumber_incrementsPerSourceTrack() throws {
        let library = RecordingLibrary(libraryRoot: tempRoot)

        let first = try library.storeRecording(pcm: makePCM(), sourceTrackName: "Bass", barCount: 1, bpm: 120)
        let second = try library.storeRecording(pcm: makePCM(), sourceTrackName: "Bass", barCount: 4, bpm: 120)
        let other = try library.storeRecording(pcm: makePCM(), sourceTrackName: "Keys", barCount: 1, bpm: 120)

        XCTAssertEqual(first.name, "Bass — 1 bar — take 1")
        XCTAssertEqual(second.name, "Bass — 4 bars — take 2")
        XCTAssertEqual(other.name, "Keys — 1 bar — take 1")
        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - Failure tolerance

    func test_storeRecording_throwsWhenRecordingsPathIsBlocked_andLibraryStaysConsistent() throws {
        // A file squatting on the recordings directory path makes every write fail.
        let blockedPath = tempRoot.appendingPathComponent(RecordingLibrary.recordingsDirectoryName)
        try Data("not a directory".utf8).write(to: blockedPath)

        let library = RecordingLibrary(libraryRoot: tempRoot)
        XCTAssertThrowsError(
            try library.storeRecording(pcm: makePCM(), sourceTrackName: "Guitar", barCount: 1, bpm: 120)
        )
        XCTAssertTrue(library.recordings.isEmpty)
    }

    func test_storeRecording_rejectsEmptyPCM() {
        let library = RecordingLibrary(libraryRoot: tempRoot)
        XCTAssertThrowsError(
            try library.storeRecording(
                pcm: AudioInputCapturedPCM(sampleRate: 44_100, channels: []),
                sourceTrackName: "Guitar",
                barCount: 1,
                bpm: 120
            )
        ) { error in
            XCTAssertEqual(error as? RecordingLibrary.StoreError, .emptyPCM)
        }
    }

    func test_unreadableSidecar_isSkipped() throws {
        let library = RecordingLibrary(libraryRoot: tempRoot)
        _ = try library.storeRecording(pcm: makePCM(), sourceTrackName: "Mic", barCount: 1, bpm: 120)
        try Data("not json".utf8).write(
            to: library.recordingsDirectory.appendingPathComponent("broken.json")
        )

        let reloaded = RecordingLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(reloaded.recordings.count, 1, "broken sidecar must not hide valid takes")
    }

    func test_missingRoot_loadsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())")
        let library = RecordingLibrary(libraryRoot: missing)
        XCTAssertTrue(library.recordings.isEmpty)
    }
}
