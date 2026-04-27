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
}
