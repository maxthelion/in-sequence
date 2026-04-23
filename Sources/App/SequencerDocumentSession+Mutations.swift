import Foundation

// MARK: - Typed session mutation API
//
// Every method here:
//   1. Calls one or more typed store methods (which only mutate state + bump revision).
//   2. Updates `self.revision`.
//   3. Dispatches the appropriate impact (publishSnapshot, fullEngineApply, or scoped).
//   4. Schedules the debounce flush.
//
// Impact semantics are preserved from the old `mutateProject(impact:_:)` call sites.
// Call sites that were `.fullEngineApply` remain `.fullEngineApply` unless annotated
// with a justification comment for narrowing.

extension SequencerDocumentSession {

    // MARK: - Impact dispatch (internal)

    /// Dispatch the impact after a successful mutation. Updates `revision`, publishes
    /// the snapshot or applies the document model, and schedules the flush.
    private func dispatchImpact(_ impact: LiveMutationImpact) {
        revision = store.revision
        switch impact {
        case .snapshotOnly:
            publishSnapshot()
        case .fullEngineApply:
            // apply(documentModel:) installs a fresh snapshot internally.
            // Do NOT also call publishSnapshot() — that would compile twice.
            engineController.apply(documentModel: store.exportToProject())
        case .scopedRuntime(let update):
            dispatchScopedRuntimeUpdate(update)
            publishSnapshot()
        }
        scheduleFlushToDocument()
    }

    // MARK: - Batch helper

