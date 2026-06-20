import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

// MARK: - Tracks-page invalidation-scope budget
//
// Regression net for the tracks-page BPM sag
// (docs/audits/2026-06-12-architecture-verdict.md §1–2): the page observed
// tick-rate engine state (`transportTickIndex`) in its whole-page body, so
// every transport tick re-evaluated every card during playback. Main-thread
// load then degraded tick publishing and gesture handling.
//
// Contract under test: tick-rate state is observed ONLY by playhead leaf
// views. Publishing a transport tick must not re-evaluate
// `TracksMatrixView.body`. The probe counters live in TracksMatrixView.swift
// (DEBUG only).
@MainActor
final class TracksPageInvalidationTests: XCTestCase {

    // MARK: - Fixture

    /// 8 MIDI tracks, one 4-bar phrase. Track 0 carries a step-varying mute
    /// cell and track 1 a bar-varying pattern cell so the playhead leaves
    /// have real per-step work; the rest are `.single`/inherit (the common
    /// shape, which must not observe the playhead at all).
    private func makeFixtureProject() -> Project {
        var trackIDs: [UUID] = []
        var tracks: [StepSequenceTrack] = []
        for index in 0..<8 {
            let trackID = UUID()
            trackIDs.append(trackID)
            tracks.append(
                StepSequenceTrack(
                    id: trackID,
                    name: "Track \(index + 1)",
                    pitches: [60 + index],
                    stepPattern: Array(repeating: false, count: 16),
                    stepAccents: Array(repeating: false, count: 16),
                    destination: .midi(port: .sequencerAIOut, channel: UInt8(index % 16), noteOffset: 0),
                    velocity: 96,
                    gateLength: 4
                )
            )
        }

        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        var phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        phrase.lengthBars = 4

        if let muteLayer = layers.first(where: { $0.target == .mute }) {
            let stepValues: [PhraseCellValue] = (0..<phrase.stepCount).map { .bool($0 % 2 == 0) }
            phrase.setCell(.steps(stepValues), for: muteLayer.id, trackID: trackIDs[0])
        }
        if let patternLayer = layers.first(where: { $0.target == .patternIndex }) {
            let barValues: [PhraseCellValue] = (0..<phrase.lengthBars).map { .index($0 % 2) }
            phrase.setCell(.bars(barValues), for: patternLayer.id, trackID: trackIDs[1])
        }

        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [],
            selectedTrackID: trackIDs[0],
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }

    private struct Harness {
        let session: SequencerDocumentSession
        let engine: EngineController
        let window: NSWindow
        let hostingView: NSHostingView<AnyView>
    }

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    private func makeHarness(mode: WorkspaceMode) throws -> Harness {
        let project = makeFixtureProject()
        let box = DocumentBox(document: SeqAIDocument(project: project))
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
        // The page derives edit-vs-perform from the GLOBAL workspace mode
        // (perform/setup split slice 1) on the session.
        session.workspaceMode = mode

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
        // Off-screen but attached: SwiftUI evaluates bodies once the hosting
        // view lives in a window and lays out — no need to order it front on
        // the test machine's display.
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        hostingView.layoutSubtreeIfNeeded()
        drainMainRunLoop()

        return Harness(session: session, engine: engine, window: window, hostingView: hostingView)
    }

