import AVFoundation
import XCTest
@testable import SequencerAI

final class SliceAnalyzerTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writePulseWAV(to: tempURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func test_gridSlices_includeWholeSampleAndEqualUserRegions() throws {
        let file = try AVAudioFile(forReading: tempURL)

        let slices = SliceAnalyzer.gridSlices(file: file, divisions: 4)

        XCTAssertEqual(slices.count, 5)
        XCTAssertEqual(slices[0].startFrame, 0)
        XCTAssertEqual(slices[0].endFrame, file.length)
        XCTAssertEqual(slices[1].startFrame, 0)
        XCTAssertEqual(slices[1].endFrame, file.length / 4)
    }

    func test_transientSlices_alwaysIncludeWholeSample() throws {
        let file = try AVAudioFile(forReading: tempURL)

        let slices = SliceAnalyzer.transientSlices(file: file)

        XCTAssertGreaterThanOrEqual(slices.count, 1)
        XCTAssertEqual(slices[0].startFrame, 0)
        XCTAssertEqual(slices[0].endFrame, file.length)
    }

    func test_transientSlices_alignMarkersToPulseOnsets() throws {
        let file = try AVAudioFile(forReading: tempURL)

        let slices = SliceAnalyzer.transientSlices(file: file, sensitivity: 0.35)
        let starts = slices.dropFirst().map(\.startFrame)

        XCTAssertTrue(
            starts.contains { abs($0 - 11_025) <= 512 },
            "expected a marker near the second pulse onset, got \(starts)"
        )
        XCTAssertTrue(
            starts.contains { abs($0 - 22_050) <= 512 },
            "expected a marker near the third pulse onset, got \(starts)"
        )
    }

    func test_transientSlices_doNotBacktrackIntoSustainedPreviousAudio() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSustainedBedPulseWAV(to: url)
        let file = try AVAudioFile(forReading: url)

        let slices = SliceAnalyzer.transientSlices(file: file, sensitivity: 0.35)
        let starts = slices.dropFirst().map(\.startFrame)
        let target = 22_050

        guard let secondHit = starts.min(by: { abs($0 - Int64(target)) < abs($1 - Int64(target)) }) else {
            XCTFail("expected at least one transient marker")
            return
        }

        XCTAssertTrue(
            abs(secondHit - Int64(target)) <= 512,
            "expected sustained audio before a hit not to pull the marker away from \(target), got \(starts)"
        )
    }

    private func writePulseWAV(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            samples[frame] = frame % 11_025 < 400 ? 0.9 : 0.05
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func writeSustainedBedPulseWAV(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let phase = Float(frame) / Float(format.sampleRate)
            let bed = 0.22 * sinf(2 * .pi * 110 * phase)
            let firstHit = (11_025..<(11_025 + 420)).contains(frame)
            let secondHit = (22_050..<(22_050 + 420)).contains(frame)
            samples[frame] = (firstHit || secondHit) ? 0.92 : bed
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
