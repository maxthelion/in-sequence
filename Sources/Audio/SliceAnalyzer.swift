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

    /// Detects onsets via a spectral-flux-style novelty function with an
    /// adaptive local threshold.
    ///
    /// `sensitivity` is the UI control (slider range ~0.15...0.75). It is
    /// mapped so that *higher* values detect *more* transients. Internally it
    /// drives three coupled parameters: the local threshold margin (how far a
    /// peak must exceed its neighbourhood), the peak-picking exclusion radius
    /// (how close two onsets may sit), and the minimum slice length. This makes
    /// the slider meaningfully change the result instead of only nudging a
    /// single global threshold.
    static func transientSlices(file: AVAudioFile, sensitivity: Double = 0.35) -> [SliceMarker] {
        let length = max(0, Int64(file.length))
        guard length > 0,
              let samples = monoSamples(from: file),
              !samples.isEmpty
        else {
            return [SliceMarker(startFrame: 0, endFrame: length)]
        }

        let sampleRate = file.processingFormat.sampleRate
        // Map the (clamped) UI sensitivity to a 0...1 "detail" amount. The UI
        // slider is 0.15...0.75; clamp defensively and re-base so the full
        // travel maps across the detail range.
        let clampedSensitivity = min(max(sensitivity, 0.05), 0.95)
        let detail = min(max((clampedSensitivity - 0.05) / 0.90, 0), 1)

        // Finer time resolution than the old 1024 non-overlapping windows:
        // a 1024-sample window with a 256-sample hop (75% overlap) localises
        // sharp onsets far better and stops a coarse window from straddling
        // (and diluting) two close hits.
        let windowSize = 1_024
        let hopSize = 256
        let energies = rmsWindows(samples: samples, windowSize: windowSize, hopSize: hopSize)
        guard energies.count > 2 else {
            return [SliceMarker(startFrame: 0, endFrame: length)]
        }

        // Spectral-flux-style novelty: positive frame-to-frame energy rise.
        let flux = zip(energies.dropFirst(), energies).map { current, previous in
            max(0, current - previous)
        }
        let smoothed = movingAverage(Array(flux), radius: 1)

        // Adaptive local threshold: a peak must exceed the local mean of the
        // novelty curve (over ~250ms) by a sensitivity-scaled margin, with a
        // small global-derived floor so silence-to-quiet rises do not trigger.
        // This is robust to a loud opening hit inflating a global mean/std and
        // then masking a quieter mid-loop transient.
        let localRadius = max(1, Int(0.250 * sampleRate / Double(hopSize)))
        let localMean = movingAverage(smoothed, radius: localRadius)
        let globalMean = smoothed.reduce(0, +) / Double(max(1, smoothed.count))
        // detail 0 -> ~2.2x local mean required; detail 1 -> ~1.05x. Higher
        // sensitivity => lower bar => more onsets.
        let marginMultiplier = 2.2 - 1.15 * detail
        let globalFloor = globalMean * (0.6 - 0.45 * detail)

        // Peak-picking exclusion radius (in hops): how close two detected
        // onsets may sit. At high sensitivity this shrinks to ~12ms so genuinely
        // close transients both survive; at low sensitivity it widens to ~90ms.
        let pickRadiusSeconds = 0.012 + (1 - detail) * 0.078
        let pickRadius = max(1, Int(pickRadiusSeconds * sampleRate / Double(hopSize)))

        // Minimum slice length follows the same control: down to ~20ms at full
        // sensitivity (catches fast double-hits) up to ~70ms at low sensitivity.
        let minSliceSeconds = 0.020 + (1 - detail) * 0.050
        let minDistanceFrames = max(1, Int(sampleRate * minSliceSeconds))

        var transientFrames: [Int64] = []
        var transientScores: [Double] = []

        for index in smoothed.indices {
            let localThreshold = max(localMean[index] * marginMultiplier, globalFloor)
            guard smoothed[index] > localThreshold,
                  isLocalMaximum(values: smoothed, index: index, radius: pickRadius)
            else {
                continue
            }
            // Centre of this window in frames (window start + half window).
            let roughFrame = Int64(index * hopSize + windowSize / 2)
            let frame = refinedTransientFrame(
                around: roughFrame,
                samples: samples,
                sampleRate: sampleRate,
                length: length
            )
            if let last = transientFrames.last,
               frame - last < Int64(minDistanceFrames)
            {
                if let lastScore = transientScores.last,
                   smoothed[index] > lastScore {
                    transientFrames[transientFrames.count - 1] = frame
                    transientScores[transientScores.count - 1] = smoothed[index]
                }
            } else {
                transientFrames.append(min(max(frame, 0), length - 1))
                transientScores.append(smoothed[index])
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

    private static func refinedTransientFrame(
        around roughFrame: Int64,
        samples: [Float],
        sampleRate: Double,
        length: Int64
    ) -> Int64 {
        guard !samples.isEmpty else {
            return min(max(roughFrame, 0), max(0, length - 1))
        }

        let sampleCount = samples.count
        let center = min(max(Int(roughFrame), 0), sampleCount - 1)
        let lookBack = min(center, max(1, Int(sampleRate * 0.03)))
        let lookAhead = min(sampleCount - 1, center + max(1, Int(sampleRate * 0.04)))
        let lower = max(0, center - lookBack)
        let upper = max(lower, lookAhead)

        var peakIndex = lower
        var peakMagnitude = abs(samples[lower])
        for index in lower...upper {
            let magnitude = abs(samples[index])
            if magnitude > peakMagnitude {
                peakMagnitude = magnitude
                peakIndex = index
            }
        }

        guard peakMagnitude > 0 else {
            return min(max(roughFrame, 0), max(0, length - 1))
        }

        if let attackEdge = strongestAttackEdge(
            before: peakIndex,
            lowerBound: lower,
            samples: samples,
            sampleRate: sampleRate,
            peakMagnitude: peakMagnitude
        ) {
            return min(max(Int64(attackEdge), 0), max(0, length - 1))
        }

        let threshold = max(peakMagnitude * 0.2, 0.015)
        let maxBacktrack = max(1, Int(sampleRate * 0.008))
        let boundedLower = max(lower, peakIndex - maxBacktrack)
        var onset = peakIndex
        while onset > boundedLower, abs(samples[onset - 1]) > threshold {
            onset -= 1
        }
        return min(max(Int64(onset), 0), max(0, length - 1))
    }

    private static func strongestAttackEdge(
        before peakIndex: Int,
        lowerBound: Int,
        samples: [Float],
        sampleRate: Double,
        peakMagnitude: Float
    ) -> Int? {
        guard peakIndex > lowerBound else {
            return nil
        }

        let lag = max(8, Int(sampleRate * 0.002))
        let radius = max(4, lag / 2)
        let searchStart = max(lowerBound + lag, peakIndex - max(lag, Int(sampleRate * 0.025)))
        guard searchStart < peakIndex else {
            return nil
        }

        var bestIndex = searchStart
        var bestRise: Float = 0
        for index in searchStart...peakIndex {
            let before = meanAbsoluteMagnitude(samples, center: index - lag, radius: radius)
            let after = meanAbsoluteMagnitude(samples, center: index, radius: radius)
            let rise = after - before
            if rise > bestRise {
                bestRise = rise
                bestIndex = index
            }
        }

        guard bestRise > max(0.004, peakMagnitude * 0.035) else {
            return nil
        }

        let preEdgeFloor = meanAbsoluteMagnitude(samples, center: max(lowerBound, bestIndex - lag), radius: radius)
        let onsetThreshold = preEdgeFloor + (bestRise * 0.2)
        var onset = bestIndex
        while onset > lowerBound,
              meanAbsoluteMagnitude(samples, center: onset - 1, radius: radius) > onsetThreshold
        {
            onset -= 1
        }
        return onset
    }

    private static func meanAbsoluteMagnitude(_ samples: [Float], center: Int, radius: Int) -> Float {
        guard !samples.isEmpty else {
            return 0
        }

        let lower = max(0, center - radius)
        let upper = min(samples.count - 1, center + radius)
        guard lower <= upper else {
            return 0
        }

        var sum: Float = 0
        for index in lower...upper {
            sum += abs(samples[index])
        }
        return sum / Float(upper - lower + 1)
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

    /// RMS energy per analysis window. `hopSize` controls window overlap; when
    /// omitted it defaults to a non-overlapping (`hopSize == windowSize`) scan.
    private static func rmsWindows(samples: [Float], windowSize: Int, hopSize: Int? = nil) -> [Double] {
        let hop = max(1, hopSize ?? windowSize)
        return stride(from: 0, to: samples.count, by: hop).map { start in
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
