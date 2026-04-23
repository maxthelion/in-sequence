import XCTest
import Observation
@testable import SequencerAI

// MARK: - Phase 5 observation granularity tests
//
// Each test verifies that a mutation to one domain object (clip A, track A, phrase A)
// does NOT fire the onChange closure of an observer bound to a different domain object
// (clip B, track B, phrase B).
//
// Mechanism: `withObservationTracking { <read> } onChange: { ... }` registers a
// one-shot subscription. If the onChange fires before we explicitly check `didFire`,
// the subscription was broader than expected.
//
// Key invariant about Swift's @Observable macro:
//   - A read of a stored property (e.g. `store.tracks`) registers a dependency on
//     that property. A mutation that doesn't touch `tracks` won't fire it.
//   - A read of a COMPUTED property that internally reads a private stored field
//     registers a dependency on that private field.
//   - A read of `store.clipPoolByID[key]` registers a dependency on the WHOLE
//     `clipPoolByID` dict, NOT on the individual key. This means ANY clip mutation
//     will invalidate an observer that reads ANY clip via dict lookup.
//
// The `clipPool` and `generatorPool` computed properties on LiveSequencerStore
// iterate `storeClipOrder` + `storeClipsByID`, so reading `clipPool` (or any
// derived accessor that calls it, like `clipEntry(id:)`) registers dependencies
// on BOTH `storeClipOrder` and `storeClipsByID`. Because `storeClipsByID` is a
// dict, mutating ANY entry invalidates ALL observers reading ANY part of that dict.
//
// Tests that expose this ceiling are marked `XCTExpectFailure` with a comment
// referencing the limitation. These tests establish the known observation ceiling
// so it can be narrowed if a per-key wrapper is introduced in the future.

