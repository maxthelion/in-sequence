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
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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

    func test_trackNavigatorCards_selectOnRightClickWithoutContextMenus() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TracksMatrixView.swift"),
            encoding: .utf8
        )
        let trackCard = try XCTUnwrap(
            source.slice(from: "private struct TrackMatrixCard", to: "    private var strokeColor"),
            "TrackMatrixCard source should be present"
        )
        let kitCard = try XCTUnwrap(
            source.slice(from: "private struct KitMatrixCard", to: "struct TrackPerformRuntimeControlState"),
            "KitMatrixCard source should be present"
        )

        XCTAssertTrue(
            trackCard.contains(".studioSelectOnRightClick"),
            "Track cards should still select on secondary click."
        )
        XCTAssertFalse(
            trackCard.contains(".contextMenu"),
            "Track cards must not open the old Select/Copy/Mute menu on secondary click."
        )
        XCTAssertTrue(
            kitCard.contains(".studioSelectOnRightClick"),
            "Kit cards should still select on secondary click."
        )
        XCTAssertFalse(
            kitCard.contains(".contextMenu"),
            "Kit cards must not open the old Select/Copy/Expand menu on secondary click."
        )
        XCTAssertTrue(
            trackCard.contains(".contentShape(") && trackCard.contains(".onTapGesture"),
            "The ordinary track card's full visible shape must toggle/open, including its edges."
        )
        XCTAssertTrue(
            kitCard.contains(".contentShape(") && kitCard.contains(".onTapGesture(perform: onOpenKit)"),
            "The kit card's full visible shape must toggle/open, including its edges."
        )
        XCTAssertFalse(
            trackCard.contains("track-card-select-mark") || trackCard.contains("TrackTypeBadge"),
            "Selection cards should use a solid fill without checkbox or type-logo chrome."
        )
        XCTAssertFalse(
            kitCard.contains("kit-card-select-mark") || kitCard.contains("square.grid.2x2.fill"),
            "Kit selection cards should use the same solid-fill grammar without a checkbox or logo."
        )
    }

    func test_trackNavigatorCardEdgeTogglesSelectionThroughHostedUI() throws {
        let harness = try makeHarness(mode: .setup)
        defer { harness.window.close() }
        let firstTrackID = try XCTUnwrap(harness.session.store.tracks.first?.id)
        harness.session.tracksSelectionMode = true
        harness.session.tracksSelection.removeAll()
        drainMainRunLoop(seconds: 0.05)

        harness.window.makeKeyAndOrderFront(nil)
        drainMainRunLoop(seconds: 0.02)
        click(host: harness.hostingView, window: harness.window, at: NSPoint(x: 12, y: 90))

        XCTAssertTrue(
            harness.session.tracksSelection.contains(firstTrackID),
            "A click near the visible card's left edge must select the card, not fall through its padding."
        )
    }

    private func click(host: NSView, window: NSWindow, at point: NSPoint) {
        let location = host.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            window.sendEvent(event)
        }
        drainMainRunLoop(seconds: 0.02)
    }

    func test_generatorTriggerEditorExposesEuclideanControlsWithoutManualOrDisclosure() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/Generator/StepAlgoEditor.swift"),
            encoding: .utf8
        )
        let euclideanSection = try XCTUnwrap(
            source.slice(from: "case let .euclidean", to: "case let .manual"),
            "Euclidean trigger section should be present"
        )

        XCTAssertFalse(
            source.contains("showsSecondaryParameters"),
            "Euclidean Steps/Offset/Pitch must not be hidden behind disclosure state."
        )
        XCTAssertFalse(
            source.contains("StudioCircleIconButton"),
            "Trigger generator must not expose the old ellipsis/chevron parameter disclosure."
        )
        XCTAssertFalse(
            source.contains("title: \"Source\""),
            "The trigger algorithm chooser should not surface implementation wording as a Source label."
        )
        XCTAssertTrue(
            source.contains("private var visibleStepAlgoKinds: [StepAlgoKind] { [.euclidean, .weighted] }"),
            "Manual trigger controls are intentionally not part of this visible generator slice."
        )
        XCTAssertOrdered(
            ["title: \"Pulses\"", "title: \"Steps\"", "title: \"Offset\"", "title: \"Pitch\""],
            in: euclideanSection,
            message: "Euclidean trigger controls should render as the visible four-control set."
        )
    }

    func test_generatorPitchEditorStartsWithKeyboardThenUsesRotariesAndScaleMenu() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/Generator/PitchAlgoEditor.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains("SourceParameterStepperRow(title: \"Root\""),
            "Pitch Root should be a rotary, not the old stepper row."
        )
        XCTAssertFalse(
            source.contains("SourceParameterStepperRow(title: \"Spread\""),
            "Pitch Spread should be a rotary, not the old stepper row."
        )
        XCTAssertFalse(
            source.contains("SourceParameterSliderRow(title: \"Selection\""),
            "Pitch Selection should be a rotary, not the old slider row."
        )
        XCTAssertOrdered(
            [
                "PitchPoolKeyboardStrip(",
                "scaleControl(scale)",
                "title: \"Root\"",
                "title: \"Spread\"",
                "title: \"Selection\""
            ],
            in: source,
            message: "Pitch editing should start with the piano strip, put Scale on its own row, then render the numeric controls."
        )
        XCTAssertTrue(
            source.contains("LazyVGrid(columns: pitchColumns") &&
                source.contains("count: 8"),
            "Pitch rotaries should use an eight-column grid grammar instead of cramped rows."
        )
        XCTAssertTrue(
            source.contains("GeometryReader") &&
                source.contains("whiteKeyClasses") &&
                source.contains("blackKeySpecs") &&
                source.contains(".offset(x: whiteWidth * spec.boundary - blackWidth / 2)"),
            "The pitch keyboard should be full-width piano geometry with shorter black keys aligned to white-key boundaries."
        )
    }

    func test_generatorStageSelectorLivesInHeaderWithBake() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/Generator/GeneratorParamsEditorView.swift"),
            encoding: .utf8
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )
        let visualRunner = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/VisualScenarioCommandRunner.swift"),
            encoding: .utf8
        )
        let shell = try XCTUnwrap(
            source.slice(from: "private var foundationEditorShell", to: "private var generatorHeader"),
            "Generator shell source should be present"
        )
        let header = try XCTUnwrap(
            source.slice(from: "private var generatorHeader", to: "private var generatorStageSelector"),
            "Generator header source should be present"
        )

        XCTAssertFalse(
            shell.contains("StudioSegmentedControl("),
            "Trigger/Pitch switching should not render as a separate row below the generator header."
        )
        XCTAssertTrue(
            header.contains("generatorStageSelector"),
            "The shared generator header should contain the Trigger/Pitch stage selector."
        )
        XCTAssertFalse(
            source.contains("generatorKindMenu"),
            "Generator kind names should not render as a dropdown in the working generator surface."
        )
        XCTAssertTrue(
            header.contains("Label(\"Bake\""),
            "Bake should remain in the same generator header grammar."
        )
        XCTAssertTrue(
            qaScript.contains("22e-track-generator-trigger-tab|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip,trackGeneratorStage=trigger,trackSourceGeneratorRenderedStage=trigger"),
            "The trigger generator capture must wait for the rendered generator editor, not only selected command state."
        )
        XCTAssertTrue(
            qaScript.contains("22f-track-generator-pitch-tab|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip,trackGeneratorStage=pitch,trackSourceGeneratorRenderedStage=pitch"),
            "The pitch generator capture must wait for the rendered generator editor, not only selected command state."
        )
        XCTAssertTrue(
            visualRunner.contains("trackSourceGeneratorRenderedStage=\\("),
            "The visual status file should publish the rendered generator stage used by the QA waits."
        )
    }

    func test_emptyTrackSourceRendersInlineAddSourceAndHasCaptureRow() throws {
        let sourceTab = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/TrackSourceSourceTabContent.swift"),
            encoding: .utf8
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )
        let visualRunner = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/VisualScenarioCommandRunner.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            sourceTab.contains("case .empty:\n            addSourcePicker(step: sourcePickerStep ?? .root)"),
            "Empty source slots should render the Add Source chooser inline, not an intermediate empty well."
        )
        XCTAssertTrue(
            qaScript.contains("22a-track-add-source-empty"),
            "The standard QA surface pass should include the inline Add Source empty-slot state."
        )
        XCTAssertTrue(
            qaScript.contains("22a-track-add-source-empty|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip"),
            "The Add Source capture row should wait for the track source editor to render, not just for command state."
        )
        XCTAssertTrue(
            qaScript.contains("trackSourceAddSourceVisible=true"),
            "The Add Source capture row should wait on a status key that proves the intended state."
        )
        XCTAssertTrue(
            visualRunner.contains("trackSourceAddSourceVisible=\\("),
            "The visual command status file should publish the Add Source visibility key."
        )
    }

    func test_clipCaptureHistoryIsReachableFromToolbarAndCaptureRow() throws {
        let editor = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/TrackSourceEditorView.swift"),
            encoding: .utf8
        )
        let pills = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/TrackSourceSlotWellTabBar.swift"),
            encoding: .utf8
        )
        let clipPreview = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/Clip/ClipContentPreview.swift"),
            encoding: .utf8
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(
            editor.contains("case history") && editor.contains("case .history:\n                        clipHistoryTab"),
            "The implemented clip history view should remain reachable as the Capture button destination."
        )
        XCTAssertFalse(
            pills.contains("track-detail-tab-history"),
            "History should not remain a visible peer tab; Capture opens it as a workflow surface."
        )
        XCTAssertTrue(
            clipPreview.contains("Label(\"Capture\", systemImage: \"waveform.path.ecg\")"),
            "The clip toolbar should expose a Capture button that opens history."
        )
        XCTAssertFalse(
            clipPreview.contains("Label(\"Assign Macro\""),
            "The old inline Assign Macro button should not remain in the clip grid area."
        )
        XCTAssertTrue(
            qaScript.contains("22aa-track-clip-history"),
            "The standard QA surface pass should include the clip history state."
        )
        XCTAssertTrue(
            qaScript.contains("22aa-track-clip-history|workspace=track,trackSourceTab=history,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=history"),
            "The history capture row should wait for the history tab to render, not just for selected-tab command state."
        )
        XCTAssertTrue(
            qaScript.contains("trackClipHistoryFixture=selected"),
            "The history capture row should drive a selected populated history cell, not an empty tab."
        )
    }

    func test_samplerSoundPageRemovesStaleControlsAndCapturesRealWaveformState() throws {
        let samplerWidget = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/SamplerDestinationWidget.swift"),
            encoding: .utf8
        )
        let drumAccordion = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift"),
            encoding: .utf8
        )
        let chooserPanel = try XCTUnwrap(
            drumAccordion.slice(from: "func expandedSoundChooserPanel", to: "func expandedSoundSamplerPanel"),
            "Drum-part empty sound chooser should be present"
        )
        let samplerPanel = try XCTUnwrap(
            drumAccordion.slice(from: "func expandedSoundSamplerPanel", to: "func expandedSoundAUPanel"),
            "Drum-part sampler sound panel should be present"
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )
        let visualRunner = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/VisualScenarioCommandRunner.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            samplerWidget.contains("WaveformView(buckets: buckets, fillColor: accent)"),
            "Sampler sound pages must keep the actual waveform renderer in the populated sample card."
        )
        XCTAssertFalse(
            samplerWidget.contains(".fill(StudioTheme.subtleFill)\n                    .frame(width: max(0, stopX - startX), height: height)"),
            "The start/length overlay must not paint an opaque region over the sampler waveform."
        )
        XCTAssertFalse(
            samplerWidget.contains("View built-in sampler macros"),
            "The sampler header must not keep the old config/macro button beside Play."
        )
        XCTAssertFalse(
            samplerWidget.contains("systemName: \"slider.horizontal.3\""),
            "The sampler header must not render the old config/macro icon."
        )
        XCTAssertTrue(
            chooserPanel.contains("HStack(alignment: .top"),
            "Empty drum-part sound state should place the two add choices side by side."
        )
        XCTAssertEqual(
            chooserPanel.components(separatedBy: "StudioAddCard(").count - 1,
            2,
            "Empty drum-part sound state should offer two dashed plus boxes."
        )
        XCTAssertFalse(
            chooserPanel.contains("No sound source"),
            "The empty drum-part sound state should not show the old text label."
        )
        XCTAssertFalse(
            samplerPanel.contains("Load AU instrument"),
            "Sampler parts should not keep the bottom Load AU instrument button."
        )
        XCTAssertFalse(
            samplerPanel.contains("kit-row-load-au"),
            "The removed bottom Load AU button should not leave an accessibility target behind."
        )
        XCTAssertTrue(
            qaScript.contains("SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES"),
            "QA captures must materialize audio-rich fixture WAVs so sampler waveforms draw non-zero buckets."
        )
        XCTAssertTrue(
            qaScript.contains("19-track-sampler-sound-populated") &&
                qaScript.contains("trackSourceEditorRenderedVisible=true") &&
                qaScript.contains("trackSourceEditorRenderedTab=sound") &&
                qaScript.contains("selectedTrackSoundDestinationKind=sample") &&
                qaScript.contains("trackSoundSource=sample"),
            "QA coverage should include a populated sampler sound page, not a generator sound page."
        )
        XCTAssertTrue(
            qaScript.contains("19a-track-sound-empty") &&
                qaScript.contains("trackSourceEditorRenderedVisible=true") &&
                qaScript.contains("trackSourceEditorRenderedTab=sound") &&
                qaScript.contains("selectedTrackSoundDestinationKind=none") &&
                qaScript.contains("trackSoundSource=empty"),
            "QA coverage should include the empty sound-source chooser state."
        )
        XCTAssertTrue(
            visualRunner.contains("case \"sample\", \"sampler\":") &&
                visualRunner.contains(".sample(sampleID: sample.id, settings: .default)"),
            "The visual command runner should be able to drive the sampler sound capture state directly."
        )
    }

    func test_drumKitRowHeaderKeepsPartNameTopAlignedAndRemovesLengthSubtext() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/DrumGroup/DrumKitMatrixRowView.swift"),
            encoding: .utf8
        )
        let nameColumn = try XCTUnwrap(
            source.slice(from: "private var nameColumn", to: "@ViewBuilder\n    private var readOnlyBadge"),
            "Drum-kit row name column should be present"
        )

        XCTAssertTrue(
            source.contains("HStack(alignment: .top, spacing: 10)"),
            "The drum-part name column should stay top-aligned in both compact and expanded rows."
        )
        XCTAssertTrue(
            nameColumn.contains("Text(row.partName)\n                        .studioText(.subtitle)"),
            "The drum-part name should be larger than the old compact label text."
        )
        XCTAssertFalse(
            nameColumn.contains("clipLengthLabel"),
            "The compact grey clip-length subtext should not render beneath the drum-part name."
        )
        XCTAssertFalse(
            nameColumn.contains("kit-row-clip-length"),
            "The removed clip-length subtext should not leave an accessibility target behind."
        )
    }

    func test_drumKitGeneratorModeUsesSharedGeneratorEditorAndHasCaptureRow() throws {
        let accordion = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift"),
            encoding: .utf8
        )
        let sourceSwitch = try XCTUnwrap(
            accordion.slice(from: "func sourceModeSwitch", to: "func setMemberSourceMode"),
            "Drum-kit source mode switch should be present"
        )
        let generatorBody = try XCTUnwrap(
            accordion.slice(from: "func expandedGeneratorBody", to: "func memberSourceGenerator"),
            "Drum-kit expanded generator body should be present"
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )
        let visualRunner = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/VisualScenarioCommandRunner.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            sourceSwitch.contains("Text(\"SOURCE\")"),
            "The drum-part Clip/Generator switch should not show the old Source label."
        )
        XCTAssertTrue(
            generatorBody.contains("GeneratorParamsEditorView(") &&
                generatorBody.contains("layout: .sourceContained"),
            "Drum-part generator mode should reuse the shared mono-track generator controls."
        )
        XCTAssertFalse(
            generatorBody.contains("MODIFIER") ||
                generatorBody.contains("Add modifier") ||
                generatorBody.contains("kit-row-add-modifier"),
            "The drum-part generator row should not expose modifier controls in this slice."
        )
        XCTAssertTrue(
            qaScript.contains("29d-drum-kit-expanded-generator") &&
                qaScript.contains("drumKitMatrixRenderedVisible=true") &&
                qaScript.contains("drumKitMatrixRenderedExpandedSourceMode=generator") &&
                qaScript.contains("drumKitMatrixCommands=expand-part:0,row-tab-steps,source-generator"),
            "QA coverage should include the expanded drum-part generator mode with strict status waits."
        )
        XCTAssertTrue(
            visualRunner.contains("drumKitMatrixRenderedExpandedSourceMode"),
            "The visual status file should publish expanded source mode for the generator capture wait."
        )
    }

    func test_drumKitCaptureUsesSingleHistoryBarWithoutAuditionOrLive() throws {
        let capture = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/DrumGroup/DrumKitMatrixView+Capture.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(
            capture.slice(from: "func captureHistoryBody", to: "func captureSnapshots"),
            "Drum-kit capture body should be present"
        )
        let bar = try XCTUnwrap(
            capture.slice(from: "func captureHistoryBar", to: "func captureHistoryMiniBar"),
            "Drum-kit capture bar should be present"
        )
        let cellStrip = try XCTUnwrap(
            capture.slice(from: "func captureHistoryCellStrip", to: "    /// Shared Preview/Audition toggle"),
            "Drum-kit capture cell strip should be present"
        )
        let qaScript = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/visual-scenarios/qa-surface-coverage.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(
            body.contains("captureHistoryBar(model, snapshots: snapshots)"),
            "The capture surface should render one combined capture bar."
        )
        XCTAssertFalse(
            body.contains("captureHistoryHeader") || body.contains("captureHistoryScrubber"),
            "The old separate header/scrubber rows should not be part of the visible capture body."
        )
        XCTAssertTrue(
            bar.contains("captureHistoryCellStrip(model, snapshots: snapshots)") &&
                bar.contains("historyLengthControl") &&
                bar.contains("Label(isSelectingCaptureSaveSlot ? \"Choose slot\" : \"Save\"") &&
                bar.contains("systemName: \"xmark\""),
            "The single capture bar should contain track-style history cells, length, save, and the close cross."
        )
        XCTAssertFalse(
            bar.contains("Audition") || bar.contains("Live"),
            "Audition and Live controls should not be visible in the active capture bar."
        )
        XCTAssertTrue(
            cellStrip.contains("KitHistoryMinibarCell") &&
                cellStrip.contains("historyNavigationCellCount") &&
                cellStrip.contains("kitHistoryCellPartStepStates") &&
                cellStrip.contains("historyBarsBack = back") &&
                cellStrip.contains("kit-history-cell-\\(index)"),
            "Selecting a kit history cell should change the displayed history window across the 16-cell part matrix."
        )
        XCTAssertFalse(
            capture.slice(from: "private struct KitHistoryMinibarCell", to: "private struct KitHistoryMiniStepThumbnail")?.contains("Text(") ?? true,
            "Kit history cells should render as text-free mini part matrices."
        )
        XCTAssertTrue(
            bar.contains("isSelectingCaptureSaveSlot = true"),
            "Save should arm pattern-slot targeting instead of toggling it off on a second click."
        )
        XCTAssertTrue(
            qaScript.contains("29f-drum-kit-capture-save-slot") &&
                qaScript.contains("history-save-open") &&
                !qaScript.contains("29f-drum-kit-capture-save-slot|workspace=track,drumKitMatrixRenderedCaptureOpen=true,drumKitMatrixRenderedSaveSlotPickerVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=open-capture,history-fixture,history-audition-on"),
            "The QA capture row should cover save-slot targeting without opening the removed audition state."
        )
    }

    func test_createTrackGroupSheetOmitsSelectedTrackPills() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TracksMatrixView.swift"),
            encoding: .utf8
        )
        let sheet = try XCTUnwrap(
            source.slice(
                from: "private func createPerformanceTrackGroupSheet",
                to: "    private func performanceTrackGroupSlot"
            )
        )

        XCTAssertTrue(sheet.contains("LazyVGrid("))
        XCTAssertFalse(sheet.contains("ForEach(selectedTracks"))
        XCTAssertFalse(sheet.contains("Capsule()"))
    }

    func test_addDrumGroupMenusHideNativeIndicators() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/DrumGroup/AddDrumGroupContent.swift"),
            encoding: .utf8
        )
        let menus = try XCTUnwrap(
            source.slice(from: "private func tagMenu", to: "    private func soundLabel")
        )

        XCTAssertEqual(menus.components(separatedBy: ".menuIndicator(.hidden)").count - 1, 2)
        XCTAssertEqual(menus.components(separatedBy: "Image(systemName: \"chevron.down\")").count - 1, 1)
    }

    func test_phraseCrossfaderUsesRoundedSharedSlideControl() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/PhraseWorkspaceView.swift"),
            encoding: .utf8
        )
        let crossfader = try XCTUnwrap(
            source.slice(from: "private func phraseSceneCrossfader", to: "    // Slots mode:")
        )

        XCTAssertTrue(crossfader.contains("StudioSlideControl("))
        XCTAssertTrue(crossfader.contains("chrome: .roundedRectangle"))
        XCTAssertFalse(source.contains("private struct PhraseSceneCrossfaderTrack"))
    }

    func test_clipLengthControlUsesCompressedSegmentGeometry() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/TrackSource/Clip/ClipContentPreview.swift"),
            encoding: .utf8
        )
        let controls = try XCTUnwrap(
            source.slice(from: "private func clipHeaderControls", to: "    private func pitchKeyboard")
        )

        XCTAssertTrue(controls.contains("minWidth: 28"))
        XCTAssertTrue(controls.contains("horizontalPadding: StudioMetrics.Spacing.hairline"))
    }

    func test_sliceSourceModalUsesSharedStudioControlsAndTrackAccent() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/Slicer/SliceTrackWorkspaceView.swift"),
            encoding: .utf8
        )
        let sharedControls = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/UI/Theme/StudioControls.swift"),
            encoding: .utf8
        )
        let modal = try XCTUnwrap(
            source.slice(from: "private var sliceModal", to: "    // MARK: - Slice browsing")
        )
        let detection = try XCTUnwrap(
            source.slice(from: "private func autoDetectControls", to: "    // Slice count")
        )

        XCTAssertTrue(modal.contains("StudioSlideControl("))
        XCTAssertTrue(modal.contains("chrome: .roundedRectangle"))
        XCTAssertTrue(detection.contains("StudioSegmentedControl("))
        XCTAssertTrue(modal.contains("StudioCommandButton("))
        XCTAssertTrue(modal.contains("accent: accent"))
        XCTAssertFalse(modal.contains("\n            Slider("))
        XCTAssertFalse(detection.contains("\n                    Slider("))
        XCTAssertFalse(detection.contains("Picker("))
        XCTAssertFalse(modal.contains(".buttonStyle(.bordered"))
        XCTAssertTrue(sharedControls.contains("struct StudioCommandButton: View"))
    }
}

