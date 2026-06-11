import AVFoundation

extension AVAudioPCMBuffer {
    /// Converts to `playbackFormat` when channel count or sample rate
    /// differ; returns self when they already match, nil on conversion
    /// failure. Player nodes throw uncatchable NSExceptions when handed a
    /// buffer whose format mismatches their connection, so callers convert
    /// rather than rewire live graphs.
    func convertingForPlayback(to playbackFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.channelCount != playbackFormat.channelCount ||
              format.sampleRate != playbackFormat.sampleRate
        else {
            return self
        }

        let ratio = playbackFormat.sampleRate / max(format.sampleRate, 1)
        let convertedCapacity = AVAudioFrameCount(ceil(Double(frameLength) * ratio)) + 1
        guard let converter = AVAudioConverter(from: format, to: playbackFormat),
              let converted = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: convertedCapacity)
        else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return self
        }
        guard conversionError == nil else {
            return nil
        }
        return converted
    }
}
