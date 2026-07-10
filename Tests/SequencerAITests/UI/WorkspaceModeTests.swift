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

    func test_captureFixtureCanSelectExistingTrackTypeAndRemoveTemporary808Group() throws {
        let fixture = makeFixture()
        defer { fixture.engine.shutdown() }
        fixture.session.appendTrack(trackType: .chord)
        let chordID = fixture.session.store.selectedTrackID
        fixture.session.appendTrack(trackType: .slice)

        apply(["selectTrackType": TrackType.chord.rawValue], fixture: fixture)

        XCTAssertEqual(fixture.session.store.selectedTrackID, chordID)
        XCTAssertEqual(fixture.sectionBox.section, .track)

        let groupID = try XCTUnwrap(
            fixture.session.addDrumGroup(
                plan: DrumGroupPlan(
                    name: "808",
                    color: "#8AA",
                    members: [DrumGroupPlan.Member(tag: "kick", trackName: "Kick")]
                )
            )
        )
        let memberIDs = Set(try XCTUnwrap(fixture.session.store.trackGroups.first { $0.id == groupID }).memberIDs)

        apply(["removeDefault808": "true"], fixture: fixture)

        XCTAssertTrue(fixture.session.store.trackGroups.allSatisfy { $0.id != groupID })
        XCTAssertTrue(memberIDs.isDisjoint(with: Set(fixture.session.store.tracks.map(\.id))))
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

    // MARK: - Tracks Perform = navigation + selection (no bespoke layer surface)

    /// AC3/AC4: the tracks Perform view's "Perform" action launches the scoped
    /// Track/Kit Perform overlay (which reuses phrase perform) for the current
    /// selection. The Perform button's effect is exactly an
    /// `enterScopedPerform` over the selected (or focused) track ids, with the
    /// selection scoping a single track, a multi-select set, or a whole kit —
    /// all transient runtime state, never persisted to the document.
    func test_performFromMultiSelect_setsScopeAndEntersScopedPerform() {
        let fixture = makeFixture()
        // Three transient runtime selections drive the launch — they are NOT
        // document-backed track ids here; the contract under test is the
        // scope-set + mode flip the Perform button performs.
        let selected = [UUID(), UUID(), UUID()]

        fixture.session.enterScopedPerform(trackIDs: selected)

        XCTAssertEqual(
            fixture.session.performTrackScope, Set(selected),
            "Selecting cards then Perform must scope perform to exactly the selected track ids."
        )
        XCTAssertEqual(
            fixture.session.workspaceMode, .perform,
            "Perform must flip the global workspace mode into perform."
        )
    }

    func test_tracksPerformCommandRoutesToPhraseLayersByTrackWithSelectionScope() throws {
        let fixture = makeFixture()
        let selected = fixture.session.store.tracks.prefix(2).map(\.id)
        fixture.session.tracksSelection = Set(selected)

        apply(["tracksAction": "perform"], fixture: fixture)

        let request = try XCTUnwrap(fixture.session.pendingPhrasePerform)
        XCTAssertEqual(request.tab, .layers)
        XCTAssertEqual(request.layerEditMode, .byTrack)
        XCTAssertEqual(request.trackIDs, Set(selected))
    }

    func test_scenePerformRequestRoutesEveryTrackToPhraseScenes() throws {
        let fixture = makeFixture()
        fixture.session.workspaceMode = .setup

        fixture.session.requestScenePerform()

        let request = try XCTUnwrap(fixture.session.pendingPhrasePerform)
        XCTAssertEqual(fixture.session.workspaceMode, .perform)
        XCTAssertEqual(request.tab, .scenes)
        XCTAssertNil(request.layerEditMode)
        XCTAssertEqual(request.trackIDs, Set(fixture.session.store.tracks.map(\.id)))
    }

    func test_tracksFilterCommandNavigatesWithoutMutatingDocumentOrSelectionAndReportsStatus() throws {
        let fixture = makeFixture()
        let projectBefore = fixture.session.store.exportToProject()
        let selected = fixture.session.store.selectedTrackID
        fixture.session.tracksSelection = [selected]

        apply(["tracksFilter": TracksNavigatorFilter.drumParts.rawValue], fixture: fixture)

        XCTAssertEqual(fixture.sectionBox.section, .tracks)
        XCTAssertEqual(fixture.session.tracksSelection, [selected])
        XCTAssertEqual(fixture.session.store.exportToProject(), projectBefore)
        let status = try statusDictionary(fixture: fixture, section: .tracks)
        XCTAssertEqual(status["tracksFilter"], TracksNavigatorFilter.drumParts.rawValue)
    }

    /// AC4: the bespoke tracks-perform layer surface is gone, so the QA status
    /// must no longer report any `trackPerformLayer*` selector/variant field.
    func test_status_noLongerReportsTrackPerformLayerSelector() throws {
        let fixture = makeFixture()
        fixture.session.workspaceMode = .perform

        let status = try statusDictionary(fixture: fixture, section: .tracks)

        XCTAssertNil(
            status["trackPerformLayerMode"],
            "The tracks Perform view is navigation + selection now — it must not expose a track-perform layer mode."
        )
        XCTAssertNil(
            status["trackPerformLayerSelectorVisible"],
            "The TRACK LAYER selector was removed; its status field must be retired."
        )
        XCTAssertNil(
            status["trackPerformLayerVariant"],
            "The track-perform layer variant was removed with the layer surface."
        )
        XCTAssertNil(
            status["trackPerformCaptureVisible"],
            "The tracks-matrix capture chooser was removed; its status field must be retired."
        )
    }

    /// AC4: the retired `trackPerformLayer*` / `phrasePerformCapture` commands
    /// must be accepted (so stale visual scripts don't error) but ignored —
    /// they only drive navigation into tracks-perform now, never a layer
    /// selector. The selection/scope stays empty (unscoped) since no scope
    /// command was sent.
    func test_retiredTrackPerformLayerCommand_isAcceptedButDrivesNoLayerSurface() {
        let fixture = makeFixture()

        apply(
            [
                "trackPerformLayer": "noteRepeat",
                "trackPerformLayerSelector": "open",
                "trackPerformLayerVariant": "1/16"
            ],
            fixture: fixture
        )

        XCTAssertEqual(
            fixture.session.workspaceMode, .perform,
            "The retired fixture still navigates into tracks perform."
        )
        XCTAssertEqual(fixture.sectionBox.section, .tracks)
        XCTAssertTrue(
            fixture.session.performTrackScope.isEmpty,
            "A retired layer command must not scope perform — it is ignored."
        )
    }

    // MARK: - The tracks navigator is independent of the global mode

    func test_tracksPage_doesNotReEvaluateWhenGlobalModeChanges() throws {
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

        XCTAssertEqual(
            TracksPageInvalidationProbe.pageBodyEvaluations, 0,
            "Tracks is a mode-independent navigator; changing global mode " +
            "must not invalidate its page body."
        )
    }

    func test_phraseSceneHardSwitch_mapsSlotsToCrossfaderEndpoints() {
        XCTAssertEqual(PhraseSceneHardSwitch.crossfaderValue(for: .a), 0)
        XCTAssertEqual(PhraseSceneHardSwitch.crossfaderValue(for: .b), 1)
    }
}
