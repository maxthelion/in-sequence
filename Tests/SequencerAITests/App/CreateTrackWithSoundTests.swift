import SwiftUI
import XCTest
@testable import SequencerAI

/// Session-level tests for the consolidated Create Track flow's at-creation
/// sound step (`CreateTrackFlow`): the `appendTrack(trackType:soundDestination:)`
/// and `appendTrack(generator:)` compositions, and the capture-harness
/// command → flow-step mapping. Real AU instantiation/sound is human-tier
/// only (no TCC prompts for autonomous agents), so coverage here is
/// session-mutation/routing-level, mirroring DrumKitSoundTabAUTests.
@MainActor
final class CreateTrackWithSoundTests: XCTestCase {

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project = .empty) -> (SequencerDocumentSession, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        return (session, box)
    }

    private func makeAUComponentID() -> AudioComponentID {
        AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
    }

    // MARK: - AU fast path (mono/poly sound step, single-click AU row)

    /// Clicking an AU instrument row must create the track AND attach the AU
    /// through the standard setEditedDestination path in one gesture.
    func test_appendTrackWithAUDestination_createsSelectedTrackWithAU() throws {
        let (session, _) = makeSession()
        let trackCountBefore = session.store.tracks.count

        let componentID = makeAUComponentID()
        let newTrackID = session.appendTrack(
            trackType: .monoMelodic,
            soundDestination: .auInstrument(componentID: componentID, stateBlob: nil)
        )

        let live = session.store.exportToProject()
        XCTAssertEqual(live.tracks.count, trackCountBefore + 1,
            "The sound step must append exactly one track")
        let createdID = try XCTUnwrap(newTrackID)
        XCTAssertEqual(live.selectedTrackID, createdID,
            "The new track must be selected so onOpenTrack lands on it")
        let created = try XCTUnwrap(live.tracks.first(where: { $0.id == createdID }))
        XCTAssertEqual(created.trackType, .monoMelodic)
        XCTAssertEqual(created.destination.kind, .auInstrument,
            "The AU row must attach the chosen AU instrument at creation")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// The Sampler row seeds a `.sample` destination; Poly keeps its type.
    func test_appendTrackWithSampleDestination_polyKeepsTypeAndSound() throws {
        let (session, _) = makeSession()

        let newTrackID = session.appendTrack(
            trackType: .polyMelodic,
            soundDestination: .sample(sampleID: UUID(), settings: .default)
        )

        let live = session.store.exportToProject()
        let created = try XCTUnwrap(live.tracks.first(where: { $0.id == newTrackID }))
        XCTAssertEqual(created.trackType, .polyMelodic)
        XCTAssertEqual(created.destination.kind, .sample)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// A refused append (second audio-input track) must return nil and must
    /// NOT retarget an existing track's destination.
    func test_appendTrackWithSound_refusedAppend_returnsNilWithoutRetargeting() {
        let (session, _) = makeSession()
        session.appendTrack(trackType: .audioInput)
        let destinationsBefore = session.store.tracks.map(\.destination)

        let result = session.appendTrack(
            trackType: .audioInput,
            soundDestination: .auInstrument(componentID: makeAUComponentID(), stateBlob: nil)
        )

        XCTAssertNil(result, "A refused append must not report a created track")
        XCTAssertEqual(session.store.tracks.map(\.destination), destinationsBefore,
            "A refused append must leave every existing destination untouched")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Generator composition (Library create-from-entity)

    /// Creating a track from a pooled generator must append a track of the
    /// generator's type and assign the generator as the slot-0 source.
    func test_appendTrackWithGenerator_assignsSlotZeroSource() throws {
        let (session, _) = makeSession()
        let generator = try XCTUnwrap(
            session.store.generatorPool.first(where: { $0.trackType == .monoMelodic }),
            "Precondition: the default generator pool carries a mono generator"
        )

        let newTrackID = session.appendTrack(generator: generator)

        let live = session.store.exportToProject()
        let createdID = try XCTUnwrap(newTrackID)
        let created = try XCTUnwrap(live.tracks.first(where: { $0.id == createdID }))
        XCTAssertEqual(created.trackType, generator.trackType,
            "The created track must take the generator's track type")
        let slotRef = live.patternBank(for: createdID).slot(at: 0).sourceRef
        XCTAssertEqual(slotRef.mode, .generator,
            "Slot 0 must switch to generator mode")
        XCTAssertEqual(slotRef.generatorID, generator.id,
            "Slot 0 must reference the chosen pool generator")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Capture-harness command mapping

    /// The command-file vocabulary must keep driving every creation surface
    /// (rows 02c/02d/02e/02f) now that they are steps of one flow sheet.
    func test_visualCommandMapping_coversAllCreationSurfaces() {
        XCTAssertEqual(
            CreateTrackFlowStep.action(forVisualCommand: "create-track-modal:open"),
            .present(.pickType)
        )
        XCTAssertEqual(
            CreateTrackFlowStep.action(forVisualCommand: "add-drum-group-modal:open"),
            .present(.drumGroupSound)
        )
        XCTAssertEqual(
            CreateTrackFlowStep.action(forVisualCommand: "add-slice-track-modal:open"),
            .present(.sliceSound)
        )
        XCTAssertEqual(
            CreateTrackFlowStep.action(forVisualCommand: "track-sound-modal:open"),
            .present(.monoPolySound(.monoMelodic))
        )
        for close in [
            "create-track-modal:close",
            "add-drum-group-modal:close",
            "add-slice-track-modal:close",
            "track-sound-modal:close",
        ] {
            XCTAssertEqual(CreateTrackFlowStep.action(forVisualCommand: close), .close)
        }
        XCTAssertNil(CreateTrackFlowStep.action(forVisualCommand: "unrelated-command"),
            "Non-creation commands must not touch the flow sheet")
    }
}
