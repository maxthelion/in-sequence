import AVFoundation
import XCTest
@testable import SequencerAI

final class MasterRenderTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("master-render-\(UUID().uuidString).wav")
    }

    func test_startStop_roundTripCreatesReadableFile() throws {
        let graph = MainAudioGraph()
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(graph.startMasterRender(to: url))
        XCTAssertTrue(graph.isMasterRenderActive)
        XCTAssertFalse(graph.startMasterRender(to: tmpURL()), "second concurrent render must be refused")

        // Push synthetic audio through the write path (no running engine).
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        buffer.frameLength = 512
        for ch in 0..<2 {
            let samples = buffer.floatChannelData![ch]
            for i in 0..<512 { samples[i] = sinf(Float(i) * 0.1) * 0.5 }
        }
        graph.writeMasterRenderBufferForTesting(buffer)
        graph.writeMasterRenderBufferForTesting(buffer)

        XCTAssertEqual(graph.stopMasterRender(), url)
        XCTAssertFalse(graph.isMasterRenderActive)
        XCTAssertNil(graph.stopMasterRender())

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 1024)
        // Content survived: non-silent RMS.
        let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024)!
        try file.read(into: read)
        var sum: Float = 0
        let data = read.floatChannelData![0]
        for i in 0..<Int(read.frameLength) { sum += data[i] * data[i] }
        XCTAssertGreaterThan(sum / Float(read.frameLength), 0.01)
    }

    func test_writeWithoutActiveRender_isNoOp() {
        let graph = MainAudioGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        graph.writeMasterRenderBufferForTesting(buffer)
        XCTAssertFalse(graph.isMasterRenderActive)
    }
}
