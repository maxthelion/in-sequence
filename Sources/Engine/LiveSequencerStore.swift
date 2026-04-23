import Foundation
import Observation

/// Scoped runtime update payloads for `LiveMutationImpact.scopedRuntime`.
///
/// Each case carries exactly the data the session needs to dispatch to the
/// engine without rebuilding the full document model.
enum ScopedRuntimeUpdate: Sendable {
    /// Update sampler filter settings for a single track.
    case filter(trackID: UUID, settings: SamplerFilterSettings)
    /// Write an AU state blob for a single track (or group-inherited destination).
    case auState(trackID: UUID, blob: Data?)
    /// Update mix settings for a single track (general-consumer path).
    case mix(trackID: UUID, mix: TrackMixSettings)
}

enum LiveMutationImpact: Sendable {
    case snapshotOnly
    case fullEngineApply
    /// Dispatch a scoped runtime update directly to the engine, publish a snapshot,
    /// and schedule the normal debounce flush. Does NOT call apply(documentModel:).
    case scopedRuntime(update: ScopedRuntimeUpdate)
}

// MARK: - LiveSequencerStoreState

/// Lightweight aggregate of the store's resident fields, produced cheaply for
/// snapshot compilation. All arrays and dictionaries are Swift value types and
/// share copy-on-write storage with the store's resident fields until mutated.
struct LiveSequencerStoreState {
    let tracks: [StepSequenceTrack]
    let generatorPool: [GeneratorPoolEntry]
    let clipPool: [ClipPoolEntry]
    let layers: [PhraseLayerDefinition]
    let patternBanksByTrackID: [UUID: TrackPatternBank]
    let phrasesByID: [UUID: PhraseModel]
    let phraseOrder: [UUID]
    let selectedPhraseID: UUID

    /// A minimal empty state suitable for initialising `currentPlaybackSnapshot`
    /// before any document is applied.
    static let empty = LiveSequencerStoreState(
        tracks: [],
        generatorPool: [],
        clipPool: [],
        layers: [],
        patternBanksByTrackID: [:],
        phrasesByID: [:],
        phraseOrder: [],
        selectedPhraseID: UUID()
    )
}

// MARK: - LiveSequencerStore

/// Owns the live authored state of the open document.
///
/// Internal state is a set of per-domain resident fields — not a single
/// `Project` value. Mutations operate directly on the affected domain slice
/// without rewriting the full `Project` value.
///
/// Use `importFromProject(_:)` on init and on external document changes.
/// Use `exportToProject()` for flush paths and snapshot compilation.
@MainActor
@Observable
final class LiveSequencerStore {

    // MARK: - Revision

    /// Monotonically increasing counter. Bumped by every state-changing mutation.
    private(set) var revision: UInt64 = 0

    // MARK: - Resident state

    /// Document format version — carried through import/export without interpretation.
    private var storeVersion: Int = 1

    /// Ordered track list. Order is authoritative.
    private var storeTracks: [StepSequenceTrack] = []

    /// Track groups, ordered as stored.
    private var storeTrackGroups: [TrackGroup] = []

    /// Generator pool indexed by ID. `storeGeneratorOrder` preserves insertion order.
    private var storeGeneratorsByID: [UUID: GeneratorPoolEntry] = [:]
    private var storeGeneratorOrder: [UUID] = []

    /// Clip pool indexed by ID. `storeClipOrder` preserves insertion order.
    private var storeClipsByID: [UUID: ClipPoolEntry] = [:]
    private var storeClipOrder: [UUID] = []

    /// Phrase layer definitions, ordered as stored.
    private var storeLayers: [PhraseLayerDefinition] = []

    /// Routes, ordered as stored.
    private var storeRoutes: [Route] = []

    /// Pattern banks keyed by track ID.
    private var storePatternBanksByTrackID: [UUID: TrackPatternBank] = [:]

    /// Selection state.
    private var storeSelectedTrackID: UUID = UUID()
    private var storeSelectedPhraseID: UUID = UUID()

    /// Phrases indexed by ID. `storePhraseOrder` preserves insertion order.
    private var storePhrasesByID: [UUID: PhraseModel] = [:]
    private var storePhraseOrder: [UUID] = []