final class TracksNavigatorPresentationTests: XCTestCase {
    func test_filtersClassifyEveryTrackCategoryWithGroupMembershipTakingPrecedence() {
        let fixture = makeFixture()

        XCTAssertEqual(trackIDs(for: .mono, fixture: fixture), [fixture.mono.id])
        XCTAssertEqual(trackIDs(for: .poly, fixture: fixture), [fixture.poly.id])
        XCTAssertEqual(trackIDs(for: .chord, fixture: fixture), [fixture.chord.id])
        XCTAssertEqual(trackIDs(for: .slicer, fixture: fixture), [fixture.slicer.id])
        XCTAssertEqual(trackIDs(for: .audio, fixture: fixture), [fixture.audio.id])
        XCTAssertEqual(
            TracksNavigatorPresentation.items(
                tracks: fixture.tracks,
                groups: [fixture.group],
                filter: .drumKits
            ),
            [.kit(fixture.group.id)]
        )
        XCTAssertEqual(
            trackIDs(for: .drumParts, fixture: fixture),
            [fixture.groupedPoly.id, fixture.groupedMono.id],
            "Group member order wins, and grouped melodic tracks classify only as drum parts."
        )
    }

    func test_allAndDrumFiltersPreserveStablePresentationOrderWithoutMutatingInput() {
        let fixture = makeFixture()
        let originalTracks = fixture.tracks
        let originalGroups = [fixture.group]

        let collapsed = TracksNavigatorPresentation.items(
            tracks: fixture.tracks,
            groups: originalGroups,
            filter: .all
        )
        XCTAssertEqual(
            collapsed,
            [
                .track(fixture.mono.id), .track(fixture.poly.id),
                .track(fixture.chord.id), .track(fixture.slicer.id),
                .track(fixture.audio.id), .kit(fixture.group.id)
            ]
        )

        let expanded = TracksNavigatorPresentation.items(
            tracks: fixture.tracks,
            groups: originalGroups,
            filter: .all,
            forceExpandedGroups: [fixture.group.id]
        )
        XCTAssertEqual(
            Array(expanded.suffix(3)),
            [.kit(fixture.group.id), .track(fixture.groupedPoly.id), .track(fixture.groupedMono.id)]
        )
        XCTAssertEqual(fixture.tracks, originalTracks)
        XCTAssertEqual(originalGroups, [fixture.group])
    }