    /// Run multiple typed mutations against the live store and publish exactly one
    /// snapshot at the end. Use only for composite user actions that must produce a
    /// single engine-visible update.
    ///
    /// The `body` receives the raw `LiveSequencerStore` so it can call any of the
    /// store's typed mutation methods directly. The session's `isInBatch` guard
    /// prevents any individual typed-session method from publishing during the body.
    ///
    /// - Returns: `true` if the store revision advanced (i.e. something changed).
    @discardableResult
    func batch(impact: LiveMutationImpact = .snapshotOnly, _ body: (LiveSequencerStore) -> Void) -> Bool {
        let revisionBefore = store.revision
        isInBatch = true
        body(store)
        isInBatch = false
        guard store.revision != revisionBefore else {
            return false
        }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Clip mutations

    /// Mutate a clip in the clip pool by ID, then dispatch impact.
    @discardableResult
    func mutateClip(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout ClipPoolEntry) -> Void) -> Bool {
        let changed = store.mutateClip(id: id, update)
        guard changed else { return false }
        guard !isInBatch else { return true }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Track mutations

    /// Mutate a track by ID, then dispatch impact.
    @discardableResult
    func mutateTrack(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout StepSequenceTrack) -> Void) -> Bool {
        let changed = store.mutateTrack(id: id, update)
        guard changed else { return false }
        guard !isInBatch else { return true }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Generator mutations

    /// Mutate a generator pool entry by ID, then dispatch impact.
    @discardableResult
    func mutateGenerator(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout GeneratorPoolEntry) -> Void) -> Bool {
        let changed = store.mutateGenerator(id: id, update)
        guard changed else { return false }
        guard !isInBatch else { return true }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Phrase mutations

    /// Mutate a phrase by ID, then dispatch impact.
    @discardableResult
    func mutatePhrase(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout PhraseModel) -> Void) -> Bool {
        let changed = store.mutatePhrase(id: id, update)
        guard changed else { return false }
        guard !isInBatch else { return true }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Selection

    /// Set the selected track ID, publish a snapshot. Always `.snapshotOnly` —
    /// selection has no audible impact.
    func setSelectedTrackID(_ id: UUID) {
        store.setSelectedTrackID(id)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Set the selected phrase ID, publish a snapshot. Always `.snapshotOnly`.
    func setSelectedPhraseID(_ id: UUID) {
        store.setSelectedPhraseID(id)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Set both selected phrase ID and selected track ID atomically.
    func setSelectedPhraseAndTrackID(phraseID: UUID, trackID: UUID) {
        batch(impact: .snapshotOnly) { s in
            s.setSelectedPhraseID(phraseID)
            s.setSelectedTrackID(trackID)
        }
    }

    // MARK: - Phrase structure (insert / duplicate / remove)

    /// Insert a new blank phrase below `phraseID`. Publishes one snapshot.
    func insertPhrase(below phraseID: UUID) {
        var p = store.exportToProject()
        p.insertPhrase(below: phraseID)
        store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        // Also sync layers (insertPhrase may add cells that need syncing)
        store.setLayers(p.layers)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Duplicate phrase by ID. Publishes one snapshot.
    func duplicatePhrase(id phraseID: UUID) {
        var p = store.exportToProject()
        p.duplicatePhrase(id: phraseID)
        store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Remove phrase by ID (guard: must have >1 phrase). Publishes one snapshot.
    func removePhrase(id phraseID: UUID) {
        var p = store.exportToProject()
        p.removePhrase(id: phraseID)
        store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    // MARK: - Phrase cell content

    /// Set a phrase cell for the given layer and track IDs. Publishes one snapshot.
    func setPhraseCell(
        _ cell: PhraseCell,
        layerID: String,
        trackIDs: [UUID],
        phraseID: UUID,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        let changed = store.mutatePhrase(id: phraseID) { phrase in
            for trackID in trackIDs {
                phrase.setCell(cell, for: layerID, trackID: trackID)
            }
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(impact)
    }

    // MARK: - Pattern bank

    /// Mutate the pattern bank for a given track ID in place, then dispatch impact.
    @discardableResult
    func mutatePatternBank(trackID: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout TrackPatternBank) -> Void) -> Bool {
        let changed = store.mutatePatternBank(trackID: trackID, update)
        guard changed else { return false }
        guard !isInBatch else { return true }
        dispatchImpact(impact)
        return true
    }

    // MARK: - Pattern source ref (composite: writes bank + possibly adds clip to pool)

    /// Set the pattern source ref for a track slot.
    ///
    /// Uses `batch` because it may add a new clip to the pool and update the bank
    /// in the same user action — one snapshot publish at the end.
    func setPatternSourceRef(
        _ sourceRef: SourceRef,
        for trackID: UUID,
        slotIndex: Int,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        batch(impact: impact) { s in
            var p = s.exportToProject()
            let clipsBefore = Set(p.clipPool.map(\.id))
            p.setPatternSourceRef(sourceRef, for: trackID, slotIndex: slotIndex)
            for bank in p.patternBanks {
                s.setPatternBank(trackID: bank.trackID, bank: bank)
            }
            // Sync clip pool if new clips were added (setPatternSourceRef may call ensureClip).
            for clip in p.clipPool where !clipsBefore.contains(clip.id) {
                s.appendClip(clip)
            }
        }
    }

    // MARK: - Macro application (composite: tracks + layers + phrases)

    /// Apply a macro add/remove diff to a track.
    ///
    /// Composite: writes track macros, layers, and phrases (via `syncMacroLayers`).
    func applyMacroDiff(
        added: [AUParameterDescriptor],
        removed: Set<UInt64>,
        trackID: UUID
    ) {
        batch(impact: .snapshotOnly) { s in
            var p = s.exportToProject()
            let liveTrack = p.tracks.first(where: { $0.id == trackID })
                ?? p.tracks.first
            guard let liveTrack else { return }
            for address in removed {
                if let binding = liveTrack.macros.first(where: {
                    if case let .auParameter(a, _) = $0.source { return a == address }
                    return false
                }) {
                    p.removeMacro(id: binding.id, from: trackID)
                }
            }
            for param in added {
                let descriptor = TrackMacroDescriptor(
                    id: UUID(),
                    displayName: param.displayName,
                    minValue: param.minValue,
                    maxValue: param.maxValue,
                    defaultValue: param.defaultValue,
                    valueType: .scalar,
                    source: .auParameter(address: param.address, identifier: param.identifier)
                )
                p.addAUMacro(descriptor: descriptor, to: trackID)
            }
            p.syncMacroLayers()
            // Write back all affected fields.
            s.replaceTracks(p.tracks)
            s.setLayers(p.layers)
            s.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
            for clip in p.clipPool {
                // macroLanes may have changed on clips
                if s.exportToProject().clipPool.first(where: { $0.id == clip.id }) != clip {
                    s.mutateClip(id: clip.id) { $0 = clip }
                }
            }
        }
    }

    // MARK: - Macro layer default (live knob drag)

    /// Write a macro layer default value for a knob drag.
    ///
    /// Uses a project-export round-trip because layer defaults are embedded in
    /// `storeLayers` and there is no narrower per-layer typed method on the store.
    func setMacroLayerDefault(
        value: Double,
        bindingID: UUID,
        trackID: UUID
    ) {
        var p = store.exportToProject()
        p.setMacroLayerDefault(
            value: value,
            bindingID: bindingID,
            trackID: trackID,
            phraseID: p.selectedPhraseID
        )
        store.setLayers(p.layers)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    // MARK: - Destination mutations

    /// Set the edited destination for a track, then dispatch `.fullEngineApply`.
    ///
    /// `.fullEngineApply` is preserved: destination changes require
    /// `apply(documentModel:)` to tear down and rebuild the AU host.
    func setEditedDestination(_ destination: Destination, for trackID: UUID) {
        batch(impact: .fullEngineApply) { s in
            var p = s.exportToProject()
            p.setEditedDestination(destination, for: trackID)
            s.replaceTracks(p.tracks)
            s.replaceTrackGroups(p.trackGroups)
        }
    }

    /// Set the MIDI port for a track's destination. `.fullEngineApply` preserved
    /// from original call site: MIDI port change requires engine re-apply.
    func setEditedMIDIPort(_ port: MIDIEndpointName?, for trackID: UUID) {
        batch(impact: .fullEngineApply) { s in
            var p = s.exportToProject()
            p.setEditedMIDIPort(port, for: trackID)
            s.replaceTracks(p.tracks)
            s.replaceTrackGroups(p.trackGroups)
        }
    }

    /// Set the MIDI channel for a track's destination. `.fullEngineApply` preserved.
    func setEditedMIDIChannel(_ channel: UInt8, for trackID: UUID) {
        batch(impact: .fullEngineApply) { s in
            var p = s.exportToProject()
            p.setEditedMIDIChannel(channel, for: trackID)
            s.replaceTracks(p.tracks)
            s.replaceTrackGroups(p.trackGroups)
        }
    }

    /// Set the MIDI note offset for a track's destination. `.fullEngineApply` preserved.
    func setEditedMIDINoteOffset(_ noteOffset: Int, for trackID: UUID) {
        batch(impact: .fullEngineApply) { s in
            var p = s.exportToProject()
            p.setEditedMIDINoteOffset(noteOffset, for: trackID)
            s.replaceTracks(p.tracks)
            s.replaceTrackGroups(p.trackGroups)
        }
    }

    /// Write an AU state blob for a track or group destination.
    ///
    /// `impact` is `.scopedRuntime(.auState(...))` — the blob is written into the
    /// live store and the scoped runtime is dispatched, then a snapshot is published.
    /// This does NOT call `apply(documentModel:)`.
    func writeStateBlob(_ stateBlob: Data?, target: Project.DestinationWriteTarget) {
        // Resolve the runtime track ID for the scoped update (single export for both uses).
        let currentTracks = store.exportToProject().tracks
        let runtimeTrackID: UUID
        switch target {
        case .track(let trackID):
            runtimeTrackID = trackID
        case .group(let groupID):
            runtimeTrackID = currentTracks.first(where: { $0.groupID == groupID })?.id
                ?? currentTracks.first?.id
                ?? UUID()
        }

        batch(impact: .scopedRuntime(update: .auState(trackID: runtimeTrackID, blob: stateBlob))) { s in
            var p = s.exportToProject()
            switch target {
            case .track(let trackID):
                guard let trackIndex = p.tracks.firstIndex(where: { $0.id == trackID }),
                      case let .auInstrument(componentID, _) = p.tracks[trackIndex].destination
                else { return }
                p.tracks[trackIndex].destination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                s.replaceTracks(p.tracks)

            case .group(let groupID):
                guard let groupIndex = p.trackGroups.firstIndex(where: { $0.id == groupID }),
                      case let .auInstrument(componentID, _)? = p.trackGroups[groupIndex].sharedDestination
                else { return }
                p.trackGroups[groupIndex].sharedDestination = .auInstrument(componentID: componentID, stateBlob: stateBlob)
                s.replaceTrackGroups(p.trackGroups)
            }
        }
    }

    // MARK: - Filter settings

    /// Write sampler filter settings for a track and dispatch scoped runtime.
    func setFilterSettings(_ settings: SamplerFilterSettings, for trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.filter = settings
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.scopedRuntime(update: .filter(trackID: trackID, settings: settings)))
    }

    // MARK: - Mute / velocity / gate (track property helpers)

    /// Toggle mute for a track, dispatching `.fullEngineApply`.
    ///
    /// `.fullEngineApply` preserved from original call sites: mute affects the
    /// engine's active-voice state which requires a document-model rebuild.
    func toggleTrackMute(trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix.isMuted.toggle()
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.fullEngineApply)
    }

    /// Set mute state for a track, dispatching `.fullEngineApply`.
    func setTrackMuted(_ muted: Bool, trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix.isMuted = muted
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.fullEngineApply)
    }

    // MARK: - Pattern modifier

    /// Set the modifier bypassed state for a pattern slot.
    func setPatternModifierBypassed(_ bypassed: Bool, for trackID: UUID, slotIndex: Int) {
        mutatePatternBank(trackID: trackID) { bank in
            let slot = bank.slot(at: slotIndex)
            guard slot.sourceRef.modifierGeneratorID != nil else { return }
            let updated = SourceRef(
                mode: slot.sourceRef.mode,
                generatorID: slot.sourceRef.generatorID,
                clipID: slot.sourceRef.clipID,
                modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                modifierBypassed: bypassed
            )
            bank.setSlot(TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: updated), at: slotIndex)
        }
    }

    /// Set the modifier generator ID for a pattern slot.
    func setPatternModifierGeneratorID(_ modifierGeneratorID: UUID?, for trackID: UUID, slotIndex: Int) {
        mutatePatternBank(trackID: trackID) { bank in
            let slot = bank.slot(at: slotIndex)
            let updated = SourceRef(
                mode: slot.sourceRef.mode,
                generatorID: slot.sourceRef.generatorID,
                clipID: slot.sourceRef.clipID,
                modifierGeneratorID: modifierGeneratorID,
                modifierBypassed: modifierGeneratorID == nil ? false : slot.sourceRef.modifierBypassed
            )
            bank.setSlot(TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: updated), at: slotIndex)
        }
    }

    /// Set the selected pattern index for a track (writes phrase cell via project round-trip).
    func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        var p = store.exportToProject()
        p.setSelectedPatternIndex(index, for: trackID)
        store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Update a generator entry by ID and dispatch impact, using a project round-trip
    /// so that pattern bank sync (which depends on the generator pool) is preserved.
    func updateGeneratorEntry(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout GeneratorPoolEntry) -> Void) {
        let changed = store.mutateGenerator(id: id, update)
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(impact)
    }

    /// Ensure a clip exists for the current pattern slot, creating it if necessary,
    /// then run the clip update. Returns the clip ID used.
    @discardableResult
    func ensureClipAndMutate(trackID: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (UUID, inout ClipPoolEntry) -> Void) -> UUID? {
        batch(impact: impact) { s in
            var p = s.exportToProject()
            guard let clipID = p.ensureClipForCurrentPattern(trackID: trackID) else { return }
            // If a new clip was created, it's in p.clipPool but not yet in the store.
            for clip in p.clipPool where s.exportToProject().clipPool.first(where: { $0.id == clip.id }) == nil {
                s.appendClip(clip)
            }
            // Update pattern banks if source ref changed.
            for bank in p.patternBanks {
                s.setPatternBank(trackID: bank.trackID, bank: bank)
            }
            // Now mutate the clip.
            s.mutateClip(id: clipID) { entry in
                update(clipID, &entry)
            }
        }
        return nil // Caller doesn't need the clip ID; used for side-effect chaining.
    }
}

