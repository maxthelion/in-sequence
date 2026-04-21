import Foundation
import AVFoundation

enum WaveformDownsampler {
    private static let cache = NSCache<NSURL, NSArray>()

    /// Reads the audio file at `url`, computes peak absolute magnitude per bucket
    /// (mono sum across channels), returns `bucketCount` floats in `[0, 1]`.
    /// Cached by URL; repeat calls hit cache.
    static func downsample(url: URL, bucketCount: Int = 64) -> [Float] {
        precondition(bucketCount > 0, "bucketCount must be positive")

        if let cached = cache.object(forKey: url as NSURL) as? [NSNumber] {
            return cached.map { $0.floatValue }
        }

        let buckets = computeBuckets(url: url, bucketCount: bucketCount)
        cache.setObject(buckets.map { NSNumber(value: $0) } as NSArray, forKey: url as NSURL)
        return buckets
    }

    private static func computeBuckets(url: URL, bucketCount: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0, count: bucketCount)
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return Array(repeating: 0, count: bucketCount)
        }

        do {
            try file.read(into: buffer)
        } catch {
            return Array(repeating: 0, count: bucketCount)
        }

        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: bucketCount)
        }

        let channels = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        let framesPerBucket = max(1, totalFrames / bucketCount)

        var out = Array<Float>(repeating: 0, count: bucketCount)
        for bucket in 0..<bucketCount {
            let start = bucket * framesPerBucket
            let end = min(start + framesPerBucket, totalFrames)
            guard start < end else { break }

            var peak: Float = 0
            for frame in start..<end {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += abs(channelData[channel][frame])
                }
                let mono = sum / Float(max(channels, 1))
                if mono > peak { peak = mono }
            }
            out[bucket] = min(peak, 1.0)
        }
        return out
    }
}
