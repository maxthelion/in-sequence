import Foundation

// MARK: - LiveSequencerStore read helpers
//
// These are ports of the `Project` convenience methods that UI currently uses.
// Each helper reads the store's resident fields rather than building a `Project`.
//
// Naming and return types intentionally match `Project`'s equivalents so that
// Phase-2 call-site migration is a mechanical substitution.
//
// Mutating helpers (`appendTrack`, `removeRoute`, etc.) are NOT here —
// those come in Phase 2 as each UI call site is migrated.

extension LiveSequencerStore {

    // MARK: - Selection

    /// The currently selected track.
    ///
    /// Matches `Project.selectedTrack`: returns the track whose `id ==
    /// selectedTrackID`, falling back to `StepSequenceTrack.default` when
    /// the track list is empty.
    var selectedTrack: StepSequenceTrack {
        guard !tracks.isEmpty else {
            return .default
        }
        let index = tracks.firstIndex(where: { $0.id == selectedTrackID }) ?? 0
        return tracks[index]
    }

    /// The currently selected phrase.
    ///
    /// Matches `Project.selectedPhrase`: returns the phrase whose `id ==
    /// selectedPhraseID`, falling back to `PhraseModel.default(...)` when
    /// the phrase list is empty.
    var selectedPhrase: PhraseModel {
        let orderedPhrases = phrases
        guard !orderedPhrases.isEmpty else {
            return PhraseModel.default(
                tracks: tracks,
                layers: layers,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
        }
        let index = orderedPhrases.firstIndex(where: { $0.id == selectedPhraseID }) ?? 0
        return orderedPhrases[index]
    }

    // MARK: - Patterns

    /// The phrase layer definition whose target is `.patternIndex`, if any.
    ///
    /// Matches `Project.patternLayer`.
    var patternLayer: PhraseLayerDefinition? {
        layers.first(where: { $0.target == .patternIndex })
    }

    /// Returns the pattern bank for the given track ID, or a synthesised
    /// default if no bank is stored for that track.
    ///
    /// Matches `Project.patternBank(for:)`.
    func patternBank(for trackID: UUID) -> TrackPatternBank {
        if let existing = patternBanksByTrackID[trackID] {
            return existing
        }
        let track = tracks.first(where: { $0.id == trackID }) ?? .default
        let fallbackClipID = clipPool.first(where: { $0.trackType == track.trackType })?.id
        return TrackPatternBank.default(for: track, initialClipID: fallbackClipID)
    }

    /// The selected pattern index for the given track in the currently
    /// selected phrase.
    ///
    /// Matches `Project.selectedPatternIndex(for:)`.
    func selectedPatternIndex(for trackID: UUID) -> Int {
        selectedPhrase.patternIndex(for: trackID, layers: layers)
    }

    /// The selected pattern slot for the given track in the currently
    /// selected phrase.
    ///
    /// Matches `Project.selectedPattern(for:)`.
    func selectedPattern(for trackID: UUID) -> TrackPatternSlot {
        patternBank(for: trackID).slot(at: selectedPatternIndex(for: trackID))
    }

    /// Returns the layer whose `id` matches the given string, if any.
    ///
    /// Matches `Project.layer(id:)`. Note: `PhraseLayerDefinition.id` is a
    /// `String`, not a `UUID` — the brief's `UUID` parameter type is a mistake
    /// in the plan; this matches the actual `Project` signature.
    func layer(id: String) -> PhraseLayerDefinition? {
        layers.first(where: { $0.id == id })
    }

    // MARK: - Clip / generator pool look-ups

    /// Returns the clip pool entry with the given ID, or `nil`.
    ///
    /// Matches `Project.clipEntry(id:)`.
    func clipEntry(id: UUID?) -> ClipPoolEntry? {
        guard let id else { return nil }
        return clipPool.first(where: { $0.id == id })
    }

    /// Returns the generator pool entry with the given ID, or `nil`.
    ///
    /// Matches `Project.generatorEntry(id:)`.
    func generatorEntry(id: UUID?) -> GeneratorPoolEntry? {
        guard let id else { return nil }
        return generatorPool.first(where: { $0.id == id })
    }

    /// Generators whose `trackType` matches the given track's `trackType`.
    ///
    /// Matches `Project.compatibleGenerators(for:)`.
    func compatibleGenerators(for track: StepSequenceTrack) -> [GeneratorPoolEntry] {
        generatorPool.filter { $0.trackType == track.trackType }
    }

    /// All clips in the clip pool (source inputs for generated sources).
    ///
    /// Matches `Project.generatedSourceInputClips()`. Returns the full clip
    /// pool — same semantics as the `Project` implementation.
    func generatedSourceInputClips() -> [ClipPoolEntry] {
        clipPool
    }

    /// Clips that carry pitch material (usable as harmonic sidechains).
    ///
    /// Matches `Project.harmonicSidechainClips()`.
    func harmonicSidechainClips() -> [ClipPoolEntry] {
        clipPool.filter(\.hasPitchMaterial)
    }

    // MARK: - Track groups

    /// Returns the group the given track belongs to, or `nil`.
    ///
    /// Matches `Project.group(for:)`.
    func group(for trackID: UUID) -> TrackGroup? {
        guard let groupID = tracks.first(where: { $0.id == trackID })?.groupID else {
            return nil
        }
        return trackGroups.first(where: { $0.id == groupID })
    }

    /// Returns all tracks that are members of the given group, in group
    /// member-ID order.
    ///
    /// Matches `Project.tracksInGroup(_:)`.
    func tracksInGroup(_ groupID: TrackGroupID) -> [StepSequenceTrack] {
        guard let group = trackGroups.first(where: { $0.id == groupID }) else {
            return []
        }
        return group.memberIDs.compactMap { memberID in
            tracks.first(where: { $0.id == memberID })
        }
    }

    // MARK: - Destinations

    /// Determines whether the effective destination for a track is owned by
    /// the track itself or by its group.
    ///
    /// Matches `Project.destinationWriteTarget(for:)`.
    func destinationWriteTarget(for trackID: UUID) -> Project.DestinationWriteTarget {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return .track(trackID)
        }
        if case .inheritGroup = track.destination,
           let groupID = track.groupID,
           trackGroups.contains(where: { $0.id == groupID })
        {
            return .group(groupID)
        }
        return .track(trackID)
    }

