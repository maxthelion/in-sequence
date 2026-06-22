import AVFoundation
import SwiftUI
import XCTest
@testable import SequencerAI

/// Regression coverage for the Slice Source modal bug where changing the
/// sensitivity and hitting Apply left the slice set at "0 slices".
///
/// The modal's Apply path is:
///   analyzedSliceSet(sample:)  -> builds a SliceSet from SliceAnalyzer
///   applyAnalysis(sample:)     -> session.applySlicerAnalysis(...)
///
/// These tests exercise the document/store half of that path directly (no
/// CoreAudio boot — `EngineController(client: nil, endpoint: nil)`), asserting
/// that detection + apply takes the resolved slice set from 0 user slices to
/// N > 0 and that the clip gains active trigger steps.
@MainActor
final class SlicerApplyAnalysisCreatesSlicesTests: XCTestCase {
    private var sampleURL: URL!

    override func setUpWithError() throws {
        sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writePulseWAV(to: sampleURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sampleURL)
    }

    func test_applyAnalysis_createsSlicesFromZero() throws {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        // 1. A slice track with a loaded sample but only the whole-sample marker
        //    — exactly the "0 slices" starting state the user sees on open.
        session.appendTrack(trackType: .slice)
        let trackID = session.store.selectedTrackID
        let file = try AVAudioFile(forReading: sampleURL)
        let sampleLengthFrames = file.length
        let sampleID = UUID()

        let initialSet = SliceSet(
            sampleID: sampleID,
            markers: [SliceMarker(startFrame: 0, endFrame: sampleLengthFrames)],
            mode: .manual
        )
        session.setSlicerDestination(sliceSet: initialSet, settings: .default, for: trackID)

        XCTAssertEqual(
            resolvedUserSliceCount(session: session, trackID: trackID),
            0,
            "fixture should start with 0 user slices"
        )

        // 2. Run detection the way the modal does: transient analysis at a
        //    chosen sensitivity, preserving the existing whole-sample marker id.
        var detected = makeDetectedSet(
            file: file,
            sampleID: sampleID,
            sensitivity: 0.35,
            bars: 2
        )
        if let current = resolvedSliceSet(session: session, trackID: trackID) {
            detected.id = current.id
        }

        XCTAssertGreaterThan(
            detected.userSliceCount,
            0,
            "transient detection should propose at least one user slice"
        )

        // 3. Apply — the same call the Apply button makes.
        session.applySlicerAnalysis(
            sliceSet: detected,
            sampleLengthFrames: sampleLengthFrames,
            clipLengthSteps: 2 * 16,
            for: trackID
        )

        // 4. The committed slice set now has N > 0 user slices.
        let finalCount = resolvedUserSliceCount(session: session, trackID: trackID)
        XCTAssertGreaterThan(
            finalCount,
            0,
            "Apply must create slices (0 -> N>0); got \(finalCount)"
        )

        // 5. The clip the slicer plays now has active trigger steps.
        let activeSteps = activeTriggerStepCount(session: session, trackID: trackID)
        XCTAssertGreaterThan(
            activeSteps,
            0,
            "Apply must populate trigger steps for the created slices"
        )
    }

    // MARK: - Helpers mirroring SliceTrackWorkspaceView.analyzedSliceSet

    private func makeDetectedSet(
        file: AVAudioFile,
        sampleID: UUID,
        sensitivity: Double,
        bars: Int
    ) -> SliceSet {
        let transientMarkers = SliceAnalyzer.transientSlices(file: file, sensitivity: sensitivity)
        let markers = transientMarkers.count > 1
            ? transientMarkers
            : SliceAnalyzer.gridSlices(file: file, divisions: max(1, bars * 16))
        var set = SliceSet(sampleID: sampleID, markers: markers, mode: .transient, bars: Double(bars))
        set.normalize(sampleLengthFrames: file.length)
        return set
    }

    private func resolvedSliceSet(
        session: SequencerDocumentSession,
        trackID: UUID
    ) -> SliceSet? {
        guard case let .slicer(sliceSetID, _) = session.store.resolvedDestination(for: trackID) else {
            return nil
        }
        return session.store.sliceSet(id: sliceSetID)
    }

    private func resolvedUserSliceCount(
        session: SequencerDocumentSession,
        trackID: UUID
    ) -> Int {
        resolvedSliceSet(session: session, trackID: trackID)?.userSliceCount ?? 0
    }

    private func activeTriggerStepCount(
        session: SequencerDocumentSession,
        trackID: UUID
    ) -> Int {
        let pattern = session.store.selectedPattern(for: trackID)
        guard let clipID = pattern.sourceRef.clipID,
              let clip = session.store.clipEntry(id: clipID),
              case let .sliceTriggers(stepPattern, _, _, _) = clip.content
        else {
            return 0
        }
        return stepPattern.filter { $0 }.count
    }

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
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