    func test_visibleTrackIDsExpandKitRepresentativesWithoutChangingSelectionOrGroupState() {
        let fixture = makeFixture()
        let items = TracksNavigatorPresentation.items(
            tracks: fixture.tracks,
            groups: [fixture.group],
            filter: .drumKits
        )
        let selection = Set([fixture.mono.id, fixture.groupedMono.id])

        XCTAssertEqual(
            TracksNavigatorPresentation.visibleTrackIDs(
                in: items,
                tracks: fixture.tracks,
                groups: [fixture.group]
            ),
            [fixture.groupedPoly.id, fixture.groupedMono.id]
        )
        XCTAssertEqual(selection, Set([fixture.mono.id, fixture.groupedMono.id]))
        XCTAssertTrue(fixture.group.isPatternLinked)
    }

    private func trackIDs(
        for filter: TracksNavigatorFilter,
        fixture: Fixture
    ) -> [UUID] {
        TracksNavigatorPresentation.items(
            tracks: fixture.tracks,
            groups: [fixture.group],
            filter: filter
        ).compactMap { item in
            guard case .track(let id) = item else { return nil }
            return id
        }
    }

    private struct Fixture {
        let mono: StepSequenceTrack
        let poly: StepSequenceTrack
        let chord: StepSequenceTrack
        let slicer: StepSequenceTrack
        let audio: StepSequenceTrack
        let groupedMono: StepSequenceTrack
        let groupedPoly: StepSequenceTrack
        let group: TrackGroup

