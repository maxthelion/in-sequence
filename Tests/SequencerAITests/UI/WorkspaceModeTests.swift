import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

// MARK: - Global workspace mode (perform/setup split, slice 1)
//
// ONE global SETUP/PERFORM mode replaces the per-page Edit/Perform (tracks)
// and Browse/Perform (scenes) toggles. "Setup configures (what a thing IS);
// Perform plays (what you hear next bar)." These tests pin:
//
//  1. the mode is session-only state defaulting to `.setup` (like the
//     selected page, it is never persisted in the document),
//  2. the ONE mode value drives Tracks; top-level Scenes remains management
//     because scene perform now lives under Phrase,
//  3. capture-harness compatibility: the legacy `tracksMode=` and
//     `scenesMode=` commands keep their navigation side effect, the new
//     `workspaceMode=` command sets the global mode directly, and the
//     `.status` file keeps emitting legacy keys so visual scripts can keep
//     reading deterministic state.
@MainActor
final class WorkspaceModeTests: XCTestCase {

    // MARK: - Fixture

    private final class DocumentBox {
        var document = SeqAIDocument()
    }

    private final class SectionBox {
        var section: WorkspaceSection = .phrase
    }

    private struct Fixture {
        let box: DocumentBox
        let sectionBox: SectionBox
        let engine: EngineController
        let session: SequencerDocumentSession

        var sectionBinding: Binding<WorkspaceSection> {
            let sectionBox = sectionBox
            return Binding(
                get: { sectionBox.section },
                set: { sectionBox.section = $0 }
            )
        }
    }

    private func makeFixture() -> Fixture {
        let box = DocumentBox()
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        return Fixture(box: box, sectionBox: SectionBox(), engine: engine, session: session)
    }

    private func apply(_ command: [String: String], fixture: Fixture) {
        VisualScenarioCommandRunner.apply(
            command: command,
            section: fixture.sectionBinding,
            visualPhraseControlsOpenIndex: .constant(nil),
            session: fixture.session,
            engineController: fixture.engine
        )
    }

    // MARK: - Session-only mode state

    func test_workspaceMode_defaultsToSetup() {
        let fixture = makeFixture()
        XCTAssertEqual(
            fixture.session.workspaceMode, .setup,
            "The global workspace mode is session state and must default to " +
            "setup on every session, like the selected page."
        )
    }

    // MARK: - One mode drives both pages

    func test_oneGlobalMode_drivesBothPagesVocabularies() {
        // The tracks page (edit/perform) and scenes page (browseEdit/perform)
        // vocabularies are pure derivations of the ONE global mode — there is
        // no second mode axis for a page to disagree on.
        XCTAssertEqual(WorkspaceMode.setup.tracksModeValue, .edit)
        XCTAssertEqual(WorkspaceMode.setup.scenesModeValue, .browseEdit)
        XCTAssertEqual(WorkspaceMode.perform.tracksModeValue, .perform)
        XCTAssertEqual(WorkspaceMode.perform.scenesModeValue, .perform)

        // And the reverse mapping (legacy command vocabulary → global mode).
        XCTAssertEqual(WorkspaceMode(tracksMode: .edit), .setup)
        XCTAssertEqual(WorkspaceMode(tracksMode: .perform), .perform)
        XCTAssertEqual(WorkspaceMode(scenesMode: .browseEdit), .setup)
        XCTAssertEqual(WorkspaceMode(scenesMode: .perform), .perform)
    }

    // MARK: - Harness command mapping (legacy commands keep working)

