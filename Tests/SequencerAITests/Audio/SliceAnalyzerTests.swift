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

    func test_transientSlices_detectBothOfTwoCloseTransients() throws {
        // Two strong hits 70ms apart sitting after a louder opening hit. The old
        // detector (wide local-maximum window + global mean/std threshold) would
        // merge or mask the second of the close pair, so the opening slice ran
        // past a legitimate onset. With sensitivity raised, both must survive.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCloseTransientPairWAV(to: url)
        let file = try AVAudioFile(forReading: url)

        let slices = SliceAnalyzer.transientSlices(file: file, sensitivity: 0.6)
        let starts = slices.dropFirst().map(\.startFrame)

        // The two close hits sit at ~13230 and ~16317 frames (70ms apart @44.1k).
        let firstClose: Int64 = 13_230
        let secondClose: Int64 = 16_317
        XCTAssertTrue(
            starts.contains { abs($0 - firstClose) <= 700 },
            "expected a marker near the first close hit (\(firstClose)), got \(starts)"
        )
        XCTAssertTrue(
            starts.contains { abs($0 - secondClose) <= 700 },
            "expected a marker near the second close hit (\(secondClose)), got \(starts)"
        )
    }

    func test_transientSlices_sensitivitySplitsACloseTransientPair() throws {
        // Direct regression for the reported bug: two legitimate hits sit ~45ms
        // apart. At the default/low sensitivity they collapse into one onset (so
        // the preceding slice runs past the second hit); raising sensitivity must
        // resolve them as two distinct onsets. This proves the slider is
        // meaningfully responsive and that close transients are no longer masked.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeAdjacentPairWAV(to: url)
        let file = try AVAudioFile(forReading: url)

        func onsetsNearPair(_ sensitivity: Double) -> Int {
            SliceAnalyzer.transientSlices(file: file, sensitivity: sensitivity)
                .dropFirst()
                .map(\.startFrame)
                .filter { abs($0 - 21_000) < 4_000 }
                .count
        }

        let low = onsetsNearPair(0.15)
        let high = onsetsNearPair(0.75)

        XCTAssertGreaterThanOrEqual(high, low, "raising sensitivity must not lose onsets (low=\(low), high=\(high))")
        XCTAssertGreaterThanOrEqual(high, 2, "highest sensitivity should resolve the close pair as two onsets, got \(high)")
    }

    private func writeAdjacentPairWAV(to url: URL) throws {
        // A loud opener, then two equal hits 45ms apart.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        let onsets: [(start: Int, length: Int, gain: Float)] = [
            (0, 600, 1.0),
            (20_000, 300, 0.8),
            (21_984, 300, 0.8)
        ]
        for frame in 0..<Int(frameCount) {
            var value: Float = 0.02
            for onset in onsets where (onset.start..<(onset.start + onset.length)).contains(frame) {
                let local = Float(frame - onset.start) / Float(onset.length)
                value = onset.gain * (1 - local)
            }
            samples[frame] = value
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

    private func writeCloseTransientPairWAV(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        // Onsets: a loud opener at 0, then two close hits 70ms apart.
        let onsets: [(start: Int, length: Int, gain: Float)] = [
            (0, 600, 1.0),
            (13_230, 420, 0.85),
            (16_317, 420, 0.85)
        ]
        for frame in 0..<Int(frameCount) {
            var value: Float = 0.02
            for onset in onsets where (onset.start..<(onset.start + onset.length)).contains(frame) {
                // Decaying burst so each hit has a clear attack edge.
                let local = Float(frame - onset.start) / Float(onset.length)
                value = onset.gain * (1 - local)
            }
            samples[frame] = value
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