    /// The destination that governs the resolved audio/MIDI output for a
    /// track, resolving group inheritance.
    ///
    /// Matches `Project.resolvedDestination(for:)`.
    func resolvedDestination(for trackID: UUID) -> Destination {
        let target = destinationWriteTarget(for: trackID)
        let resolved: Destination?
        switch target {
        case .track(let tid):
            resolved = tracks.first(where: { $0.id == tid })?.destination
        case .group(let gid):
            resolved = trackGroups.first(where: { $0.id == gid })?.sharedDestination
        }
        return resolved
            ?? tracks.first(where: { $0.id == trackID })?.destination
            ?? .none
    }

    /// The destination used for voice-snapshot comparison (strips transient
    /// state before comparison).
    ///
    /// Matches `Project.voiceSnapshotDestination(for:)`.
    func voiceSnapshotDestination(for trackID: UUID) -> Destination? {
        let target = destinationWriteTarget(for: trackID)
        let destination: Destination?
        switch target {
        case .track(let tid):
            destination = tracks.first(where: { $0.id == tid })?.destination
        case .group(let gid):
            destination = trackGroups.first(where: { $0.id == gid })?.sharedDestination
        }
        return destination?.withoutTransientState
    }

    // MARK: - Routes

    /// All route rules whose source track ID matches the given track.
    ///
    /// Matches `Project.routesSourced(from:)`. Note: `Project` uses type
    /// `Route`; the brief incorrectly names the type `RouteRule`.
    func routesSourced(from trackID: UUID) -> [Route] {
        routes.filter { route in
            switch route.source {
            case let .track(sourceTrackID), let .chordGenerator(sourceTrackID):
                return sourceTrackID == trackID
            }
        }
    }
}
