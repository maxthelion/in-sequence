import AVFoundation
import XCTest
@testable import SequencerAI

final class SampleAssetCacheTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-asset-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryRoot.appendingPathComponent("kick", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_warmAsyncReportsLoadingThenReady() throws {
        let sample = try makeSample(fileName: "async.wav")
        let cache = SampleAssetCache()

        cache.warmAsync(samples: [sample], libraryRoot: libraryRoot, pinnedSampleIDs: [sample.id])

        XCTAssertTrue([.loading, .ready].contains(cache.readiness(sampleID: sample.id)))
        waitUntil(timeout: 2) {
            cache.readiness(sampleID: sample.id) == .ready
        }
        XCTAssertNotNil(cache.asset(sampleID: sample.id))
    }

    func test_failedWarmupReportsFailedAndDoesNotReturnAsset() {
        let sample = AudioSample(
            id: UUID(),
            name: "missing",
            fileRef: .appSupportLibrary(relativePath: "kick/missing.wav"),
            category: .kick,
            lengthSeconds: nil
        )
        let cache = SampleAssetCache()

        XCTAssertNil(cache.warm(sample: sample, libraryRoot: libraryRoot))
        if case .failed = cache.readiness(sampleID: sample.id) {
            XCTAssertNil(cache.asset(sampleID: sample.id))
        } else {
            XCTFail("Expected failed readiness, got \(cache.readiness(sampleID: sample.id))")
        }
    }

    func test_memoryBudgetRejectsSingleAssetLargerThanResidentCeiling() throws {
        let sample = try makeSample(fileName: "oversized.wav")
        let cache = SampleAssetCache(memoryBudgetBytes: 1)

        cache.retain(sampleIDs: [sample.id])
        let asset = try XCTUnwrap(cache.warm(sample: sample, libraryRoot: libraryRoot))

        XCTAssertEqual(cache.readiness(sampleID: sample.id), .ready)
        XCTAssertNil(asset.pcmBuffer)
        XCTAssertEqual(cache.currentByteSizeForTesting, 0)
    }

    func test_memoryBudgetEvictsInactiveResidentAsset() throws {
        let pinned = try makeSample(fileName: "pinned.wav")
        let inactive = try makeSample(fileName: "inactive.wav")
        let cache = SampleAssetCache(memoryBudgetBytes: 20_000)

        cache.retain(sampleIDs: [pinned.id])
        XCTAssertNotNil(cache.warm(sample: pinned, libraryRoot: libraryRoot))
        XCTAssertNil(cache.warm(sample: inactive, libraryRoot: libraryRoot))

        XCTAssertEqual(cache.readiness(sampleID: pinned.id), .ready)
        XCTAssertEqual(cache.readiness(sampleID: inactive.id), .stale)
        XCTAssertNotNil(cache.asset(sampleID: pinned.id)?.pcmBuffer)
        XCTAssertNil(cache.asset(sampleID: inactive.id))
        XCTAssertLessThanOrEqual(cache.currentByteSizeForTesting, 20_000)
    }

    func test_memoryBudgetDemotesPinnedWorkingSetWithoutUnboundedGrowth() throws {
        let first = try makeSample(fileName: "first-pinned.wav")
        let second = try makeSample(fileName: "second-pinned.wav")
        let cache = SampleAssetCache(memoryBudgetBytes: 20_000)

        cache.retain(sampleIDs: [first.id, second.id])
        XCTAssertNotNil(cache.warm(sample: first, libraryRoot: libraryRoot))
        XCTAssertNotNil(cache.warm(sample: second, libraryRoot: libraryRoot))

        let residentCount = [first, second].compactMap {
            cache.asset(sampleID: $0.id)?.pcmBuffer
        }.count
        XCTAssertEqual(residentCount, 1)
        XCTAssertEqual(cache.readiness(sampleID: first.id), .ready)
        XCTAssertEqual(cache.readiness(sampleID: second.id), .ready)
        XCTAssertLessThanOrEqual(cache.currentByteSizeForTesting, 20_000)
    }

    private func makeSample(fileName: String) throws -> AudioSample {
        let url = libraryRoot.appendingPathComponent("kick", isDirectory: true).appendingPathComponent(fileName)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frames = AVAudioFrameCount(4_800)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return AudioSample(
            id: UUID(),
            name: (fileName as NSString).deletingPathExtension,
            fileRef: .appSupportLibrary(relativePath: "kick/\(fileName)"),
            category: .kick,
            lengthSeconds: 0.1,
            lengthFrames: Int64(frames),
            sampleRate: 48_000
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition())
    }
}