    func test_legacyTracksModeCommand_setsGlobalModeAndNavigatesToTracks() {
        let fixture = makeFixture()

        apply(["tracksMode": "perform"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .perform,
                       "tracksMode=perform must map onto the global mode")
        XCTAssertEqual(fixture.sectionBox.section, .tracks,
                       "tracksMode= keeps its navigation side effect")

        apply(["tracksMode": "edit"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .setup,
                       "tracksMode=edit must map onto setup")
        XCTAssertEqual(fixture.sectionBox.section, .tracks)
    }

    func test_legacyScenesModeCommand_navigatesToSceneManagementOnly() {
        let fixture = makeFixture()
        fixture.session.workspaceMode = .perform

        apply(["scenesMode": "perform"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .setup,
                       "top-level Scenes is management only; scene perform lives under Phrase")
        XCTAssertEqual(fixture.sectionBox.section, .scenes,
                       "scenesMode= keeps its navigation side effect for legacy capture commands")

        apply(["scenesMode": "browseEdit"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .setup,
                       "scenesMode=browseEdit must map onto setup")
        XCTAssertEqual(fixture.sectionBox.section, .scenes)
    }

    func test_workspaceModeCommand_setsGlobalModeWithoutNavigating() {
        let fixture = makeFixture()
        fixture.sectionBox.section = .mixer

        apply(["workspaceMode": "perform"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .perform)
        XCTAssertEqual(fixture.sectionBox.section, .mixer,
                       "workspaceMode= is the global mode's own command — no navigation side effect")

        apply(["workspaceMode": "setup"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .setup)
        XCTAssertEqual(fixture.sectionBox.section, .mixer)
    }

    func test_performFixtureCommands_forceGlobalPerformMode() {
        // The perform-layer capture fixtures (trackPerformLayer= etc.) used
        // to write the local tracks mode; they must now drive the global one.
        let fixture = makeFixture()

        apply(["trackPerformLayer": "mute"], fixture: fixture)
        XCTAssertEqual(fixture.session.workspaceMode, .perform)
        XCTAssertEqual(fixture.sectionBox.section, .tracks)
    }

    // MARK: - Status emission (legacy keys derived from the global mode)

    private func statusDictionary(fixture: Fixture, section: WorkspaceSection) throws -> [String: String] {
        let statusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-mode-tests-\(UUID().uuidString).status")
        defer { try? FileManager.default.removeItem(at: statusURL) }

        VisualScenarioCommandRunner.writeStatus(
            to: statusURL,
            section: section,
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

    func test_status_emitsLegacyModeKeysDerivedFromGlobalMode() throws {
        let fixture = makeFixture()

        fixture.session.workspaceMode = .perform
        var status = try statusDictionary(fixture: fixture, section: .tracks)
        XCTAssertEqual(status["workspaceMode"], "perform")
        XCTAssertEqual(status["tracksMode"], "perform",
                       "legacy tracksMode status key must survive, derived from the global mode")
        XCTAssertEqual(status["scenesMode"], "perform",
                       "outside the Scenes workspace, the legacy scenesMode key still reflects the global mode")

        fixture.session.workspaceMode = .setup
        status = try statusDictionary(fixture: fixture, section: .scenes)
        XCTAssertEqual(status["workspaceMode"], "setup")
        XCTAssertEqual(status["tracksMode"], "edit",
                       "setup must read back as the legacy edit vocabulary")
        XCTAssertEqual(status["scenesMode"], "browseEdit",
                       "top-level Scenes always reports scene management")

        fixture.session.workspaceMode = .perform
        status = try statusDictionary(fixture: fixture, section: .scenes)
        XCTAssertEqual(status["workspaceMode"], "perform")
        XCTAssertEqual(status["scenesMode"], "browseEdit",
                       "top-level Scenes must not report scene perform anymore")
    }

    // MARK: - Scoped Track/Kit Perform (AC22 / AC3.2)

    func test_enterScopedPerform_setsScopeAndFlipsToPerform() {
        let fixture = makeFixture()
        let t1 = UUID()

        fixture.session.enterScopedPerform(trackIDs: [t1])

        XCTAssertEqual(
            fixture.session.performTrackScope, [t1],
            "enterScopedPerform([t1]) must record exactly that track in the scope set"
        )
        XCTAssertEqual(
            fixture.session.workspaceMode, .perform,
            "enterScopedPerform must flip the global workspace mode to perform"
        )
    }

    func test_enterScopedPerform_emptyClearsScope() {
        let fixture = makeFixture()
        let t1 = UUID()
        fixture.session.enterScopedPerform(trackIDs: [t1])

        fixture.session.enterScopedPerform(trackIDs: [])

        XCTAssertTrue(
            fixture.session.performTrackScope.isEmpty,
            "enterScopedPerform([]) must clear the scope — empty means unscoped (all tracks)"
        )
        XCTAssertEqual(
            fixture.session.workspaceMode, .perform,
            "Clearing the scope still enters perform mode"
        )
    }

    // MARK: - The tracks page observes the global mode

    func test_tracksPage_reEvaluatesWhenGlobalModeChanges() throws {
        let box = DocumentBox()
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()

        let layerID = session.store.patternLayer?.id ?? session.store.layers.first!.id
        let root = TracksWorkspaceView(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            selectedLayerID: .constant(layerID),
            onOpenTrack: {}
        )
        .environment(engine)
        .environment(session)

        let hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1480, height: 980)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        hostingView.layoutSubtreeIfNeeded()
        defer { window.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        TracksPageInvalidationProbe.reset()

        session.workspaceMode = .perform
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThan(
            TracksPageInvalidationProbe.pageBodyEvaluations, 0,
            "Flipping the GLOBAL workspace mode must re-evaluate the tracks " +
            "page — zero evaluations means the page is no longer wired to the " +
            "one session-owned mode."
        )
    }
}