    // MARK: - Init

    init(project: Project) {
        importFromProject(project)
    }

    // MARK: - Import / Export

    /// Atomically replace all resident fields from a `Project` value.
    ///
    /// Used on init and when an external document change arrives.
    func importFromProject(_ project: Project) {
        storeVersion = project.version
        storeTracks = project.tracks
        storeTrackGroups = project.trackGroups
        storeLayers = project.layers
        storeRoutes = project.routes
        storeSelectedTrackID = project.selectedTrackID
        storeSelectedPhraseID = project.selectedPhraseID

        storeGeneratorOrder = project.generatorPool.map(\.id)
        storeGeneratorsByID = Dictionary(uniqueKeysWithValues: project.generatorPool.map { ($0.id, $0) })

        storeClipOrder = project.clipPool.map(\.id)
        storeClipsByID = Dictionary(uniqueKeysWithValues: project.clipPool.map { ($0.id, $0) })

        storePhraseOrder = project.phrases.map(\.id)
        storePhrasesByID = Dictionary(uniqueKeysWithValues: project.phrases.map { ($0.id, $0) })

        storePatternBanksByTrackID = Dictionary(
            uniqueKeysWithValues: project.patternBanks.map { ($0.trackID, $0) }
        )

        revision &+= 1
    }

    /// Test observer — fired at the start of every `exportToProject()` call.
    /// Nil in production; set by test code to count or assert on invocations.
    var exportToProjectObserver: (() -> Void)?

    /// Monotonically increasing counter of `exportToProject()` invocations.
    ///
    /// Read this in tests via `assertNoExportDuring(_:_:)` to verify that a
    /// code path does not perform a full project export. Production code should
    /// never read this counter.
    private(set) var exportToProjectCallCount: Int = 0

    /// Reconstruct a `Project` value from resident fields.
    ///
    /// Called by session flush paths only. `publishSnapshot()` uses `compileInput()`
    /// instead (Phase 1b invariant).
    func exportToProject() -> Project {
        exportToProjectObserver?()
        exportToProjectCallCount += 1
        let orderedGenerators = storeGeneratorOrder.compactMap { storeGeneratorsByID[$0] }
        let orderedClips = storeClipOrder.compactMap { storeClipsByID[$0] }
        let orderedPhrases = storePhraseOrder.compactMap { storePhrasesByID[$0] }
        let orderedBanks = storeTracks.compactMap { storePatternBanksByTrackID[$0.id] }

        return Project(
            version: storeVersion,
            tracks: storeTracks,
            trackGroups: storeTrackGroups,
            generatorPool: orderedGenerators,
            clipPool: orderedClips,
            layers: storeLayers,
            routes: storeRoutes,
            patternBanks: orderedBanks,
            selectedTrackID: storeSelectedTrackID,
            phrases: orderedPhrases,
            selectedPhraseID: storeSelectedPhraseID
        )
    }

    // MARK: - replaceProject (external-change path)

    /// Replace resident state from a new `Project` value.
    ///
    /// Returns `false` if nothing changed (by Project equality).
    @discardableResult
    func replaceProject(_ nextProject: Project) -> Bool {
        let before = exportToProject()
        guard nextProject != before else {
            return false
        }
        importFromProject(nextProject)
        return true
    }

    // MARK: - Backward-compatible accessors

    /// The current project value. Deprecated in favour of `exportToProject()`.
    var project: Project {
        exportToProject()
    }

    /// Alias kept for test backwards compatibility.
    func projectedProject() -> Project {
        exportToProject()
    }

    // MARK: - Typed mutation API

    /// Mutate a clip in the clip pool by ID.
    ///
    /// - Returns: `true` if the clip existed and the closure produced a change.
    @discardableResult
    func mutateClip(id: UUID, _ update: (inout ClipPoolEntry) -> Void) -> Bool {
        guard var entry = storeClipsByID[id] else {
            return false
        }
        let before = entry
        update(&entry)
        guard entry != before else {
            return false
        }
        storeClipsByID[id] = entry
        revision &+= 1
        return true
    }