@MainActor
final class ObservationGranularityTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() -> LiveSequencerStore {
        let (project, _, _) = makeLiveStoreProject()
        return LiveSequencerStore(project: project)
    }

    /// Build a store with two clips in the clip pool. Returns the store
    /// plus the IDs of the two clips.
    private func makeStoreWithTwoClips() -> (store: LiveSequencerStore, clipA: UUID, clipB: UUID) {
        let (project, trackID, clipAID) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        // Append a second clip.
        let clipB = ClipPoolEntry(
            id: UUID(),
            name: "Clip B",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 8,
                steps: Array(repeating: ClipStep.empty, count: 8)
            )
        )
        _ = trackID
        store.appendClip(clipB)
        return (store, clipAID, clipB.id)
    }

    /// Build a store with two tracks. Returns the store plus the track IDs.
    private func makeStoreWithTwoTracks() -> (store: LiveSequencerStore, trackA: UUID, trackB: UUID) {
        let (project, trackAID, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)

        // Add a second track by building a project round-trip.
        var p = store.exportToProject()
        p.appendTrack(trackType: .polyMelodic)
        store.importFromProject(p)

        // trackB is the last track appended.
        let trackBID = store.tracks.last!.id
        return (store, trackAID, trackBID)
    }

    /// Build a store with two phrases. Returns the store plus the phrase IDs.
    private func makeStoreWithTwoPhrases() -> (store: LiveSequencerStore, phraseA: UUID, phraseB: UUID) {
        let (project, _, _) = makeLiveStoreProject()
        let store = LiveSequencerStore(project: project)
        let phraseAID = store.selectedPhraseID

        var p = store.exportToProject()
        p.insertPhrase(below: phraseAID)
        store.replacePhrases(p.phrases, selectedPhraseID: phraseAID)
        let phraseBID = store.phrases.first(where: { $0.id != phraseAID })!.id
        return (store, phraseAID, phraseBID)
    }

    // MARK: - Track-level narrowing (array property — @Observable tracks at property level)

    /// Mutating track A's mix level must not invalidate an observer reading `selectedTrackID`.
    ///
    /// `selectedTrackID` and `tracks` are separate stored properties on the store.
    /// A mutation to `tracks` (via `mutateTrack`) does NOT touch `selectedTrackID`.
    func test_trackMixMutation_doesNotInvalidate_selectedTrackIDObserver() {
        let (store, _, trackB) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.selectedTrackID
        } onChange: {
            didFire = true
        }

        // Mutate track B's mix — doesn't touch selectedTrackID.
        store.mutateTrack(id: trackB) { $0.mix.level = 0.5 }

        XCTAssertFalse(didFire,
            "Mutating a track's mix must not invalidate an observer reading selectedTrackID " +
            "(separate stored property)")
    }

    /// Mutating track A must not invalidate an observer reading track B
    /// when track B is accessed via a separate `tracks.first(where:)` call.
    ///
    /// @Observable tracks `\.tracks` (the array). Any mutation to the array
    /// (including updating one element in place via `storeTracks[index] = ...`)
    /// mutates the stored `storeTracks` property, invalidating ALL observers
    /// that read `\.tracks`. This is the ceiling for array-backed storage.
    func test_trackMutation_invalidates_viewReadingDifferentTrack() {
        let (store, trackA, _) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            // Observer for track B (the last track), read via `.tracks` property.
            _ = store.tracks.last?.name
        } onChange: {
            didFire = true
        }

        // Mutate track A — this writes to `storeTracks` (the whole array property).
        store.mutateTrack(id: trackA) { $0.mix.level = 0.8 }

        // Observation note: `storeTracks` is a single stored property (an array).
        // Writing ANY element of the array writes the whole property, so ALL
        // observers reading `.tracks` are invalidated regardless of which track
        // element changed. This is the known ceiling for array-backed track storage.
        // Per-track narrowing would require per-track @Observable wrappers.
        XCTExpectFailure(
            "Known limitation: @Observable tracks `storeTracks` as a whole array. " +
            "Mutating any element invalidates all `.tracks` observers. " +
            "Per-track narrowing would require individual @Observable track wrappers."
        ) {
            XCTAssertFalse(didFire,
                "Expected track A mutation to NOT invalidate track B observer, but it does " +
                "because @Observable registers array-level dependencies")
        }
    }

    /// Mutating track A's name must not invalidate an observer reading `patternBanksByTrackID`.
    ///
    /// `patternBanksByTrackID` and `tracks` are different stored properties.
    func test_trackNameMutation_doesNotInvalidate_patternBanksObserver() {
        let (store, trackA, _) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.patternBanksByTrackID
        } onChange: {
            didFire = true
        }

        // Mutate track A's name — writes `storeTracks`, not `storePatternBanksByTrackID`.
        store.mutateTrack(id: trackA) { $0.name = "Renamed Track A" }

        XCTAssertFalse(didFire,
            "Mutating a track's name (storeTracks) must not fire an observer reading " +
            "patternBanksByTrackID (a separate stored property)")
    }

    // MARK: - Clip-level observation (dict-keyed — known ceiling)

    /// Mutating clip A must not invalidate an observer bound specifically to clip B.
    ///
    /// Because `clipPool` and `clipEntry(id:)` read `storeClipsByID` (the whole dict),
    /// mutating ANY clip entry writes to the dict and fires ALL clip observers.
    /// This test documents that known ceiling.
    func test_clipMutation_doesNotInvalidate_viewReadingDifferentClip() {
        let (store, clipA, clipB) = makeStoreWithTwoClips()
        var didFire = false

        withObservationTracking {
            // Simulates a view reading clip B specifically.
            _ = store.clipPool.first(where: { $0.id == clipB })?.name
        } onChange: {
            didFire = true
        }

        // Mutate clip A's name.
        store.mutateClip(id: clipA) { $0.name = "Clip A renamed" }

        // Observation note: `clipPool` reads `storeClipOrder` + `storeClipsByID`.
        // Mutating `storeClipsByID[clipA]` writes the whole dict property, which
        // invalidates ALL observers that read `storeClipsByID`. This is the
        // known ceiling for dict-keyed clip pool storage under @Observable.
        // A per-key observation wrapper around ClipPoolEntry could narrow this.
        XCTExpectFailure(
            "Known limitation: @Observable tracks `storeClipsByID` as a whole dict. " +
            "Mutating clip A invalidates observers reading clip B via clipPool/clipEntry. " +
            "Per-key narrowing would require an @Observable wrapper per clip entry."
        ) {
            XCTAssertFalse(didFire,
                "Expected clip A mutation to NOT invalidate clip B observer, but it does " +
                "because @Observable registers dict-level (not key-level) dependencies")
        }
    }

    /// Mutating clip A must not invalidate an observer reading the tracks list.
    ///
    /// `tracks` (backed by `storeTracks`) and `clipPool` (backed by `storeClipsByID`)
    /// are separate stored properties. A clip mutation must not fire a `tracks` observer.
    func test_clipMutation_doesNotInvalidate_tracksListObserver() {
        let (store, clipA, _) = makeStoreWithTwoClips()
        var didFire = false

        withObservationTracking {
            _ = store.tracks.count
        } onChange: {
            didFire = true
        }

        store.mutateClip(id: clipA) { $0.name = "Different Name" }

        XCTAssertFalse(didFire,
            "Mutating a clip (storeClipsByID) must not fire an observer reading `tracks` " +
            "(storeTracks — a separate stored property)")
    }

    // MARK: - Phrase-level observation (dict-keyed — known ceiling)

    /// Mutating phrase A's cells must not invalidate an observer reading phrase B.
    ///
    /// Same dict-keyed ceiling as clips: `storePhrasesByID` is the whole dict.
    func test_phraseMutation_doesNotInvalidate_viewReadingDifferentPhrase() {
        let (store, phraseA, phraseB) = makeStoreWithTwoPhrases()
        var didFire = false

        withObservationTracking {
            // Simulates a view reading phrase B's name.
            _ = store.phrases.first(where: { $0.id == phraseB })?.name
        } onChange: {
            didFire = true
        }

        // Mutate phrase A.
        store.mutatePhrase(id: phraseA) { phrase in
            phrase.lengthBars = 4
        }

        // Observation note: `phrases` reads `storePhraseOrder` + `storePhrasesByID`.
        // Same ceiling as clips — dict-level invalidation. Any phrase mutation
        // fires all phrase observers.
        XCTExpectFailure(
            "Known limitation: @Observable tracks `storePhrasesByID` as a whole dict. " +
            "Mutating phrase A invalidates observers reading phrase B via `.phrases`. " +
            "Per-key narrowing would require an @Observable wrapper per phrase."
        ) {
            XCTAssertFalse(didFire,
                "Expected phrase A mutation to NOT invalidate phrase B observer, but it does")
        }
    }

    /// Mutating phrase A must not invalidate an observer reading `selectedPhraseID`.
    ///
    /// `selectedPhraseID` (backed by `storeSelectedPhraseID`) is a separate stored
    /// property. Mutating `storePhrasesByID` must not fire it.
    func test_phraseMutation_doesNotInvalidate_selectedPhraseIDObserver() {
        let (store, phraseA, _) = makeStoreWithTwoPhrases()
        var didFire = false

        withObservationTracking {
            _ = store.selectedPhraseID
        } onChange: {
            didFire = true
        }

        store.mutatePhrase(id: phraseA) { phrase in
            phrase.name = "Phrase A renamed"
        }

        XCTAssertFalse(didFire,
            "Mutating a phrase (storePhrasesByID) must not fire an observer reading " +
            "selectedPhraseID (storeSelectedPhraseID — a separate stored property)")
    }

    // MARK: - Pattern bank observation

    /// Mutating the pattern bank for track A must not invalidate an observer
    /// reading `tracks`.
    ///
    /// `storePatternBanksByTrackID` and `storeTracks` are separate stored properties.
    func test_patternBankMutation_doesNotInvalidate_viewReadingTracksList() {
        let (store, trackA, _) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.tracks.map(\.name)
        } onChange: {
            didFire = true
        }

        // Mutate the pattern bank for track A.
        store.mutatePatternBank(trackID: trackA) { bank in
            let slot = bank.slot(at: 1)
            let updated = TrackPatternSlot(
                slotIndex: 1,
                name: "Slot 1",
                sourceRef: slot.sourceRef
            )
            bank.setSlot(updated, at: 1)
        }

        XCTAssertFalse(didFire,
            "Mutating a pattern bank (storePatternBanksByTrackID) must not invalidate " +
            "an observer reading `tracks` (storeTracks)")
    }

    /// Mutating the pattern bank for track A must not invalidate an observer
    /// reading the pattern bank for track B.
    ///
    /// Both are inside `storePatternBanksByTrackID` — the same dict. This hits
    /// the dict-keyed ceiling again.
    func test_patternBankMutation_doesNotInvalidate_viewReadingDifferentTrackPatternBank() {
        let (store, trackA, trackB) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.patternBanksByTrackID[trackB]?.slots.count
        } onChange: {
            didFire = true
        }

        store.mutatePatternBank(trackID: trackA) { bank in
            let slot = bank.slot(at: 0)
            bank.setSlot(TrackPatternSlot(slotIndex: 0, name: "Renamed", sourceRef: slot.sourceRef), at: 0)
        }

        // Observation note: `patternBanksByTrackID` exposes `storePatternBanksByTrackID`
        // directly. Reading `dict[trackB]` registers a dependency on the whole dict
        // property. Mutating `dict[trackA]` writes the whole dict, invalidating all
        // observers reading any key via dict subscript.
        XCTExpectFailure(
            "Known limitation: reading patternBanksByTrackID[trackB] registers a dependency " +
            "on the whole storePatternBanksByTrackID dict. Mutating any entry invalidates all " +
            "pattern-bank observers. Per-key narrowing requires per-track @Observable wrappers."
        ) {
            XCTAssertFalse(didFire,
                "Expected pattern bank mutation for track A to NOT invalidate pattern bank " +
                "observer for track B, but it does due to dict-level tracking")
        }
    }

    // MARK: - Selection change observation

    /// Changing `selectedTrackID` must not invalidate an observer reading `routes`.
    ///
    /// `storeSelectedTrackID` and `storeRoutes` are separate stored properties.
    func test_selectionChange_doesNotInvalidate_routesObserver() {
        let (store, _, trackB) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.routes.count
        } onChange: {
            didFire = true
        }

        store.setSelectedTrackID(trackB)

        XCTAssertFalse(didFire,
            "Setting selectedTrackID must not fire an observer reading `routes` " +
            "(separate stored property)")
    }

    /// Changing `selectedTrackID` must not invalidate an observer reading `layers`.
    ///
    /// `storeSelectedTrackID` and `storeLayers` are separate stored properties.
    func test_selectionChange_doesNotInvalidate_layersObserver() {
        let (store, _, trackB) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.layers.count
        } onChange: {
            didFire = true
        }

        store.setSelectedTrackID(trackB)

        XCTAssertFalse(didFire,
            "Setting selectedTrackID must not fire an observer reading `layers`")
    }

    // MARK: - Route / generator mutation isolation

    /// Mutating routes must not invalidate an observer reading `tracks`.
    func test_routeMutation_doesNotInvalidate_tracksListObserver() {
        let (store, trackA, _) = makeStoreWithTwoTracks()
        var didFire = false

        withObservationTracking {
            _ = store.tracks.count
        } onChange: {
            didFire = true
        }

        let route = store.makeDefaultRoute(from: trackA)
        store.upsertRoute(route)

        XCTAssertFalse(didFire,
            "Upserting a route (storeRoutes) must not fire an observer reading `tracks`")
    }

    /// Mutating a generator must not invalidate an observer reading `tracks`.
    ///
    /// `storeGeneratorsByID` and `storeTracks` are separate stored properties.
    func test_generatorMutation_doesNotInvalidate_tracksObserver() throws {
        let store = makeStore()
        var didFire = false
        let generatorIDs = store.generatorPool.map(\.id)
        guard let firstGeneratorID = generatorIDs.first else {
            throw XCTSkip("No generators in default fixture; cannot test generator mutation isolation")
        }

        withObservationTracking {
            _ = store.tracks.count
        } onChange: {
            didFire = true
        }

        store.mutateGenerator(id: firstGeneratorID) { entry in
            entry.name = "Renamed Generator"
        }

        XCTAssertFalse(didFire,
            "Mutating a generator (storeGeneratorsByID) must not fire a `tracks` observer")
    }

    /// Mutating a generator must not invalidate an observer reading a different generator.
    ///
    /// Same dict-keyed ceiling: `storeGeneratorsByID` is the whole dict.
    func test_generatorMutation_doesNotInvalidate_viewReadingDifferentGenerator() throws {
        let store = makeStore()
        let generators = store.generatorPool
        guard generators.count >= 2 else {
            throw XCTSkip("Need at least 2 generators; default fixture has \(generators.count)")
        }
        let generatorA = generators[0].id
        let generatorB = generators[1].id
        var didFire = false

        withObservationTracking {
            _ = store.generatorPool.first(where: { $0.id == generatorB })?.name
        } onChange: {
            didFire = true
        }

        store.mutateGenerator(id: generatorA) { entry in
            entry.name = "Generator A renamed"
        }

        // Observation note: `generatorPool` reads `storeGeneratorOrder` + `storeGeneratorsByID`.
        // Same dict-level ceiling as clips and phrases.
        XCTExpectFailure(
            "Known limitation: @Observable tracks `storeGeneratorsByID` as a whole dict. " +
            "Mutating generator A invalidates observers reading generator B via `.generatorPool`. " +
            "Per-key narrowing requires individual @Observable wrappers per generator entry."
        ) {
            XCTAssertFalse(didFire,
                "Expected generator A mutation to NOT invalidate generator B observer, but it does")
        }
    }
}
