import AVFoundation
import Foundation
@testable import SequencerAI

/// Assertion-side analysis for offline renders: onset detection (reusing the
/// production autoslice transient detector), grid alignment, run-to-run
/// consistency, dropout, and clipping checks.
enum RenderHarnessAnalysis {
    /// ON-BEAT tolerance. Rationale: events are sample-aligned by the
    /// harness (<=1 frame), so the error budget is entirely the detector's —
    /// `SliceAnalyzer.transientSlices` localizes onsets via 1024-frame flux
    /// windows refined by an attack-edge search with ~2 ms granularity.
    /// Empirically the synthesized clicks resolve within a few ms; 12 ms is
    /// comfortably below half a 16th-note even at 200 BPM (75 ms), so a
    /// genuinely misplaced step cannot pass.
    static let onsetToleranceSeconds = 0.012

    /// CONSISTENT tolerance: identical scenarios should produce bit-identical
    /// renders (same graph, same schedule, no live input). Assert exact
    /// equality; report the max abs sample diff when it fails.
    static let consistencyTolerance: Float = 0

    /// NO-DROPOUTS floor: RMS over the 30 ms after an expected onset must
    /// exceed -50 dBFS (0.003). Fixture clicks at the quietest scripted
    /// levels stay >= ~20x above this.
    static let dropoutRMSFloor = 0.003
    static let dropoutWindowSeconds = 0.03

    /// Clipping ceiling for scenarios that do not intend clipping.
    static let clipCeiling: Float = 0.999

    struct OnsetMatchReport {
        var expectedSeconds: [Double]
        var detectedSeconds: [Double]
        var matchedCount: Int
        var unmatchedExpectedSeconds: [Double]
        var unmatchedDetectedSeconds: [Double]
        var maxAlignmentErrorSeconds: Double
        var meanAlignmentErrorSeconds: Double

        var isOnGrid: Bool {
            unmatchedExpectedSeconds.isEmpty && unmatchedDetectedSeconds.isEmpty
        }

        var summary: String {
            String(
                format: "expected=%d detected=%d matched=%d missed=%d extra=%d maxErr=%.2fms meanErr=%.2fms",
                expectedSeconds.count,
                detectedSeconds.count,
                matchedCount,
                unmatchedExpectedSeconds.count,
                unmatchedDetectedSeconds.count,
                maxAlignmentErrorSeconds * 1_000,
                meanAlignmentErrorSeconds * 1_000
            )
        }

        var details: String {
            func list(_ values: [Double]) -> String {
                "[" + values.map { String(format: "%.1f", $0 * 1_000) }.joined(separator: ", ") + "]ms"
            }
            return summary
                + "\n expected: \(list(expectedSeconds))"
                + "\n detected: \(list(detectedSeconds))"
                + "\n missed:   \(list(unmatchedExpectedSeconds))"
                + "\n extra:    \(list(unmatchedDetectedSeconds))"
        }
    }

    /// Detects onsets in a render using the production transient detector,
    /// then refines each marker against the local energy envelope.
    ///
    /// Rationale: `SliceAnalyzer.transientSlices` is built for the autoslice
    /// product whose snap tolerance is 30 ms; its marker placement wobbles
    /// up to ~±15 ms with the phase of an onset inside its 1024-frame
    /// analysis windows (measured empirically on sample-accurate renders).
    /// The harness asserts much tighter than that, so each detected marker
    /// is snapped to the attack — the first energy rise before the local
    /// peak — which is exact on the digitally-silent backgrounds of an
    /// offline render.
    static func detectedOnsetSeconds(in result: OfflineRenderHarness.Result) throws -> [Double] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-harness-analysis-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try result.writeWAV(to: url)
        let file = try AVAudioFile(forReading: url)
        let markers = SliceAnalyzer.transientSlices(file: file, sensitivity: 1.5)

        let mono = monoMixdown(result)