    /// Mutate a track in the ordered track list by ID.
    ///
    /// - Returns: `true` if the track existed and the closure produced a change.
    @discardableResult
    func mutateTrack(id: UUID, _ update: (inout StepSequenceTrack) -> Void) -> Bool {
        guard let index = storeTracks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let before = storeTracks[index]
        update(&storeTracks[index])
        guard storeTracks[index] != before else {
            return false
        }
        revision &+= 1
        return true
    }

    /// Mutate a generator pool entry by ID.
    ///
    /// - Returns: `true` if the generator existed and the closure produced a change.
    @discardableResult
    func mutateGenerator(id: UUID, _ update: (inout GeneratorPoolEntry) -> Void) -> Bool {
        guard var entry = storeGeneratorsByID[id] else {
            return false
        }
        let before = entry
        update(&entry)
        guard entry != before else {
            return false
        }
        storeGeneratorsByID[id] = entry
        revision &+= 1
        return true
    }

    /// Mutate a phrase by ID.
    ///
    /// - Returns: `true` if the phrase existed and the closure produced a change.
    @discardableResult
    func mutatePhrase(id: UUID, _ update: (inout PhraseModel) -> Void) -> Bool {
        guard var phrase = storePhrasesByID[id] else {
            return false
        }
        let before = phrase
        update(&phrase)
        guard phrase != before else {
            return false
        }
        storePhrasesByID[id] = phrase
        revision &+= 1
        return true
    }

    /// Replace the pattern bank for a given track ID. Bumps revision only if the value changed.
    func setPatternBank(trackID: UUID, bank: TrackPatternBank) {
        let before = storePatternBanksByTrackID[trackID]
        guard bank != before else {
            return
        }
        storePatternBanksByTrackID[trackID] = bank
        revision &+= 1
    }

    /// Mutate the pattern bank for a given track ID in place.
    ///
    /// - Returns: `true` if the bank existed and the closure produced a change.
    @discardableResult
    func mutatePatternBank(trackID: UUID, _ update: (inout TrackPatternBank) -> Void) -> Bool {
        guard var bank = storePatternBanksByTrackID[trackID] else {
            return false
        }
        let before = bank
        update(&bank)
        guard bank != before else {
            return false
        }
        storePatternBanksByTrackID[trackID] = bank
        revision &+= 1
        return true
    }

    /// Set the selected track ID. Bumps revision only if the value actually changes.
    func setSelectedTrackID(_ id: UUID?) {
        let resolved = id ?? storeTracks.first?.id ?? storeSelectedTrackID
        guard resolved != storeSelectedTrackID else {
            return
        }
        storeSelectedTrackID = resolved
        revision &+= 1
    }

    /// Set the selected phrase ID. Bumps revision only if the value actually changes.
    func setSelectedPhraseID(_ id: UUID) {
        guard id != storeSelectedPhraseID else {
            return
        }
        storeSelectedPhraseID = id
        revision &+= 1
    }

    /// Replace the layers array. Bumps revision only if the value changed.
    func setLayers(_ layers: [PhraseLayerDefinition]) {
        guard layers != storeLayers else {
            return
        }
        storeLayers = layers
        revision &+= 1
    }

    /// Append a clip to the pool. Always bumps revision.
    func appendClip(_ clip: ClipPoolEntry) {
        guard storeClipsByID[clip.id] == nil else {
            return
        }
        storeClipsByID[clip.id] = clip
        storeClipOrder.append(clip.id)
        revision &+= 1
    }

    /// Append a generator to the pool. Always bumps revision.
    func appendGenerator(_ generator: GeneratorPoolEntry) {
        guard storeGeneratorsByID[generator.id] == nil else {
            return
        }
        storeGeneratorsByID[generator.id] = generator
        storeGeneratorOrder.append(generator.id)
        revision &+= 1
    }

