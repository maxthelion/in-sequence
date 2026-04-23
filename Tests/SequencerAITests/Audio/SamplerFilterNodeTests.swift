import XCTest
import AVFoundation
@testable import SequencerAI

@MainActor
final class SamplerFilterNodeTests: XCTestCase {

    // MARK: - Helpers

    /// Generate a single-frequency sine wave PCM buffer.
    private func sineBuffer(frequencyHz: Double, durationSec: Double, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(durationSec * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            data[i] = Float(sin(2 * Double.pi * frequencyHz * t))
        }
        return buffer
    }

    /// Compute RMS of a PCM buffer's first channel.
    private func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Double = 0
        for i in 0..<Int(buffer.frameLength) {
            let v = Double(data[i])
            sum += v * v
        }
        return sqrt(sum / Double(buffer.frameLength))
    }

    /// Convert RMS ratio to dB.
    private func rmsToDb(_ rms1: Double, vs rms2: Double) -> Double {
        guard rms2 > 0 else { return -200 }
        return 20 * log10(rms1 / rms2)
    }

    /// Run a signal through an `AVAudioEngine` containing only the filter node
    /// and return the rendered buffer.
    ///
    /// Uses offline rendering (manualRenderingMode) so no hardware is required.
    private func renderThroughFilter(
        _ filterNode: SamplerFilterNode,
        input: AVAudioPCMBuffer
    ) throws -> AVAudioPCMBuffer {
        let engine = AVAudioEngine()
        let format = input.format
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(filterNode.avNode)

        engine.connect(player, to: filterNode.avNode, format: format)
        engine.connect(filterNode.avNode, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: input.frameLength
        )
        try engine.start()
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: input.frameLength)!
        try engine.renderOffline(input.frameLength, to: output)
        engine.stop()
        return output
    }

    private func renderWithoutFilter(input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let engine = AVAudioEngine()
        let format = input.format
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: input.frameLength
        )
        try engine.start()
        player.scheduleBuffer(input, completionHandler: nil)
        player.play()

        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: input.frameLength)!
        try engine.renderOffline(input.frameLength, to: output)
        engine.stop()
        return output
    }

    // MARK: - Bypass transparency

    func test_defaultSettings_1kHzSinePassesThrough() throws {
        let filter = SamplerFilterNode()
        let input = sineBuffer(frequencyHz: 1_000, durationSec: 0.1)
        let baseline = try renderWithoutFilter(input: input)
        let output = try renderThroughFilter(filter, input: input)

        let inRMS = rms(baseline)
        let outRMS = rms(output)
        guard inRMS > 0 else { XCTFail("Input silence"); return }

        let deltaDb = rmsToDb(outRMS, vs: inRMS)
        // Compare against the same offline-render path without a filter node so the
        // assertion measures filter coloration rather than engine/render gain staging.
        XCTAssertLessThanOrEqual(abs(deltaDb), 0.5,
            "Default filter should pass 1 kHz within ±0.5 dB, got \(deltaDb) dB")
    }

    // MARK: - Highpass attenuation

    func test_highpass_at10kHz_attenuates1kHz() throws {
        let filter = SamplerFilterNode()
        filter.setType(.highpass)
        filter.setCutoff(hz: 10_000)

        let input = sineBuffer(frequencyHz: 1_000, durationSec: 0.1)
        let inRMS = rms(input)
        let output = try renderThroughFilter(filter, input: input)
        let outRMS = rms(output)

        guard inRMS > 0 else { XCTFail("Input silence"); return }
        let attenDb = rmsToDb(outRMS, vs: inRMS)
        // 1 kHz should be attenuated by more than 20 dB at HP 10 kHz.
        XCTAssertLessThanOrEqual(attenDb, -20,
            "HP at 10 kHz should attenuate 1 kHz by >20 dB, got \(attenDb) dB")
    }

    // MARK: - Lowpass attenuation

    func test_lowpass_at500Hz_attenuates5kHz() throws {
        let filter = SamplerFilterNode()
        filter.setType(.lowpass)
        filter.setCutoff(hz: 500)

        let input = sineBuffer(frequencyHz: 5_000, durationSec: 0.1)
        let inRMS = rms(input)
        let output = try renderThroughFilter(filter, input: input)
        let outRMS = rms(output)

        guard inRMS > 0 else { XCTFail("Input silence"); return }
        let attenDb = rmsToDb(outRMS, vs: inRMS)
        // 5 kHz should be attenuated by more than 15 dB at LP 500 Hz.
        XCTAssertLessThanOrEqual(attenDb, -15,
            "LP at 500 Hz should attenuate 5 kHz by >15 dB, got \(attenDb) dB")
    }

    // MARK: - setType updates band filterType

    func test_setType_updatesFilterTypeOnBand() {
        let filter = SamplerFilterNode()
        filter.setType(.lowpass)
        XCTAssertEqual(filter.avNode.bands[0].filterType, .lowPass)

        filter.setType(.highpass)
        XCTAssertEqual(filter.avNode.bands[0].filterType, .highPass)

        filter.setType(.bandpass)
        XCTAssertEqual(filter.avNode.bands[0].filterType, .bandPass)

        filter.setType(.notch)
        XCTAssertEqual(filter.avNode.bands[0].filterType, .parametric)
    }

    // MARK: - Setter methods don't allocate new bands

    func test_setters_doNotReallocateBands() {
        let filter = SamplerFilterNode()
        let bandsBefore = filter.avNode.bands
        filter.setType(.highpass)
        filter.setCutoff(hz: 1000)
        filter.setResonance(0.5)
        filter.setDrive(0.3)
        filter.setPoles(.four)
        let bandsAfter = filter.avNode.bands
        XCTAssertEqual(bandsBefore.count, bandsAfter.count, "Band count must not change after setter calls")
        XCTAssertEqual(bandsAfter.count, 1)
    }

    // MARK: - apply() sets all five parameters

    func test_apply_setsAllParameters() {
        let filter = SamplerFilterNode()
        let settings = SamplerFilterSettings(
            type: .highpass,
            poles: .four,
            cutoffHz: 2000,
            resonance: 0,
            drive: 0
        )
        filter.apply(settings)
        XCTAssertEqual(filter.avNode.bands[0].filterType, .highPass)
        XCTAssertEqual(filter.avNode.bands[0].frequency, 2000, accuracy: 1)
    }

    // MARK: - Cutoff clamping

    func test_setCutoff_clampsToValidRange() {
        let filter = SamplerFilterNode()
        filter.setCutoff(hz: -100)
        XCTAssertEqual(filter.avNode.bands[0].frequency, 20, accuracy: 1)

        filter.setCutoff(hz: 999_999)
        XCTAssertEqual(filter.avNode.bands[0].frequency, 20_000, accuracy: 1)
    }
}