        var tracks: [StepSequenceTrack] {
            [mono, groupedMono, poly, chord, slicer, audio, groupedPoly]
        }
    }

    private func makeFixture() -> Fixture {
        let groupID = UUID()
        let mono = track("Mono", type: .monoMelodic)
        let groupedMono = track("Kick", type: .monoMelodic, groupID: groupID)
        let poly = track("Poly", type: .polyMelodic)
        let chord = track("Chord", type: .chord)
        let slicer = track("Slicer", type: .slice)
        let audio = track("Audio", type: .audioInput)
        let groupedPoly = track("Snare", type: .polyMelodic, groupID: groupID)
        let group = TrackGroup(
            id: groupID,
            name: "Kit",
            memberIDs: [groupedPoly.id, groupedMono.id]
        )
        return Fixture(
            mono: mono,
            poly: poly,
            chord: chord,
            slicer: slicer,
            audio: audio,
            groupedMono: groupedMono,
            groupedPoly: groupedPoly,
            group: group
        )
    }

    private func track(
        _ name: String,
        type: TrackType,
        groupID: TrackGroupID? = nil
    ) -> StepSequenceTrack {
        StepSequenceTrack(
            name: name,
            trackType: type,
            pitches: [60],
            stepPattern: [true, false, false, false],
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}

private func XCTAssertOrdered(
    _ needles: [String],
    in haystack: String,
    message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var lowerBound = haystack.startIndex
    for needle in needles {
        guard let range = haystack.range(of: needle, range: lowerBound..<haystack.endIndex) else {
            XCTFail("\(message) Missing ordered token: \(needle)", file: file, line: line)
            return
        }
        lowerBound = range.upperBound
    }
}
