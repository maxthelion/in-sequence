import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER work-product (NOT a frozen rail) for the P3 prosecutor charge:
///
///   "P3 origin-shift introduces an unguarded ~100ms playback-latency change the
///    offline frame-accuracy rail cannot see. captureOrigin(...,leadSeconds:)
///    shifts BOTH originHostSeconds and originSampleTime forward by leadSeconds
///    (AudioMasterClock.swift:154-155 and the upgrade 286-287)... Any sign error,
///    double-application, or asymmetric host-vs-sample shift in the lead would be
///    invisible to the deterministic suite."
///
/// This file reproduces-or-kills that charge by DRIVING THE REAL render-derived
/// `captureOrigin(..., leadSeconds:)` path (a non-nil renderPositionProvider —
/// the LIVE branch the offline path never takes) and asserting the two facets the
/// prosecutor names:
///
///  1. The host and sample origins shift by the SAME musical lead (symmetry):
///     under the live lead, `sampleTime(atMusicalSeconds:)` (frame view) must equal
///     the host→frame mapping `capturedOriginCorrelation().frame(forHostSeconds:)`
///     of `hostSeconds(atMusicalSeconds:)`. A sign error, double-application, OR an
///     asymmetric host-vs-sample shift all break this equality.
///
///  2. The lead is applied ONCE with the correct sign and magnitude: the absolute
///     stamp equals `renderHost + lead + m` (host) and `renderFrame + lead*sr + m*sr`
///     (frame).
///
/// These run the render-derived branch (`captureOrigin` lines 152-156) AND the
/// fallback→render upgrade (lines 278-290), which `LookAheadOriginShiftGuardTests`
/// only partially covers (its render-upgrade case checks `audioTime` host but never
/// `sampleTime` frame; its knife-edge case uses the nil/fallback branch so the
/// frame-shift line 154 is never exercised). This closes that observation.
final class LookAheadLeadSymmetryVerifierTests: XCTestCase {

    private static let specLeadSeconds: TimeInterval = 0.100
    private static let sampleRate: Double = 48_000

    /// LIVE render-derived branch: captureOrigin with a real render position and
    /// the locked lead. Host and sample origins must shift by the SAME musical
    /// lead — `sampleTime(m)` (frame) must equal the correlation's host→frame map
    /// of `hostSeconds(m)`. Asymmetric/sign/double application breaks this.
    func test_renderDerivedCaptureOrigin_hostAndSampleShiftSymmetrically() throws {
        let renderFrame: AVAudioFramePosition = 12_345
        let renderHostSeconds: TimeInterval = 5_000.0
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: {
            (sampleTime: renderFrame,
             hostTime: AVAudioTime.hostTime(forSeconds: renderHostSeconds),
             sampleRate: Self.sampleRate)
        })

        clock.captureOrigin(fallbackHostSeconds: 0, leadSeconds: Self.specLeadSeconds)

        let correlation = clock.capturedOriginCorrelation()
        XCTAssertTrue(correlation.isRenderDerived, "must take the render-derived branch")

        for m in [0.0, 0.5, 1.0, 2.5, 10.0] as [TimeInterval] {
            let host = clock.hostSeconds(atMusicalSeconds: m)
            let frameView = clock.sampleTime(atMusicalSeconds: m)
            let frameViaCorrelation = correlation.frame(forHostSeconds: host)
            XCTAssertEqual(
                frameView, frameViaCorrelation,
                "m=\(m): host and sample origins must shift by the SAME lead — frame view " +
                "(\(frameView)) must equal the host→frame correlation (\(frameViaCorrelation)). " +
                "An asymmetric host-vs-sample lead shift breaks this."
            )

            // Absolute: applied ONCE, correct sign.
            XCTAssertEqual(
                host, renderHostSeconds + Self.specLeadSeconds + m, accuracy: 1e-6,
                "m=\(m): host stamp must be renderHost+lead+m (lead applied once, forward)."
            )
            let expectedFrame = renderFrame
                + AVAudioFramePosition((Self.specLeadSeconds * Self.sampleRate).rounded())
                + AVAudioFramePosition((m * Self.sampleRate).rounded())
            XCTAssertEqual(
                frameView, expectedFrame,
                "m=\(m): frame stamp must be renderFrame+lead*sr+m*sr (lead applied once, forward)."
            )
        }
    }

    /// Fallback→render UPGRADE path (lines 278-290): capture provisionally with no
    /// render position, then a render position appears. The upgrade must carry the
    /// SAME lead to BOTH host and sample origins — the guard test only checks host.
    func test_fallbackThenRenderUpgrade_sampleOriginAlsoShiftsByLead() throws {
        var position: (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)?
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })

        clock.captureOrigin(fallbackHostSeconds: 0, leadSeconds: Self.specLeadSeconds)

        let renderFrame: AVAudioFramePosition = 9_000
        let renderHostSeconds: TimeInterval = 7_000.0
        position = (
            sampleTime: renderFrame,
            hostTime: AVAudioTime.hostTime(forSeconds: renderHostSeconds),
            sampleRate: Self.sampleRate
        )

        // Trigger the upgrade and read both views.
        let correlation = clock.capturedOriginCorrelation()
        XCTAssertTrue(correlation.isRenderDerived, "upgrade must mark origin render-derived")

        let m: TimeInterval = 1.0
        let host = clock.hostSeconds(atMusicalSeconds: m)
        let frameView = clock.sampleTime(atMusicalSeconds: m)
        XCTAssertEqual(
            frameView, correlation.frame(forHostSeconds: host),
            "upgraded host and sample origins must shift by the SAME lead (symmetry)."
        )
        let expectedFrame = renderFrame
            + AVAudioFramePosition((Self.specLeadSeconds * Self.sampleRate).rounded())
            + AVAudioFramePosition((m * Self.sampleRate).rounded())
        XCTAssertEqual(
            frameView, expectedFrame,
            "upgraded sample origin must carry the lead in frames (renderFrame+lead*sr+m*sr)."
        )
    }
}