    private func drainMainRunLoop(seconds: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Drives `tickCount` transport ticks through the real tick entry point,
    /// draining the main run loop after each so SwiftUI processes every
    /// invalidation individually (no coalescing that would hide per-tick
    /// re-evaluation).
    private func driveTicks(_ tickCount: Int, engine: EngineController, startingAt firstTick: UInt64 = 0) {
        for offset in 0..<tickCount {
            let tickIndex = firstTick + UInt64(offset)
            engine.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) * 0.05)
            drainMainRunLoop(seconds: 0.005)
        }
        drainMainRunLoop()
    }

    // MARK: - Tests

    func test_transportTicks_doNotReevaluateTracksPageBody_editMode() throws {
        let harness = try makeHarness(mode: .setup)
        defer { harness.window.close() }

        TracksPageInvalidationProbe.reset()
        // Settle: anything still pending from initial render.
        drainMainRunLoop()
        TracksPageInvalidationProbe.reset()

        let tickCount = 32
        driveTicks(tickCount, engine: harness.engine)

        let pageEvaluations = TracksPageInvalidationProbe.pageBodyEvaluations
        let cardEvaluations = TracksPageInvalidationProbe.cardContentEvaluations
        let leafEvaluations = TracksPageInvalidationProbe.playheadLeafEvaluations
        print("[TracksPageInvalidation] edit mode: \(tickCount) ticks → " +
              "pageBodyEvaluations=\(pageEvaluations), " +
              "cardContentEvaluations=\(cardEvaluations), " +
              "playheadLeafEvaluations=\(leafEvaluations)")

        XCTAssertEqual(
            pageEvaluations, 0,
            "Transport ticks must not re-evaluate the tracks page body " +
            "(\(pageEvaluations) page-body evaluations for \(tickCount) ticks). " +
            "Tick-rate state may only be read by playhead leaf views " +
            "(architecture verdict §2: invalidation scope is budgeted)."
        )
        XCTAssertEqual(
            cardEvaluations, 0,
            "Transport ticks must not re-build the track cards " +
            "(\(cardEvaluations) card-content evaluations for \(tickCount) ticks " +
            "× 8 tracks). A tick-rate read inside the card-building closure " +
            "re-renders every visible card per tick — the tracks-page BPM-sag " +
            "mechanism. Tick-rate state may only be read by playhead leaf views."
        )
    }

    func test_transportTicks_doNotReachAnyLeaf() throws {
        let harness = try makeHarness(mode: .setup)
        defer { harness.window.close() }

        drainMainRunLoop()
        TracksPageInvalidationProbe.reset()

        let tickCount = 32
        driveTicks(tickCount, engine: harness.engine)

        // The tracks view is now a plain NAVIGATOR (track tiles + add tile): it
        // renders NO tick-rate state (no pattern/layer preview, no playhead-
        // following stroke), so transport ticks must not re-evaluate any
        // tracks-page leaf. The probe is proven wired by
        // `test_documentMutation_stillReevaluatesPageBody`.
        XCTAssertEqual(
            TracksPageInvalidationProbe.playheadLeafEvaluations, 0,
            "The navigator reads no tick-rate state — transport ticks must not " +
            "re-evaluate any tracks-page leaf " +
            "(\(TracksPageInvalidationProbe.playheadLeafEvaluations) leaf " +
            "evaluations for \(tickCount) ticks)."
        )
    }

    func test_documentMutation_stillReevaluatesPageBody() throws {
        let harness = try makeHarness(mode: .setup)
        defer { harness.window.close() }

        drainMainRunLoop()
        TracksPageInvalidationProbe.reset()

        // Positive control for the probe itself: a selection change is page
        // state and MUST re-evaluate the page body.
        let nextTrackID = harness.session.store.tracks[1].id
        harness.session.setSelectedTrackID(nextTrackID)
        drainMainRunLoop()

        XCTAssertGreaterThan(
            TracksPageInvalidationProbe.pageBodyEvaluations, 0,
            "Selection changes must re-evaluate the page body — zero means the " +
            "probe is not wired into the rendered view tree and the budget " +
            "assertions above are vacuous."
        )
    }

    func test_transportTicks_doNotReevaluateTracksPageBody_performMode() throws {
        let harness = try makeHarness(mode: .perform)
        defer { harness.window.close() }

        drainMainRunLoop()
        TracksPageInvalidationProbe.reset()

        let tickCount = 32
        driveTicks(tickCount, engine: harness.engine)

        let pageEvaluations = TracksPageInvalidationProbe.pageBodyEvaluations
        let cardEvaluations = TracksPageInvalidationProbe.cardContentEvaluations
        print("[TracksPageInvalidation] perform mode: \(tickCount) ticks → " +
              "pageBodyEvaluations=\(pageEvaluations), " +
              "cardContentEvaluations=\(cardEvaluations), " +
              "playheadLeafEvaluations=\(TracksPageInvalidationProbe.playheadLeafEvaluations)")

        XCTAssertEqual(
            pageEvaluations, 0,
            "Transport ticks must not re-evaluate the tracks page body in " +
            "perform mode (\(pageEvaluations) page-body evaluations for " +
            "\(tickCount) ticks)."
        )
        XCTAssertEqual(
            cardEvaluations, 0,
            "Transport ticks must not re-build the track tiles in perform mode " +
            "(\(cardEvaluations) card-content evaluations for \(tickCount) ticks). " +
            "The tracks view is now a plain NAVIGATOR with no Edit/Perform split, " +
            "so perform mode renders the same static tiles as setup; a tick-rate " +
            "read in the tile-building closure would re-render every visible tile " +
            "per tick — the tracks-page BPM-sag mechanism."
        )
    }

    /// With the Edit/Perform split removed the tracks view is the same plain
    /// NAVIGATOR in every workspace mode: static track tiles (name + icon +
    /// mute) and the add tile, reading NO tick-rate state. So in perform mode
    /// too transport ticks must reach no leaf — the navigator has no playhead-
    /// following preview/stroke to re-evaluate.
    func test_transportTicks_doNotReachAnyLeaf_performMode() throws {
        let harness = try makeHarness(mode: .perform)
        defer { harness.window.close() }

        drainMainRunLoop()
        TracksPageInvalidationProbe.reset()

        let tickCount = 32
        driveTicks(tickCount, engine: harness.engine)

        let pageEvaluations = TracksPageInvalidationProbe.pageBodyEvaluations
        let cardEvaluations = TracksPageInvalidationProbe.cardContentEvaluations
        let leafEvaluations = TracksPageInvalidationProbe.playheadLeafEvaluations
        print("[TracksPageInvalidation] perform mode navigator: \(tickCount) ticks → " +
              "pageBodyEvaluations=\(pageEvaluations), " +
              "cardContentEvaluations=\(cardEvaluations), " +
              "playheadLeafEvaluations=\(leafEvaluations)")

        XCTAssertEqual(
            pageEvaluations, 0,
            "perform-mode ticks must not re-evaluate the page body"
        )
        XCTAssertEqual(
            cardEvaluations, 0,
            "perform-mode ticks must not re-build the navigator tiles " +
            "(\(cardEvaluations) card-content evaluations for \(tickCount) ticks)"
        )
        XCTAssertEqual(
            leafEvaluations, 0,
            "The navigator reads no tick-rate state — perform-mode ticks must " +
            "reach no tracks-page leaf (\(leafEvaluations) leaf evaluations for " +
            "\(tickCount) ticks)."
        )
    }
}
