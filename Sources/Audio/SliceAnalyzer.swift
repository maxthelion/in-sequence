import AVFoundation
import Foundation

enum SliceAnalyzer {
    static func gridSlices(file: AVAudioFile, divisions: Int) -> [SliceMarker] {
        let length = max(0, Int64(file.length))
        let count = max(1, divisions)
        var markers = [SliceMarker(id: UUID(), startFrame: 0, endFrame: length)]
        guard length > 0 else {
            return markers
        }

        for index in 0..<count {
            let start = Int64((Double(index) / Double(count)) * Double(length))
            let end = index == count - 1
                ? length
                : Int64((Double(index + 1) / Double(count)) * Double(length))
            markers.append(SliceMarker(startFrame: start, endFrame: max(start + 1, end)))
        }
        return markers
    }

    static func transientSlices(file: AVAudioFile, sensitivity: Double = 1.5) -> [SliceMarker] {
        let length = max(0, Int64(file.length))
        guard length > 0,
              let samples = monoSamples(from: file),
              !samples.isEmpty
        else {
            return [SliceMarker(startFrame: 0, endFrame: length)]
        }

        let windowSize = 1_024
        let energies = rmsWindows(samples: samples, windowSize: windowSize)
        guard energies.count > 2 else {
            return [SliceMarker(startFrame: 0, endFrame: length)]
        }

        let flux = zip(energies.dropFirst(), energies).map { current, previous in
            max(0, current - previous)
        }
        let smoothed = movingAverage(Array(flux), radius: 2)
        let mean = smoothed.reduce(0, +) / Double(max(1, smoothed.count))
        let variance = smoothed.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(max(1, smoothed.count))
        let threshold = mean + max(0, sensitivity) * sqrt(variance)
        let minDistanceFrames = max(1, Int(file.processingFormat.sampleRate * 0.05))
        var transientFrames: [Int64] = []

        for index in smoothed.indices {
            guard smoothed[index] > threshold,
                  isLocalMaximum(values: smoothed, index: index, radius: 5)
            else {
                continue
            }
            let frame = Int64((index + 1) * windowSize)
            if let last = transientFrames.last,
               frame - last < Int64(minDistanceFrames)
            {
                if smoothed[index] > smoothed[Int(max(0, last / Int64(windowSize) - 1))] {
                    transientFrames[transientFrames.count - 1] = frame
                }
            } else {
                transientFrames.append(min(max(frame, 0), length - 1))
            }
        }

        guard !transientFrames.isEmpty else {
            return [SliceMarker(startFrame: 0, endFrame: length)]
        }

        let starts = transientFrames.first == 0 ? transientFrames : [0] + transientFrames
        var markers = [SliceMarker(startFrame: 0, endFrame: length)]
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : length
            guard end - start >= Int64(minDistanceFrames) || index == starts.count - 1 else {
                continue
            }
            markers.append(SliceMarker(startFrame: start, endFrame: max(start + 1, end)))
        }

        return markers
    }

    private static func monoSamples(from file: AVAudioFile) -> [Float]? {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return nil
        }

        do {
            file.framePosition = 0
            try file.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return []
        }

        var mono = Array(repeating: Float(0), count: frameCount)
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameCount {
                mono[index] += samples[index] / Float(channelCount)
            }
        }
        return mono
    }

    private static func rmsWindows(samples: [Float], windowSize: Int) -> [Double] {
        stride(from: 0, to: samples.count, by: max(1, windowSize)).map { start in
            let end = min(samples.count, start + windowSize)
            let slice = samples[start..<end]
            guard !slice.isEmpty else { return 0 }
            let meanSquare = slice.reduce(Double(0)) { partial, sample in
                partial + Double(sample * sample)
            } / Double(slice.count)
            return sqrt(meanSquare)
        }
    }

    private static func movingAverage(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { index in
            let lower = max(values.startIndex, index - radius)
            let upper = min(values.endIndex - 1, index + radius)
            let window = values[lower...upper]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private static func isLocalMaximum(values: [Double], index: Int, radius: Int) -> Bool {
        let lower = max(values.startIndex, index - radius)
        let upper = min(values.endIndex - 1, index + radius)
        return values[lower...upper].allSatisfy { values[index] >= $0 }
    }
}
