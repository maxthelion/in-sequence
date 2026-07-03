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
        // Test-isolation teardown (bug 20260702-135500): every controller this
        // suite creates is fully shut down inside the test that created it, so
        // no TickClock timer or host-queue work leaks into later suites.
        addTeardownBlock {
            session.engineController.shutdown()
            XCTAssertFalse(session.engineController.clock.isRunning,
                "no TickClock may survive test teardown")
            SequencerDocumentSessionRegistry.unregister(session)
        }
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

    // MARK: - Capture-harness vocab (qa-surface rows 01b / 06b / 43 / 44)

    /// `swing=` must drive the transport swing through the same clamped
    /// `setSwing` seam the transport-bar stepper uses, and the status file
    /// must report the applied amount for the row's wait key.
    func test_swingCommandDrivesTransportSwingAndStatus() throws {
        let (session, _) = makeSession()

        VisualScenarioCommandRunner.apply(
            command: ["swing": "0.4"],
            section: .constant(.phrase),
            visualPhraseControlsOpenIndex: .constant(nil),
            session: session,
            engineController: session.engineController
        )
        XCTAssertEqual(session.engineController.currentSwing, 0.4, accuracy: 0.0001)

        let status = try statusDictionary(session: session)
        XCTAssertEqual(status["swing"], "0.4",
            "The status file must report the applied swing for the capture wait")

        VisualScenarioCommandRunner.apply(
            command: ["swing": "1.7"],
            section: .constant(.phrase),
            visualPhraseControlsOpenIndex: .constant(nil),
            session: session,
            engineController: session.engineController
        )
        XCTAssertEqual(session.engineController.currentSwing, 1.0, accuracy: 0.0001,
            "Out-of-range swing must clamp, mirroring the UI stepper")
    }

    /// `phraseSceneViewMode=` must navigate to the phrase workspace and post
    /// the Macros | Slots switch to the scene perform surface; invalid values
    /// must post nothing.
    func test_phraseSceneViewModeCommand_postsSceneViewModeSwitch() {
        let (session, _) = makeSession()
        var section = WorkspaceSection.tracks
        let sectionBinding = Binding(get: { section }, set: { section = $0 })
        _ = VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands()

        VisualScenarioCommandRunner.apply(
            command: ["phraseSceneViewMode": "slots"],
            section: sectionBinding,
            visualPhraseControlsOpenIndex: .constant(nil),
            session: session,
            engineController: session.engineController
        )
        XCTAssertEqual(section, .phrase,
            "The scene view-mode command targets the phrase workspace")
        XCTAssertTrue(
            VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands()
                .contains("scene-view-mode:slots"),
            "The runner must relay the Macros | Slots switch to the view"
        )

        VisualScenarioCommandRunner.apply(
            command: ["phraseSceneViewMode": "bogus"],
            section: sectionBinding,
            visualPhraseControlsOpenIndex: .constant(nil),
            session: session,
            engineController: session.engineController
        )
        XCTAssertFalse(
            VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands()
                .contains(where: { $0.hasPrefix("scene-view-mode:") }),
            "An unknown view mode must not post a switch"
        )
    }

    /// The two creation-seed library categories (rows 43/44) must be valid
    /// `libraryCategory=` vocabulary, and the command must land on the
    /// library page with the status reporting the selected category.
    func test_libraryCategoryCommand_acceptsCreationSeedCategories() throws {
        let (session, _) = makeSession()

        for raw in ["auInstruments", "generators"] {
            XCTAssertNotNil(LibraryCategory(rawValue: raw),
                "\(raw) must be a browsable library category")

            var section = WorkspaceSection.tracks
            let sectionBinding = Binding(get: { section }, set: { section = $0 })
            VisualScenarioCommandRunner.apply(
                command: ["libraryCategory": raw],
                section: sectionBinding,
                visualPhraseControlsOpenIndex: .constant(nil),
                session: session,
                engineController: session.engineController
            )
            XCTAssertEqual(section, .library)

            let status = try statusDictionary(session: session, section: .library)
            XCTAssertEqual(status["libraryCategory"], raw,
                "The status file must report the selected category for the capture wait")
        }
    }

    private func statusDictionary(
        session: SequencerDocumentSession,
        section: WorkspaceSection = .phrase
    ) throws -> [String: String] {
        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("create-track-harness-tests-\(UUID().uuidString).status")
        defer { try? FileManager.default.removeItem(at: statusURL) }

        VisualScenarioCommandRunner.writeStatus(
            to: statusURL,
            section: section,
            visualPhraseControlsOpenIndex: nil,
            session: session,
            engineController: session.engineController
        )

        let payload = try String(contentsOf: statusURL)
        return payload
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard let separator = line.firstIndex(of: "=") else { return }
                result[String(line[..<separator])] =
                    String(line[line.index(after: separator)...])
            }
    }
}