        // markers[0] is always the full-range marker; the detector also
        // prepends a frame-0 marker when the first transient is later.
        var onsetFrames = markers.dropFirst().map(\.startFrame).sorted()
        // The pre-roll guarantees real audio never starts at frame 0, so a
        // frame-0 marker is always detector padding.
        onsetFrames = onsetFrames.filter { $0 > 0 }

        // Energy gate: on digitally-silent backgrounds the detector's flux
        // smoothing can produce plateau peaks whose refinement window holds
        // only zeros, so it emits the rough frame as a ghost marker (~2-3
        // windows before the true attack). Real recordings have a noise
        // floor and never hit this path; renders do. A marker with no
        // energy right after it is a ghost.
        onsetFrames = onsetFrames.filter { frame in
            let startSeconds = Double(frame) / result.sampleRate
            return result.rms(startSeconds: startSeconds, durationSeconds: 0.01) > dropoutRMSFloor / 2
        }

        onsetFrames = onsetFrames.map { refinedAttackFrame(near: $0, mono: mono, sampleRate: result.sampleRate) }
            .sorted()

        // Dedupe markers closer than 5 ms (the detector can emit a marker
        // pair around one refined transient).
        var deduped: [Int64] = []
        let minGap = Int64(result.sampleRate * 0.005)
        for frame in onsetFrames {
            if let last = deduped.last, frame - last < minGap {
                continue
            }
            deduped.append(frame)
        }
        return deduped.map { Double($0) / result.sampleRate }
    }

    private static func monoMixdown(_ result: OfflineRenderHarness.Result) -> [Float] {
        guard let first = result.channels.first else { return [] }
        guard result.channels.count > 1 else { return first }
        var mono = first
        for channel in result.channels.dropFirst() {
            for index in 0..<min(mono.count, channel.count) {
                mono[index] += channel[index]
            }
        }
        let scale = 1 / Float(result.channels.count)
        return mono.map { $0 * scale }
    }

    /// Snaps a detector marker to the attack: locate the strongest local
    /// peak within ±20 ms, then walk back over the short-window energy
    /// envelope until it falls below 5% of that peak.
    private static func refinedAttackFrame(near markerFrame: Int64, mono: [Float], sampleRate: Double) -> Int64 {
        guard !mono.isEmpty else { return markerFrame }
        let radius = Int(sampleRate * 0.020)
        let lower = max(0, Int(markerFrame) - radius)
        let upper = min(mono.count - 1, Int(markerFrame) + radius)
        guard lower < upper else { return markerFrame }

        var peakIndex = lower
        var peakMagnitude: Float = 0
        for index in lower...upper where abs(mono[index]) > peakMagnitude {
            peakMagnitude = abs(mono[index])
            peakIndex = index
        }
        guard peakMagnitude > 0 else { return markerFrame }

        // Short mean-magnitude window so single near-zero noise samples
        // inside the attack do not stop the walk early.
        let window = max(8, Int(sampleRate * 0.0005))
        func windowMagnitude(endingAt index: Int) -> Float {
            let start = max(0, index - window + 1)
            var sum: Float = 0
            for i in start...index {
                sum += abs(mono[i])
            }
            return sum / Float(index - start + 1)
        }

        let floorLevel = peakMagnitude * 0.05
        let backstop = max(0, peakIndex - Int(sampleRate * 0.040))
        var onset = peakIndex
        while onset > backstop, windowMagnitude(endingAt: onset - 1) > floorLevel {
            onset -= 1
        }
        return Int64(onset)
    }

    /// Greedy nearest-match of detected onsets to expected onsets.
    static func matchOnsets(
        expectedSeconds: [Double],
        detectedSeconds: [Double],
        tolerance: Double = onsetToleranceSeconds
    ) -> OnsetMatchReport {
        var unmatchedDetected = detectedSeconds.sorted()
        var unmatchedExpected: [Double] = []
        var errors: [Double] = []

        for expected in expectedSeconds.sorted() {
            var bestIndex: Int?
            var bestError = Double.infinity
            for (index, detected) in unmatchedDetected.enumerated() {
                let error = abs(detected - expected)
                if error < bestError {
                    bestError = error
                    bestIndex = index
                }
            }
            if let bestIndex, bestError <= tolerance {
                unmatchedDetected.remove(at: bestIndex)
                errors.append(bestError)
            } else {
                unmatchedExpected.append(expected)
            }
        }

        return OnsetMatchReport(
            expectedSeconds: expectedSeconds,
            detectedSeconds: detectedSeconds,
            matchedCount: errors.count,
            unmatchedExpectedSeconds: unmatchedExpected,
            unmatchedDetectedSeconds: unmatchedDetected,
            maxAlignmentErrorSeconds: errors.max() ?? 0,
            meanAlignmentErrorSeconds: errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
        )
    }

    /// Max absolute per-sample difference between two renders.
    static func maxAbsDifference(
        _ a: OfflineRenderHarness.Result,
        _ b: OfflineRenderHarness.Result
    ) -> Float {
        guard a.channels.count == b.channels.count else { return .infinity }
        var maxDiff: Float = 0
        for (channelA, channelB) in zip(a.channels, b.channels) {
            guard channelA.count == channelB.count else { return .infinity }
            for index in 0..<channelA.count {
                maxDiff = max(maxDiff, abs(channelA[index] - channelB[index]))
            }
        }
        return maxDiff
    }

    /// Ticks whose scheduled onsets produced no audible energy right at the
    /// expected grid position. This is the harness's strongest assertion:
    /// `tickStartFrames` is exact (the harness's own frame accounting), so a
    /// note that is silent OR late by more than `windowSeconds` fails.
    static func dropoutTicks(
        in result: OfflineRenderHarness.Result,
        expectedOnsetTicks: [Int],
        windowSeconds: Double = dropoutWindowSeconds,
        rmsFloor: Double = dropoutRMSFloor
    ) -> [Int] {
        expectedOnsetTicks.filter { tick in
            guard tick >= 0, tick < result.tickStartFrames.count else { return false }
            let startSeconds = Double(result.tickStartFrames[tick]) / result.sampleRate
            return result.rms(startSeconds: startSeconds, durationSeconds: windowSeconds) < rmsFloor
        }
    }

    /// Combined ON-BEAT + NO-DROPOUTS verdict for a scenario render.
    ///
    /// Pass criteria:
    /// - every detected onset matches an expected grid time within tolerance
    ///   (an off-grid onset is a timing bug);
    /// - every expected onset has energy within 15 ms of its grid position
    ///   (silence = dropout; energy elsewhere = late/early note).
    /// Detector misses (an expected onset with verified energy but no
    /// transient marker) are reported but do not fail: the autoslice
    /// detector's recall on dense identical material is not the engine's
    /// timing.
    struct GridVerdict {
        var report: OnsetMatchReport
        var energyMissTicks: [Int]

        var isPass: Bool {
            report.unmatchedDetectedSeconds.isEmpty && energyMissTicks.isEmpty
        }

        var details: String {
            report.details + "\n energy-miss ticks: \(energyMissTicks)"
        }
    }

    static func verifyGrid(
        result: OfflineRenderHarness.Result,
        expectedOnsetTicks: [Int],
        tolerance: Double = onsetToleranceSeconds
    ) throws -> GridVerdict {
        let report = matchOnsets(
            expectedSeconds: result.expectedOnsetSeconds(forTicks: expectedOnsetTicks),
            detectedSeconds: try detectedOnsetSeconds(in: result),
            tolerance: tolerance
        )
        let energyMisses = dropoutTicks(
            in: result,
            expectedOnsetTicks: expectedOnsetTicks,
            windowSeconds: 0.015
        )
        return GridVerdict(report: report, energyMissTicks: energyMisses)
    }
}
