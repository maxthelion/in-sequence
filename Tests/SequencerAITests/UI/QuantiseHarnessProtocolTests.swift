import SwiftUI
import XCTest
@testable import SequencerAI

/// Capture-harness protocol for quantised perform toggles: the
/// `quantise=off|bar` command drives the session setting and the status
/// file reports the Q setting plus armed/active state, so QA rows can
/// script and assert against boundary-armed changes.
@MainActor
final class QuantiseHarnessProtocolTests: XCTestCase {
    private final class DocumentBox {
        var document = SeqAIDocument()
    }

    private struct Fixture {
        let box: DocumentBox
        let engine: EngineController
        let session: SequencerDocumentSession
    }

    private func makeFixture() -> Fixture {
        let box = DocumentBox()
        let engine = EngineController(client: nil, endpoint: nil, audioOutput: CountingAudioSink())
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        // Test-isolation convention (bacee620): every controller a test
        // creates gets a full shutdown at teardown so no TickClock or host
        // work leaks into later suites.
        addTeardownBlock {
            engine.shutdown()
        }
        return Fixture(box: box, engine: engine, session: session)
    }

    private func apply(_ command: [String: String], fixture: Fixture) {
        VisualScenarioCommandRunner.apply(
            command: command,
            section: .constant(.tracks),
            visualPhraseControlsOpenIndex: .constant(nil),
            session: fixture.session,
            engineController: fixture.engine
        )
    }

    private func statusDictionary(fixture: Fixture) throws -> [String: String] {
        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quantise-harness-tests-\(UUID().uuidString).status")
        defer { try? FileManager.default.removeItem(at: statusURL) }

        VisualScenarioCommandRunner.writeStatus(
            to: statusURL,
            section: .tracks,
            visualPhraseControlsOpenIndex: nil,
            session: fixture.session,
            engineController: fixture.engine
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

    func test_quantiseCommandDrivesTheSessionSetting() {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.session.performQuantise, .bar)

        apply(["quantise": "off"], fixture: fixture)
        XCTAssertEqual(fixture.session.performQuantise, .off)

        apply(["quantise": "bar"], fixture: fixture)
        XCTAssertEqual(fixture.session.performQuantise, .bar)
    }

    func test_statusEmitsQuantiseSettingAndArmedChanges() throws {
        let fixture = makeFixture()
        fixture.session.workspaceMode = .perform
        fixture.engine.start()
        fixture.engine.clock.stop()
        defer { fixture.engine.stop() }

        var status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["quantise"], "bar")
        XCTAssertEqual(status["quantisePending"], "none")
        XCTAssertEqual(status["quantiseFillCueActive"], "none")

        let track = fixture.session.store.tracks[0]
        let phraseID = fixture.session.store.selectedPhraseID
        fixture.engine.armQuantisedToggle(.mute(trackID: track.id, muted: true, basisPhraseID: phraseID))
        fixture.engine.armQuantisedToggle(.fillCue(trackID: track.id))

        status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(
            status["quantisePending"],
            "\(track.name):mute-on,\(track.name):fill-cue",
            "armed changes report as <track>:<change> in arm order"
        )
    }

    func test_trackFillEngagedCommandWritesSelectedPhraseFillFlagAndStatus() throws {
        let fixture = makeFixture()
        let track = fixture.session.store.selectedTrack
        let fillLayer = try XCTUnwrap(fixture.session.store.layers.first {
            if case .macroRow("fill-flag") = $0.target {
                return true
            }
            return false
        })

        apply(
            [
                "trackFillSource": "clip",
                "trackFillEngaged": "on",
            ],
            fixture: fixture
        )

        XCTAssertEqual(
            fixture.session.store.selectedPhrase.cell(for: fillLayer.id, trackID: track.id),
            .single(.bool(true))
        )
        var status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["selectedTrackFillEngaged"], "true")

        apply(["trackFillEngaged": "off"], fixture: fixture)