    /// Replace all phrases and phrase order atomically (for insert/duplicate/remove).
    ///
    /// Bumps revision if anything changed.
    func replacePhrases(_ phrases: [PhraseModel], selectedPhraseID: UUID) {
        let newByID = Dictionary(uniqueKeysWithValues: phrases.map { ($0.id, $0) })
        let newOrder = phrases.map(\.id)
        guard newByID != storePhrasesByID
            || newOrder != storePhraseOrder
            || selectedPhraseID != storeSelectedPhraseID
        else {
            return
        }
        storePhrasesByID = newByID
        storePhraseOrder = newOrder
        storeSelectedPhraseID = selectedPhraseID
        revision &+= 1
    }

    /// Replace all tracks atomically (for track-list structural changes).
    ///
    /// Bumps revision if anything changed.
    func replaceTracks(_ tracks: [StepSequenceTrack]) {
        guard tracks != storeTracks else {
            return
        }
        storeTracks = tracks
        revision &+= 1
    }

    /// Replace all track groups atomically.
    ///
    /// Bumps revision if anything changed.
    func replaceTrackGroups(_ groups: [TrackGroup]) {
        guard groups != storeTrackGroups else {
            return
        }
        storeTrackGroups = groups
        revision &+= 1
    }

    // MARK: - Route typed mutations

    /// Upsert a route rule (insert if new, replace if matching ID exists).
    ///
    /// - Returns: `true` if the routes array changed.
    @discardableResult
    func upsertRoute(_ route: Route) -> Bool {
        if let index = storeRoutes.firstIndex(where: { $0.id == route.id }) {
            guard storeRoutes[index] != route else { return false }
            storeRoutes[index] = route
        } else {
            storeRoutes.append(route)
        }
        revision &+= 1
        return true
    }

    /// Remove a route rule by ID.
    ///
    /// - Returns: `true` if a matching route was found and removed.
    @discardableResult
    func removeRoute(id: UUID) -> Bool {
        let countBefore = storeRoutes.count
        storeRoutes.removeAll { $0.id == id }
        guard storeRoutes.count != countBefore else { return false }
        revision &+= 1
        return true
    }

    // MARK: - Snapshot compile input

    // MARK: - Internal read accessors (used by LiveSequencerStore+Accessors)
    //
    // The resident fields are private to prevent external mutation. These
    // internal computed properties expose the values needed by the accessor
    // extension without widening write access.

    var tracks: [StepSequenceTrack] { storeTracks }
    var trackGroups: [TrackGroup] { storeTrackGroups }
    var layers: [PhraseLayerDefinition] { storeLayers }
    var routes: [Route] { storeRoutes }
    var selectedTrackID: UUID { storeSelectedTrackID }
    var selectedPhraseID: UUID { storeSelectedPhraseID }
    var patternBanksByTrackID: [UUID: TrackPatternBank] { storePatternBanksByTrackID }

    var generatorPool: [GeneratorPoolEntry] {
        storeGeneratorOrder.compactMap { storeGeneratorsByID[$0] }
    }

    var clipPool: [ClipPoolEntry] {
        storeClipOrder.compactMap { storeClipsByID[$0] }
    }

    var phrases: [PhraseModel] {
        storePhraseOrder.compactMap { storePhrasesByID[$0] }
    }

    // MARK: - Snapshot compile input

    /// Produce a `LiveSequencerStoreState` for snapshot compilation.
    ///
    /// All fields are Swift value types whose storage is shared (copy-on-write)
    /// with the store's resident dictionaries and arrays — no allocation overhead
    /// unless the caller mutates them.
    func compileInput() -> LiveSequencerStoreState {
        let orderedGenerators = storeGeneratorOrder.compactMap { storeGeneratorsByID[$0] }
        let orderedClips = storeClipOrder.compactMap { storeClipsByID[$0] }
        let orderedPhrases = storePhraseOrder.compactMap { storePhrasesByID[$0] }
        return LiveSequencerStoreState(
            tracks: storeTracks,
            generatorPool: orderedGenerators,
            clipPool: orderedClips,
            layers: storeLayers,
            patternBanksByTrackID: storePatternBanksByTrackID,
            phrasesByID: Dictionary(uniqueKeysWithValues: orderedPhrases.map { ($0.id, $0) }),
            phraseOrder: storePhraseOrder,
            selectedPhraseID: storeSelectedPhraseID
        )
    }
}
