import XCTest
import AVFoundation
@testable import SequencerAI

final class WaveformDownsamplerTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeTestWAV(to: tempURL, durationSeconds: 0.2, amplitude: 0.5)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func writeTestWAV(to url: URL, durationSeconds: Double, amplitude: Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(durationSeconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            data[i] = amplitude * sinf(2 * .pi * 440.0 * Float(i) / Float(format.sampleRate))
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    func test_bucketCountIsRespected() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 8)
        XCTAssertEqual(buckets.count, 8)
    }

    func test_bucketsAreNonNegativeAndBounded() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 32)
        for (i, v) in buckets.enumerated() {
            XCTAssertGreaterThanOrEqual(v, 0, "bucket \(i) must be non-negative")
            XCTAssertLessThanOrEqual(v, 1, "bucket \(i) must be <= 1")
        }
    }

    func test_sineWave_producesNonZeroBuckets() {
        let buckets = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        let nonZero = buckets.filter { $0 > 0.1 }.count
        XCTAssertGreaterThan(nonZero, 10, "at least most buckets of a 0.5-amplitude sine should be > 0.1")
    }

    func test_cacheHitReturnsSameArray() {
        let first = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        let second = WaveformDownsampler.downsample(url: tempURL, bucketCount: 16)
        XCTAssertEqual(first, second)
    }

    func test_missingFile_returnsZeros() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let buckets = WaveformDownsampler.downsample(url: missing, bucketCount: 10)
        XCTAssertEqual(buckets, Array(repeating: 0, count: 10))
    }
}
