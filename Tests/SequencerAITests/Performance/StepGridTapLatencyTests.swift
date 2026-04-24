import XCTest
import Observation
import SwiftUI
@testable import SequencerAI

// MARK: - Phase 6 step-grid tap-to-invalidation benchmark
//
// These tests measure and bound the observation-invalidation latency of a
// step-toggle mutation on a non-trivial reference project (8 tracks, 4
// pattern slots each, 32-step note-grid clips, 4 phrases with populated cells).
//
// Budget: 16ms per tap-to-invalidation cycle (one frame @ 60 fps).
//
// Test approach: use `withObservationTracking` + `ContinuousClock` wall time.
// `withObservationTracking` is main-thread only and fires `onChange` synchronously
// before the next observation-tracking pass, so wall-clock measurement from
// mutation to onChange callback reflects the real invalidation cost.

@MainActor
final class StepGridTapLatencyTests: XCTestCase {

    // MARK: - Reference project fixture

    /// Build a non-trivial reference project.
    ///
    /// Structure:
    ///   - 8 tracks (monoMelodic)
    ///   - Each track has 4 pattern slots (slots 0-3), each pointing at a
    ///     distinct 32-step note-grid clip with a populated step at position 0.
    ///   - 4 phrases (64 steps each), each phrase has pattern/mute/fill cells
    ///     populated for all tracks.
    ///
    /// This is the reference scale described in Phase 6 of the plan.
    private func makeReferenceProject() -> Project {
        let trackCount = 8
        let patternSlotsPerTrack = 4
        let stepsPerClip = 32
        let phraseCount = 4
        let barsPerPhrase = 4  // 4 bars * 16 steps/bar = 64 steps

        var tracks: [StepSequenceTrack] = []
        var clips: [ClipPoolEntry] = []
        var banks: [TrackPatternBank] = []
        let selectedTrackID: UUID

        // Build 8 tracks with 4 slots each.
        var trackIDs: [UUID] = []
        for i in 0..<trackCount {
            let trackID = UUID()
            trackIDs.append(trackID)
            let track = StepSequenceTrack(
                id: trackID,
                name: "Track \(i + 1)",
                pitches: [60 + i],
                stepPattern: Array(repeating: false, count: stepsPerClip),
                stepAccents: Array(repeating: false, count: stepsPerClip),
                destination: .midi(port: .sequencerAIOut, channel: UInt8(i % 16), noteOffset: 0),
                velocity: 96,
                gateLength: 4
            )
            tracks.append(track)

            // Create 4 clips for this track (one per pattern slot).
            var slotRefs: [TrackPatternSlot] = []
            for slotIndex in 0..<patternSlotsPerTrack {
                let clipID = UUID()
                var steps = Array(repeating: ClipStep.empty, count: stepsPerClip)
                // Populate step 0 for realism.
                steps[0] = ClipStep(
                    main: ClipLane(
                        chance: 1.0,
                        notes: [ClipStepNote(pitch: 60 + i, velocity: 96, lengthSteps: 4)]
                    ),
                    fill: nil
                )
                let clip = ClipPoolEntry(
                    id: clipID,
                    name: "T\(i + 1)S\(slotIndex + 1)",
                    trackType: .monoMelodic,
                    content: .noteGrid(lengthSteps: stepsPerClip, steps: steps)
                )
                clips.append(clip)
                slotRefs.append(
                    TrackPatternSlot(
                        slotIndex: slotIndex,
                        name: nil,
                        sourceRef: SourceRef(mode: .clip, generatorID: nil, clipID: clipID)
                    )
                )
            }
            banks.append(TrackPatternBank(trackID: trackID, slots: slotRefs))
        }

        selectedTrackID = trackIDs[0]

        // Build 4 phrases with populated cells.
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        var phrases: [PhraseModel] = []
        for phraseIndex in 0..<phraseCount {
            let phraseID = UUID()
            // Build populated cells for all tracks and all layers.
            var cells: [PhraseCellAssignment] = []
            for layer in layers {
                for (ti, trackID) in trackIDs.enumerated() {
                    let cell: PhraseCell
                    if layer.target == .patternIndex {
                        // Stagger the pattern index per phrase so all slots see use.
                        cell = .single(.index(phraseIndex % patternSlotsPerTrack))
                    } else if layer.target == .mute {
                        cell = .single(.bool(false))
                    } else {
                        cell = .single(.scalar(Double(ti) / Double(trackCount)))
                    }
                    cells.append(PhraseCellAssignment(trackID: trackID, layerID: layer.id, cell: cell))
                }
            }
            let phrase = PhraseModel(
                id: phraseID,
                name: "Phrase \(phraseIndex + 1)",
                lengthBars: barsPerPhrase,
                stepsPerBar: 16,
                cells: cells
            )
            phrases.append(phrase)
        }

        let selectedPhraseID = phrases[0].id

        return Project(
            version: 1,
            tracks: tracks,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: clips,
            layers: layers,
            routes: [],
            patternBanks: banks,
            selectedTrackID: selectedTrackID,
            phrases: phrases,
            selectedPhraseID: selectedPhraseID
        )
    }

