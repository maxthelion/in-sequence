import AVFoundation
import XCTest

@testable import SequencerAI

/// End-to-end reproduction tests for the clip history live-capture pipeline:
/// generator plays → engine appends to the rolling capture buffer →
/// `ClipHistoryTransferViewModel` surfaces notes in the live preview.
final class ClipHistoryLiveCaptureTests: XCTestCase {
    private func makeGeneratorDocument() -> (Project, StepSequenceTrack) {
        let track = StepSequenceTrack(
            id: UUID(uuidString: "AAAA1111-2222-3333-4444-555566667777") ?? UUID(),
            name: "Poly 2",
            pitches: [48],
            stepPattern: [false, false, false, false],
            stepAccents: [false, false, false, false],
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            velocity: 80,
            gateLength: 2
        )
        let generator = GeneratorPoolEntry(
            id: UUID(uuidString: "BBBB1111-2222-3333-4444-555566667777")!,
            name: "Poly Generator",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 4, steps: 16, offset: 0)),
                pitch: .native(.manual(pitches: [72], pickMode: .sequential)),
                shape: NoteShape(velocity: 99, gateLength: 3, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [])
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
        )
        let document = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (document, track)
    }

    func test_running_generator_populates_capture_snapshot() {
        let controller = EngineController(client: nil, endpoint: nil)
        let (document, track) = makeGeneratorDocument()

        controller.apply(documentModel: document)
        for tick in 0..<32 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }

        let snapshot = controller.captureSnapshot(trackID: track.id)
        XCTAssertFalse(snapshot.steps.isEmpty, "Engine should append capture steps while the generator plays.")

        let capturedNoteCount = snapshot.steps.reduce(0) { $0 + $1.notes.count }
        XCTAssertGreaterThan(capturedNoteCount, 0, "Euclidean 4/16 should have produced notes in 32 ticks.")
    }

    @MainActor
    func test_view_model_live_preview_shows_captured_notes() {
        let controller = EngineController(client: nil, endpoint: nil)
        let (document, track) = makeGeneratorDocument()

        controller.apply(documentModel: document)
        for tick in 0..<32 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }

        let model = ClipHistoryTransferViewModel(
            trackID: track.id,
            snapshot: controller.captureSnapshot(trackID: track.id),
            destinationSlots: [],
            setAuditionOverride: { _ in }
        )

        XCTAssertNotNil(model.previewContent, "Live rolling preview should materialize from captured steps.")
        let totalCellNotes = model.sourceCells.reduce(0) { $0 + $1.noteCount }
        XCTAssertGreaterThan(totalCellNotes, 0, "Recent output cells should report captured notes.")
    }

    func test_capture_resumes_after_audition_stops() {
        let controller = EngineController(client: nil, endpoint: nil)
        let (document, track) = makeGeneratorDocument()

        controller.apply(documentModel: document)
        for tick in 0..<16 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }
        let beforeAudition = controller.captureSnapshot(trackID: track.id).steps.count
        XCTAssertGreaterThan(beforeAudition, 0)

        let override = PseudoClipState.materialize(
            sourceTrackID: track.id,
            from: controller.captureSnapshot(trackID: track.id),
            startStep: 0,
            lengthSteps: 8
        )
        controller.setAuditionOverride(override, for: track.id)
        for tick in 16..<24 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }

        controller.setAuditionOverride(nil, for: track.id)
        for tick in 24..<40 {
            controller.processTick(tickIndex: UInt64(tick), now: TimeInterval(tick) * 0.1)
        }

        let afterResume = controller.captureSnapshot(trackID: track.id)
        let lastStep = afterResume.steps.last?.absoluteStep ?? -1
        XCTAssertGreaterThanOrEqual(lastStep, 39, "Capture should resume appending after audition stops.")
    }
}
