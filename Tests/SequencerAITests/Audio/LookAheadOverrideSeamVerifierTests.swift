import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER (prosecution reproduction — NOT a frozen rail).
///
/// Prosecutor claim (P3 GATE C): `LookAheadSchedulingTests`'
/// `test_engineStamp_absorbsWorstCaseLateDispatch_viaOverrideSeam_GATE`
/// installs `scheduledAudioTimeOverrideForTesting` and its docstring claims it
/// asserts "the engine routed at least one stamp through the override so the
/// integration is real, not bypassed" — but the body ends with
/// `_ = stampedMusicalSeconds` and asserts NOTHING about the override. The only
/// call it makes (`leadStampedAudioTime`) does not delegate to the override seam
/// (`LookAheadScheduling.swift:108` calls `audioMasterClock.audioTime(...)`
/// directly, bypassing `scheduledAudioTime(for:)`/the override). So the named
/// `scheduledAudioTimeOverride` seam is never exercised by the rail.
///
/// These tests REPRODUCE the deficiency: they mirror GATE C's exact setup and
/// assert the property GATE C only *claims* — that the override is invoked. The
/// first test FAILS on the shipped code (override never fired → claim REAL). The
/// fix routes `leadStampedAudioTime` through `scheduledAudioTime(for:)`, after
/// which the override fires and both tests pass.
final class LookAheadOverrideSeamVerifierTests: XCTestCase {

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: libraryRoot.appendingPathComponent("kick"),
            withIntermediateDirectories: true
        )
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frameCount = AVAudioFrameCount(48_000 * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let file = try AVAudioFile(
            forWriting: libraryRoot.appendingPathComponent("kick/test-kick.wav"),
            settings: format.settings
        )
        try file.write(from: buffer)
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func makeController() throws -> EngineController {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [],
            layers: layers,
            patternBanks: [],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            sampleEngine: nil,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)
        return controller
    }

    /// REPRODUCTION: mirrors GATE C exactly — install a recording override, call
    /// `leadStampedAudioTime`, then assert the override fired. GATE C never makes
    /// this assertion; on the shipped code the override is NEVER invoked because
    /// `leadStampedAudioTime` reads `audioMasterClock` directly. So this fails
    /// pre-fix → the prosecutor's claim that "the seam is not actually exercised
    /// by any frozen rail" is REAL.
    func test_leadStampedAudioTime_routesThroughOverrideSeam() throws {
        let controller = try makeController()
        let clock = controller.audioMasterClock

        var stampedMusicalSeconds: [TimeInterval] = []
        controller.scheduledAudioTimeOverrideForTesting = { musicalSeconds in
            stampedMusicalSeconds.append(musicalSeconds)
            return clock.audioTime(atMusicalSeconds: max(0, musicalSeconds))
        }
        defer { controller.scheduledAudioTimeOverrideForTesting = nil }

        let m: TimeInterval = 1.0
        let dueSeconds = AVAudioTime.seconds(forHostTime: clock.audioTime(atMusicalSeconds: m).hostTime)
        let worstCaseNow = dueSeconds - 0.001

        _ = controller.leadStampedAudioTime(forMusicalSeconds: m, dispatchNow: worstCaseNow)

        XCTAssertFalse(
            stampedMusicalSeconds.isEmpty,
            "GATE C claims the engine 'routed at least one stamp through the override so the integration " +
            "is real, not bypassed', but leadStampedAudioTime bypasses scheduledAudioTime(for:) and reads " +
            "audioMasterClock directly — the scheduledAudioTimeOverride seam named in the mandate is never " +
            "exercised by the frozen rail."
        )
    }

    /// Once the seam is wired, the override's returned stamp must be the one the
    /// caller gets back (i.e. the override genuinely intercepts, not just records).
    /// This protects against a fix that calls the override only for its
    /// side-effect while still returning a directly-computed stamp.
    func test_overrideSeam_returnValueIsHonoured() throws {
        let controller = try makeController()
        let clock = controller.audioMasterClock

        // A sentinel stamp the override returns; the real converter never produces
        // this value for m=1.0, so seeing it back proves the override intercepted.
        let sentinel = clock.audioTime(atMusicalSeconds: 7.5)
        controller.scheduledAudioTimeOverrideForTesting = { _ in sentinel }
        defer { controller.scheduledAudioTimeOverrideForTesting = nil }

        let result = controller.leadStampedAudioTime(forMusicalSeconds: 1.0, dispatchNow: 0.9)
        XCTAssertEqual(
            try XCTUnwrap(result).hostTime, sentinel.hostTime,
            "with the override installed, leadStampedAudioTime must return the override's stamp — the seam " +
            "must actually intercept the conversion, not merely observe it."
        )
    }
}