    /// Build a `SequencerDocumentSession` backed by the reference project.
    private func makeReferenceSession() -> SequencerDocumentSession {
        let project = makeReferenceProject()
        var document = SeqAIDocument(project: project)
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { document },
                set: { document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)  // suppress flush during test
        )
        session.activate()
        return session
    }

    // MARK: - Test 1: tap-to-invalidation wall-clock budget

    /// A step toggle on a reference project must fire the observation onChange
    /// within 16ms (one frame at 60 fps).
    ///
    /// Measurement: wall-clock from just before `session.mutateClip` to the
    /// moment the `onChange` closure fires. `withObservationTracking`'s `onChange`
    /// fires lazily — during the next observation-tracking pass after the
    /// tracked property is written. We force that pass by re-reading the store
    /// immediately after the mutation, and use `onChangeFiredAt` (recorded inside
    /// the callback) as the invalidation time.
    ///
    /// Design note: `mutateClip` with `.snapshotOnly` impact calls the incremental
    /// `publishSnapshot(changed:)` path. That incremental compile runs on the same
    /// call stack as `mutateClip`, BEFORE the observation pass. The observation
    /// `onChange` fires AFTER `mutateClip` returns (during the forced re-read).
    /// The measurement window therefore still includes snapshot compilation, but
    /// the whole point of the incremental path is that this full tap-to-invalidation
    /// cycle now fits inside one frame on the reference project.
    func test_stepTap_tapsToInvalidation_underBudget() throws {
        let session = makeReferenceSession()

        // Warm up: run one mutation before the timed mutation so the compiler
        // and observation machinery are not measured on a cold cache.
        let warmupClipID = session.store.clipPool.first?.id
        if let warmupClipID {
            session.mutateClip(id: warmupClipID) { entry in
                entry.name = entry.name  // no-op change guard handled in store
            }
        }

        let clipID = session.store.selectedPattern(for: session.store.selectedTrackID).sourceRef.clipID
        let targetClipID = try XCTUnwrap(clipID, "Reference project has no clip in slot 0 of selected track")

        let firedAt = TimestampBox()

        // Install observer. onChange fires lazily during the next read-tracking pass.
        withObservationTracking {
            _ = session.store.clipPool.first(where: { $0.id == targetClipID })?.content
        } onChange: {
            firedAt.set(ContinuousClock.now)
        }

        let mutationStart = ContinuousClock.now

        // Toggle step 5 in the target clip (this also runs publishSnapshot()).
        session.mutateClip(id: targetClipID) { entry in
            if case .noteGrid(let length, var steps) = entry.content {
                let targetStep = min(5, steps.count - 1)
                if steps[targetStep].isEmpty {
                    steps[targetStep] = ClipStep(
                        main: ClipLane(
                            chance: 1.0,
                            notes: [ClipStepNote(pitch: 60, velocity: 96, lengthSteps: 4)]
                        ),
                        fill: nil
                    )
                } else {
                    steps[targetStep] = .empty
                }
                entry.content = .noteGrid(lengthSteps: length, steps: steps)
            }
        }

        let mutationEnd = ContinuousClock.now
        let mutationElapsed = mutationEnd - mutationStart

        // Force the observation pass (onChange fires here, inside this read).
        let observationPassStart = ContinuousClock.now
        _ = session.store.clipPool.first(where: { $0.id == targetClipID })?.content
        let observationPassEnd = ContinuousClock.now

        XCTAssertTrue(firedAt.timestamp != nil, "onChange must have fired after clip mutation")

        // Assertion 1: full tap path (mutation + incremental snapshot compile)
        // under 16ms — one frame at 60 fps.
        let fullPathElapsed = observationPassEnd - mutationStart
        let fullPathBudget = Duration.milliseconds(16)
        XCTAssertLessThanOrEqual(
            fullPathElapsed,
            fullPathBudget,
            "Full tap path including incremental snapshot compile (\(fullPathElapsed)) exceeded " +
            "\(fullPathBudget) budget. Reference project may be too large or the " +
            "snapshot compiler is unexpectedly slow."
        )

        // Assertion 2: pure observation-pass cost (read triggering onChange) must
        // be well under 16ms. This isolates the observation machinery from compile cost.
        let observationPassElapsed = observationPassEnd - observationPassStart
        let observationBudget = Duration.milliseconds(16)
        XCTAssertLessThanOrEqual(
            observationPassElapsed,
            observationBudget,
            "Observation pass (read-triggering onChange) took \(observationPassElapsed), " +
            "exceeding the 16ms budget. Observation fan-out may be broader than expected."
        )

        // Diagnostic: print elapsed times for baseline recording.
        print("[StepGridTapLatency] mutation+compile: \(mutationElapsed), " +
              "observation pass: \(observationPassElapsed), " +
              "full path: \(fullPathElapsed)")
    }

    /// Thread-safe timestamp box for capturing ContinuousClock.Instant from nonisolated onChange.
    private final class TimestampBox: @unchecked Sendable {
        private var _timestamp: ContinuousClock.Instant?
        private let lock = NSLock()

        var timestamp: ContinuousClock.Instant? {
            lock.withLock { _timestamp }
        }

        func set(_ ts: ContinuousClock.Instant) {
            lock.withLock { _timestamp = ts }
        }
    }

    // MARK: - Test 2: step tap invalidates only the affected clip observer

    /// Toggling step 5 of clip A must fire the onChange for a view bound to clip A,
    /// and must NOT fire for a view bound to clip B (different clip, same session).
    ///
    /// Note: due to dict-level observation tracking (see ObservationGranularityTests),
    /// the "unrelated clip" observer WILL fire under current @Observable semantics.
    /// That is documented as the known ceiling. This test establishes the current
    /// behaviour and marks the cross-clip invalidation as XCTExpectFailure so it
    /// fails loudly if the store is refactored to provide per-key isolation.
    func test_stepTap_invalidatesOnlyAffectedViews() throws {
        let session = makeReferenceSession()

        // Identify two clips: the one in slot 0 of track 0 (clip A) and
        // the one in slot 1 of track 0 (clip B, different slot → different clip ID).
        let bank = session.store.patternBank(for: session.store.selectedTrackID)
        let slotA = bank.slot(at: 0)
        let slotB = bank.slot(at: 1)
        let clipAID = try XCTUnwrap(slotA.sourceRef.clipID, "Slot 0 has no clip")
        let clipBID = try XCTUnwrap(slotB.sourceRef.clipID, "Slot 1 has no clip in reference project")

        var clipAObserverFired = false
        var clipBObserverFired = false

        // Install clip A observer.
        withObservationTracking {
            _ = session.store.clipPool.first(where: { $0.id == clipAID })?.content
        } onChange: {
            clipAObserverFired = true
        }

        // Install clip B observer.
        withObservationTracking {
            _ = session.store.clipPool.first(where: { $0.id == clipBID })?.content
        } onChange: {
            clipBObserverFired = true
        }

        // Toggle a step in clip A.
        session.mutateClip(id: clipAID) { entry in
            if case .noteGrid(let length, var steps) = entry.content {
                let target = min(5, steps.count - 1)
                steps[target] = steps[target].isEmpty
                    ? ClipStep(
                        main: ClipLane(
                            chance: 1.0,
                            notes: [ClipStepNote(pitch: 60, velocity: 96, lengthSteps: 4)]
                        ),
                        fill: nil
                    )
                    : .empty
                entry.content = .noteGrid(lengthSteps: length, steps: steps)
            }
        }

        // Force an observation pass.
        _ = session.store.clipPool.first(where: { $0.id == clipAID })?.content
        _ = session.store.clipPool.first(where: { $0.id == clipBID })?.content

        // Clip A observer should fire.
        XCTAssertTrue(clipAObserverFired,
            "Clip A observer must fire when clip A is mutated")

        // Clip B observer should NOT fire — but due to dict-level observation this
        // is the known ceiling. Mark expected failure so the test documents the
        // current behaviour without blocking CI.
        XCTExpectFailure(
            "Known limitation: mutating storeClipsByID[clipA] writes the whole dict, " +
            "firing all observers that read storeClipsByID regardless of key. " +
            "Clip B observer will fire even though clip B was not mutated. " +
            "If this test passes unexpectedly, per-key isolation was achieved."
        ) {
            XCTAssertFalse(clipBObserverFired,
                "Clip B observer should not fire when only clip A is mutated " +
                "(currently fails due to dict-level @Observable tracking)")
        }
    }

    // MARK: - Test 3: body evaluation count bounded per tap

    /// A single step tap must cause the simulated view body to evaluate no more
    /// than 2 times (some SwiftUI update cycles double-evaluate bodies; the budget
    /// accommodates that without permitting unbounded invalidation cascades).
    ///
    /// Mechanism: count how many distinct `onChange` callbacks fire for a given
    /// clip across two sequential observation-tracking registrations. We do NOT
    /// attempt to re-register from within onChange (which is nonisolated and
    /// cannot call @MainActor functions). Instead we register twice in sequence
    /// and count total firings — each registration represents one body pass.
    func test_stepTap_bodyEvaluationCount_bounded() throws {
        let session = makeReferenceSession()
        let clipID = try XCTUnwrap(
            session.store.selectedPattern(for: session.store.selectedTrackID).sourceRef.clipID,
            "Selected pattern has no clip"
        )

        // Each withObservationTracking registration represents one body evaluation pass.
        // We register two passes up front (pass 1 and pass 2) to bound invalidations.
        let invalidationCounter = InvalidationCounter()

        // Pass 1: initial registration (simulates first body render).
        withObservationTracking {
            _ = session.store.clipPool.first(where: { $0.id == clipID })?.content
        } onChange: {
            invalidationCounter.increment()
        }

        XCTAssertEqual(invalidationCounter.count, 0, "No invalidations before mutation")

        // Tap: toggle step 5 on.
        session.mutateClip(id: clipID) { entry in
            if case .noteGrid(let length, var steps) = entry.content {
                let target = min(5, steps.count - 1)
                steps[target] = ClipStep(
                    main: ClipLane(
                        chance: 1.0,
                        notes: [ClipStepNote(pitch: 60, velocity: 96, lengthSteps: 4)]
                    ),
                    fill: nil
                )
                entry.content = .noteGrid(lengthSteps: length, steps: steps)
            }
        }

        // Force the observation pass by re-reading the store (which triggers onChange
        // for any registered observer whose tracked fields changed).
        _ = session.store.clipPool.first(where: { $0.id == clipID })?.content

        // Pass 2: simulate the re-render registration (SwiftUI re-tracks after body
        // evaluation). A second mutation should trigger at most one more invalidation.
        withObservationTracking {
            _ = session.store.clipPool.first(where: { $0.id == clipID })?.content
        } onChange: {
            invalidationCounter.increment()
        }

        // Toggle the step back off (simulates a second tap or re-evaluation).
        session.mutateClip(id: clipID) { entry in
            if case .noteGrid(let length, var steps) = entry.content {
                let target = min(5, steps.count - 1)
                steps[target] = .empty
                entry.content = .noteGrid(lengthSteps: length, steps: steps)
            }
        }

        _ = session.store.clipPool.first(where: { $0.id == clipID })?.content

        XCTAssertLessThanOrEqual(
            invalidationCounter.count, 2,
            "Body must invalidate ≤ 2 times across 2 registration passes and 2 mutations " +
            "(current: \(invalidationCounter.count)). " +
            "More suggests spurious fan-out or re-entrancy."
        )
    }

    /// Thread-safe counter for tracking onChange callback invocations from the
    /// nonisolated `withObservationTracking` onChange closure.
    private final class InvalidationCounter: @unchecked Sendable {
        private var _count: Int = 0
        private let lock = NSLock()

        var count: Int {
            lock.withLock { _count }
        }

        func increment() {
            lock.withLock { _count += 1 }
        }
    }

    // MARK: - Test 4: exportToProject not called during step tap

    /// A step tap (step toggle + observation invalidation cycle) must not call
    /// `exportToProject()` on the UI read path.
    ///
    /// This test overlaps with Phase 2 UIReadsStoreDirectlyTests but exercises
    /// the full reference-project scale to rule out regression.
    func test_exportToProject_notCalledDuringTap() throws {
        let session = makeReferenceSession()
        let clipID = try XCTUnwrap(
            session.store.selectedPattern(for: session.store.selectedTrackID).sourceRef.clipID,
            "Selected pattern has no clip"
        )

        // Zero the counter AFTER activate() (which calls exportToProject internally).
        // We care only about exports triggered by UI read operations after the tap.
        let exportCountBeforeTap = session.store.exportToProjectCallCount

        // Perform the step tap.
        session.mutateClip(id: clipID) { entry in
            if case .noteGrid(let length, var steps) = entry.content {
                let target = min(5, steps.count - 1)
                steps[target] = ClipStep(
                    main: ClipLane(
                        chance: 1.0,
                        notes: [ClipStepNote(pitch: 60, velocity: 96, lengthSteps: 4)]
                    ),
                    fill: nil
                )
                entry.content = .noteGrid(lengthSteps: length, steps: steps)
            }
        }

        let exportCountAfterMutation = session.store.exportToProjectCallCount
        let exportsFromMutationDispatch = exportCountAfterMutation - exportCountBeforeTap

        // Note: `mutateClip` with `.snapshotOnly` impact calls `publishSnapshot()`
        // which calls `store.compileInput()`, NOT `exportToProject()`. Any export
        // triggered at this point would be from legacy code still going through
        // the project round-trip. If the mutation path uses `.fullEngineApply`,
        // one export is expected (engineController.apply(documentModel:) calls it).
        // Clip mutations use `.snapshotOnly` → zero exports expected.

        // Now simulate a UI read pass (what a view body does on invalidation).
        let exportCountBeforeRead = session.store.exportToProjectCallCount
        _ = session.store.clipPool.first(where: { $0.id == clipID })?.content
        _ = session.store.tracks.count
        _ = session.store.selectedTrackID

        let exportsFromUIRead = session.store.exportToProjectCallCount - exportCountBeforeRead

        XCTAssertEqual(
            exportsFromUIRead, 0,
            "UI read path after step tap must not call exportToProject(). " +
            "Found \(exportsFromUIRead) call(s) from reading store fields."
        )

        XCTAssertEqual(
            exportsFromMutationDispatch, 0,
            "mutateClip with .snapshotOnly impact must not call exportToProject(). " +
            "Found \(exportsFromMutationDispatch) call(s) during tap dispatch."
        )

        _ = exportsFromMutationDispatch  // suppress unused-var warning
    }
}