        XCTAssertEqual(
            fixture.session.store.selectedPhrase.cell(for: fillLayer.id, trackID: track.id),
            .single(.bool(false))
        )
        status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["selectedTrackFillEngaged"], "false")
    }

    func test_trackRandomizeRollBakesSelectedClipAndStatus() throws {
        let fixture = makeFixture()

        apply(
            [
                "trackFillSource": "clip",
                "trackRandomizeRoll": "on",
            ],
            fixture: fixture
        )

        let pattern = fixture.session.store.selectedPattern(for: fixture.session.store.selectedTrackID)
        let clipID = try XCTUnwrap(pattern.sourceRef.clipID)
        let clip = try XCTUnwrap(fixture.session.store.clipEntry(id: clipID))
        XCTAssertNotNil(clip.randomizeSettings)

        let status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["selectedTrackRandomizePersisted"], "true")
        XCTAssertNotEqual(status["selectedTrackRandomizeLastSeed"], "none")
        XCTAssertEqual(status["trackRandomizeSheet"], "closed")
    }

    func test_trackRandomizeSheetCommandWritesStatusAndPendingEditorCommand() throws {
        let fixture = makeFixture()

        apply(["trackRandomizeSheet": "open"], fixture: fixture)

        let status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["trackRandomizeSheet"], "open")
        XCTAssertEqual(status["trackSourceTab"], "source")
        XCTAssertTrue(
            VisualScenarioCommandRunner.drainPendingTrackSourceEditorCommands()
                .contains("randomize-sheet:open")
        )
    }

    func test_randomizeRerollAndCloseKeepTheAppliedClip() throws {
        let fixture = makeFixture()
        apply(["trackFillSource": "clip", "trackRandomizeRoll": "on"], fixture: fixture)
        let pattern = fixture.session.store.selectedPattern(for: fixture.session.store.selectedTrackID)
        let clipID = try XCTUnwrap(pattern.sourceRef.clipID)
        let first = try XCTUnwrap(fixture.session.store.clipEntry(id: clipID)?.randomizeSettings)

        apply(["trackRandomizeRoll": "on"], fixture: fixture)
        let rerolled = try XCTUnwrap(fixture.session.store.clipEntry(id: clipID)?.randomizeSettings)
        XCTAssertNotEqual(rerolled.lastSeed, first.lastSeed, "Re-Roll must apply a fresh deterministic harness seed.")

        apply(["trackRandomizeSheet": "open"], fixture: fixture)
        apply(["trackRandomizeSheet": "close"], fixture: fixture)

        XCTAssertEqual(
            fixture.session.store.clipEntry(id: clipID)?.randomizeSettings,
            rerolled,
            "Close dismisses the panel without rolling back the already-applied clip."
        )
        XCTAssertEqual(try statusDictionary(fixture: fixture)["trackRandomizeSheet"], "closed")
    }

    func test_trackClipLayerCommandsAreViewStateOnlyAndReportStatus() throws {
        let fixture = makeFixture()
        apply(["trackFillSource": "clip"], fixture: fixture)
        let revisionBefore = fixture.session.store.revision
        let generationRevisionBefore = fixture.engine.tickState.readPrepareInputs().generationInputRevision

        apply(
            [
                "trackClipLayer": "pitch",
                "trackClipLayerSwitcher": "open",
            ],
            fixture: fixture
        )

        let status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["trackClipLayer"], "pitch")
        XCTAssertEqual(status["trackClipLayerSwitcher"], "open")
        XCTAssertEqual(fixture.session.store.revision, revisionBefore)
        XCTAssertEqual(fixture.engine.tickState.readPrepareInputs().generationInputRevision, generationRevisionBefore)
    }

    func test_slicerLayerSwitcherCommandIsViewStateOnlyAndReportsStatus() throws {
        let fixture = makeFixture()
        let generationRevisionBefore = fixture.engine.tickState.readPrepareInputs().generationInputRevision

        apply(["slicerLayerSwitcher": "open"], fixture: fixture)

        let status = try statusDictionary(fixture: fixture)
        XCTAssertEqual(status["slicerLayerSwitcher"], "open")
        XCTAssertEqual(fixture.engine.tickState.readPrepareInputs().generationInputRevision, generationRevisionBefore)

        apply(["slicerLayerSwitcher": "close"], fixture: fixture)
        let closedStatus = try statusDictionary(fixture: fixture)
        XCTAssertEqual(closedStatus["slicerLayerSwitcher"], "closed")
    }

    func test_performanceTrackGroupFixturePersistsTwoTrackScopeAndReportsStatus() throws {
        let fixture = makeFixture()

        apply(
            [
                "phraseMatrixTrackCount": "3",
                "performanceTrackGroupFixture": "0",
            ],
            fixture: fixture
        )

        XCTAssertEqual(fixture.session.store.performanceTrackGroups[0]?.memberIDs.count, 2)
        XCTAssertEqual(try statusDictionary(fixture: fixture)["performanceTrackGroupCount"], "1")
    }

    func test_createTrackGroupModalCommandQueuesTracksSurfaceCommand() throws {
        let fixture = makeFixture()
        fixture.session.tracksSelection = [fixture.session.store.selectedTrackID]

        apply(["tracksCreateTrackGroupModal": "open"], fixture: fixture)

        XCTAssertEqual(try statusDictionary(fixture: fixture)["tracksCreateTrackGroupModalVisible"], "true")
        XCTAssertTrue(
            VisualScenarioCommandRunner.drainPendingTracksMatrixCommands()
                .contains("create-track-group:open")
        )

        apply(["tracksCreateTrackGroupModal": "close"], fixture: fixture)

        XCTAssertEqual(try statusDictionary(fixture: fixture)["tracksCreateTrackGroupModalVisible"], "false")
        XCTAssertTrue(
            VisualScenarioCommandRunner.drainPendingTracksMatrixCommands()
                .contains("create-track-group:close")
        )
    }
}
