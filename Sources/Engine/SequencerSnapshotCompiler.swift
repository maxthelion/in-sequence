import Foundation

enum SequencerSnapshotCompiler {

    // MARK: - Primary compile path (Phase 1b+)

    /// Compile a `PlaybackSnapshot` from resident store state.
    ///
    /// This is the primary path. `SequencerDocumentSession.publishSnapshot()` calls
    /// this overload so that `exportToProject()` is NOT called on each mutation.
    static func compile(state: LiveSequencerStoreState) -> PlaybackSnapshot {
        let trackOrder = state.tracks.map(\.id)
        let resolvedDestinations = compileResolvedDestinations(tracks: state.tracks, trackGroups: state.trackGroups)
        let clipOwnerByID = makeClipOwnerMap(patternBanks: state.patternBanksByTrackID)
        let clipBuffers = Dictionary(uniqueKeysWithValues: state.clipPool.map { clip in
            (clip.id, compileClipBuffer(for: clip, tracks: state.tracks, ownerTrackID: clipOwnerByID[clip.id]))
        })
        let trackPrograms = Dictionary(uniqueKeysWithValues: state.tracks.map { track in
            (track.id, compileTrackSourceProgram(for: track, patternBanksByTrackID: state.patternBanksByTrackID))
        })
        let orderedPhrases = state.phraseOrder.compactMap { state.phrasesByID[$0] }
        let inheritedDefaults = PhraseInheritedDefaults.build(phrases: orderedPhrases, layers: state.layers)
        let phraseBuffers = Dictionary(uniqueKeysWithValues: state.phraseOrder.compactMap { id -> (UUID, PhrasePlaybackBuffer)? in
            guard let phrase = state.phrasesByID[id] else { return nil }
            return (
                phrase.id,
                compilePhraseBuffer(
                    for: phrase,
                    stepOrderMaps: state.stepOrderMaps,
                    layers: state.layers,
                    trackPrograms: trackPrograms,
                    tracks: state.tracks,
                    inherited: inheritedDefaults.resolved(for: phrase.id)
                )
            )
        })

        return PlaybackSnapshot(
            selectedPhraseID: state.selectedPhraseID,
            clipPool: state.clipPool,
            sliceSetPool: state.sliceSetPool,
            generatorPool: state.generatorPool,
            tracks: state.tracks,
            resolvedDestinationsByTrackID: resolvedDestinations,
            trackOrder: trackOrder,
            phraseOrder: state.phraseOrder,
            clipBuffersByID: clipBuffers,
            trackProgramsByTrackID: trackPrograms,
            phraseBuffersByID: phraseBuffers
        )
    }

    static func compile(
        changed: SnapshotChange,
        previous: PlaybackSnapshot,
        state: LiveSequencerStoreState
    ) -> PlaybackSnapshot {
        guard changed.requiresPlaybackSnapshotInstall else {
            return previous
        }
        guard !changed.fullRebuild else {
            return compile(state: state)
        }

        let tracks = replacingTracks(in: previous.tracks, from: state, changedTrackIDs: changed.trackIDs)
        let resolvedDestinations = compileResolvedDestinations(tracks: tracks, trackGroups: state.trackGroups)
        let clipPool = replacingClips(in: previous.clipPool, from: state, changedClipIDs: changed.clipIDs)
        let generatorPool = replacingGenerators(in: previous.generatorPool, from: state, changedGeneratorIDs: changed.generatorIDs)
        let sliceSetPool = replacingSliceSets(in: previous.sliceSetPool, from: state, changedSliceSetIDs: changed.sliceSetIDs)

        let clipOwnerByID = makeClipOwnerMap(patternBanks: state.patternBanksByTrackID)
        var clipBuffersByID = previous.clipBuffersByID
        for clipID in changed.clipIDs {
            guard let clip = state.clipEntry(id: clipID) else {
                return compile(state: state)
            }
            clipBuffersByID[clipID] = compileClipBuffer(for: clip, tracks: tracks, ownerTrackID: clipOwnerByID[clip.id])
        }
        if !changed.trackIDs.isEmpty {
            for trackID in changed.trackIDs {
                // Recompile all clips whose owner track changed.
                for clip in state.clipPool where clipOwnerByID[clip.id] == trackID {
                    clipBuffersByID[clip.id] = compileClipBuffer(for: clip, tracks: tracks, ownerTrackID: trackID)
                }
                // Also recompile clips of the same trackType that have no owner (shared/unowned clips).
                if let track = tracks.first(where: { $0.id == trackID }) {
                    for clip in state.clipPool where clipOwnerByID[clip.id] == nil && clip.trackType == track.trackType {
                        clipBuffersByID[clip.id] = compileClipBuffer(for: clip, tracks: tracks, ownerTrackID: nil)
                    }
                }
            }
        }

        var trackProgramsByTrackID = previous.trackProgramsByTrackID
        for trackID in changed.patternBankTrackIDs.union(changed.trackIDs) {
            guard let track = state.track(id: trackID) else {
                return compile(state: state)
            }
            trackProgramsByTrackID[trackID] = compileTrackSourceProgram(
                for: track,
                patternBanksByTrackID: state.patternBanksByTrackID
            )
        }

        // Phrase buffers depend on tracks ONLY through the phrase-relevant
        // slice of their source program (macro binding order + defaults) and
        // track-set membership. A track change that leaves those intact —
        // e.g. mix, name, destination — must not recompile every phrase
        // buffer in the project (that full recompute on each fader drag tick
        // was mixer-latency cause 1).
        let phraseRelevantTrackChange = changed.trackIDs.contains { trackID in
            let previousProgram = previous.trackProgramsByTrackID[trackID]
            let nextProgram = trackProgramsByTrackID[trackID]
            return previousProgram?.macroBindingIDs != nextProgram?.macroBindingIDs
                || previousProgram?.macroDefaults != nextProgram?.macroDefaults
        }

        let orderedPhrases = state.phraseOrder.compactMap { state.phrasesByID[$0] }
        let inheritedDefaults = PhraseInheritedDefaults.build(phrases: orderedPhrases, layers: state.layers)

        var phraseBuffersByID = previous.phraseBuffersByID
        if changed.layersChanged || phraseRelevantTrackChange {
            phraseBuffersByID = Dictionary(uniqueKeysWithValues: state.phraseOrder.compactMap { phraseID in
                guard let phrase = state.phrasesByID[phraseID] else { return nil }
                return (
                    phraseID,
                    compilePhraseBuffer(
                        for: phrase,
                        stepOrderMaps: state.stepOrderMaps,
                        layers: state.layers,
                        trackPrograms: trackProgramsByTrackID,
                        tracks: tracks,
                        inherited: inheritedDefaults.resolved(for: phraseID)
                    )
                )
            })
        } else {
            let directlyChanged = changed.phraseIDs.union(
                state.phrasesByID.values.compactMap { phrase in
                    guard let mapID = phrase.stepOrderAssignment?.mapID,
                          changed.stepOrderMapIDs.contains(mapID)
                    else {
                        return nil
                    }
                    return phrase.id
                }
            )
            // Forward-only inheritance: editing a phrase can change the value
            // inherited by every *following* phrase in song order. So recompile
            // the changed phrases AND everything after the earliest changed one.
            let changedPhraseIDs = phraseIDsAffectedByInheritance(
                directlyChanged: directlyChanged,
                order: state.phraseOrder
            )
            for phraseID in changedPhraseIDs {
                guard let phrase = state.phrasesByID[phraseID] else {
                    return compile(state: state)
                }
                phraseBuffersByID[phraseID] = compilePhraseBuffer(
                    for: phrase,
                    stepOrderMaps: state.stepOrderMaps,
                    layers: state.layers,
                    trackPrograms: trackProgramsByTrackID,
                    tracks: tracks,
                    inherited: inheritedDefaults.resolved(for: phraseID)
                )
            }
        }

        return PlaybackSnapshot(
            selectedPhraseID: changed.selectedPhraseChanged ? state.selectedPhraseID : previous.selectedPhraseID,
            clipPool: clipPool,
            sliceSetPool: sliceSetPool,
            generatorPool: generatorPool,
            tracks: tracks,
            resolvedDestinationsByTrackID: resolvedDestinations,
            trackOrder: previous.trackOrder,
            phraseOrder: state.phraseOrder,
            clipBuffersByID: clipBuffersByID,
            trackProgramsByTrackID: trackProgramsByTrackID,
            phraseBuffersByID: phraseBuffersByID
        )
    }

    // MARK: - Transitional project-based path

    /// Compile a `PlaybackSnapshot` from a `Project` value.
    ///
    /// Transitional helper retained for call sites that still work from a `Project`
    /// (e.g. `EngineController.apply(documentModel:)` and test utilities that
    /// construct snapshots directly from a fixture `Project`).
    ///
    /// Internally constructs a throwaway `LiveSequencerStoreState` and delegates
    /// to `compile(state:)`.
    ///
    static func compile(project: Project) -> PlaybackSnapshot {
        let banksByID = Dictionary(uniqueKeysWithValues: project.patternBanks.map { ($0.trackID, $0) })
        let phrasesByID = Dictionary(uniqueKeysWithValues: project.phrases.map { ($0.id, $0) })
        let state = LiveSequencerStoreState(
            tracks: project.tracks,
            trackGroups: project.trackGroups,
            generatorPool: project.generatorPool,
            clipPool: project.clipPool,
            sliceSetPool: project.sliceSetPool,
            stepOrderMaps: project.stepOrderMaps,
            layers: project.layers,
            patternBanksByTrackID: banksByID,
            phrasesByID: phrasesByID,
            phraseOrder: project.phrases.map(\.id),
            selectedPhraseID: project.selectedPhraseID
        )
        return compile(state: state)
    }

    // MARK: - Private compilation helpers

    /// Build a map from clip ID → owning track ID by scanning all pattern bank slots.
    ///
    /// A clip is "owned" by the first track whose bank references it. If two tracks
    /// share a clip (via the same clipID in different bank slots), the first bank
    /// entry wins — this is an edge-case the document model currently does not
    /// explicitly forbid but doesn't encourage.
    private static func makeClipOwnerMap(
        patternBanks: [UUID: TrackPatternBank]
    ) -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for (trackID, bank) in patternBanks {
            for slot in bank.slots {
                if let clipID = slot.sourceRef.clipID, result[clipID] == nil {
                    result[clipID] = trackID
                }
            }
        }
        return result
    }

    private static func compileResolvedDestinations(
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) -> [UUID: ResolvedTrackDestination] {
        Dictionary(uniqueKeysWithValues: tracks.map { track in
            guard case .inheritGroup = track.destination else {
                return (track.id, ResolvedTrackDestination(destination: track.destination, pitchOffset: 0))
            }

            guard let groupID = track.groupID,
                  let group = trackGroups.first(where: { $0.id == groupID })
            else {
                return (track.id, ResolvedTrackDestination(destination: .none, pitchOffset: 0))
            }

            let resolved = Project.resolveInheritedPlaybackDestination(trackID: track.id, group: group)
            return (
                track.id,
                ResolvedTrackDestination(destination: resolved.destination, pitchOffset: resolved.pitchOffset)
            )
        })
    }

    private static func compileClipBuffer(
        for clip: ClipPoolEntry,
        tracks: [StepSequenceTrack],
        ownerTrackID: UUID?
    ) -> ClipBuffer {
        let normalized = clip.content.normalized
        let lengthSteps = normalized.stepCount
        let steps: [ClipStepBuffer]
        switch normalized {
        case let .noteGrid(_, clipSteps):
            steps = clipSteps.map(compileStepBuffer)
        case let .sliceTriggers(stepPattern, sliceIndexes, _, _):
            let normalizedIndexes = sliceIndexes.isEmpty ? [60] : sliceIndexes.map { 60 + $0 }
            steps = stepPattern.map { isOn in
                guard isOn else {
                    return ClipStepBuffer(main: nil, fill: nil)
                }
                let notes = normalizedIndexes.map {
                    ClipNoteBuffer(pitch: UInt8(min(max($0, 0), 127)), velocity: 100, lengthSteps: 1)
                }
                return ClipStepBuffer(main: ClipLaneBuffer(chance: 1, notes: notes), fill: nil)
            }
        }

        // Resolve macroBindingOrder using the owner track's macros, keyed by trackID.
        // `trackType` is the wrong key when two tracks of the same type have different
        // AU macro bindings — it non-deterministically resolves the wrong track's macros.
        let ownerMacros = ownerTrackID.flatMap { id in tracks.first(where: { $0.id == id }) }?.macros
        let macroBindingOrder = ownerMacros?
            .sorted { $0.slotIndex < $1.slotIndex }
            .map(\.id) ?? Array(clip.macroLanes.keys).sorted { $0.uuidString < $1.uuidString }
        let macroOverrideValues = (0..<lengthSteps).map { stepIndex in
            macroBindingOrder.map { bindingID in
                let syncedLane = clip.macroLanes[bindingID]?.synced(stepCount: lengthSteps)
                return syncedLane?.values[safe: stepIndex] ?? nil
            }
        }

        return ClipBuffer(
            clipID: clip.id,
            lengthSteps: lengthSteps,
            steps: steps,
            macroBindingOrder: macroBindingOrder,
            macroOverrideValues: macroOverrideValues
        )
    }

    private static func compileStepBuffer(_ step: ClipStep) -> ClipStepBuffer {
        ClipStepBuffer(
            main: compileLaneBuffer(step.main),
            fill: compileLaneBuffer(step.fill)
        )
    }

    private static func compileLaneBuffer(_ lane: ClipLane?) -> ClipLaneBuffer? {
        guard let lane = lane?.normalized else {
            return nil
        }

        return ClipLaneBuffer(
            chance: lane.chance,
            notes: lane.notes.map {
                ClipNoteBuffer(
                    pitch: UInt8(min(max($0.pitch, 0), 127)),
                    velocity: UInt8(min(max($0.velocity, 1), 127)),
                    lengthSteps: UInt16(min(max($0.lengthSteps, 1), Int(UInt16.max)))
                )
            }
        )
    }

    private static func compileTrackSourceProgram(
        for track: StepSequenceTrack,
        patternBanksByTrackID: [UUID: TrackPatternBank]
    ) -> TrackSourceProgram {
        let orderedMacros = track.macros.sorted { $0.slotIndex < $1.slotIndex }
        let bank = patternBanksByTrackID[track.id] ?? TrackPatternBank(trackID: track.id, slots: [])
        let slotPrograms = (0..<TrackPatternBank.slotCount).map { index -> SlotProgram in
            let slot = bank.slot(at: index)
            switch slot.sourceRef.mode {
            case .clip:
                guard let clipID = slot.sourceRef.clipID else {
                    return .empty
                }
                return .clip(
                    clipID: clipID,
                    modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                    modifierBypassed: slot.sourceRef.modifierBypassed
                )
            case .generator:
                guard let generatorID = slot.sourceRef.generatorID else {
                    return .empty
                }
                return .generator(
                    generatorID: generatorID,
                    modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                    modifierBypassed: slot.sourceRef.modifierBypassed
                )
            }
        }

        return TrackSourceProgram(
            trackID: track.id,
            slotPrograms: slotPrograms,
            macroBindingIDs: orderedMacros.map(\.id),
            macroDefaults: Dictionary(uniqueKeysWithValues: orderedMacros.map {
                ($0.id, $0.descriptor.defaultValue)
            })
        )
    }

    /// The set of phrases whose compiled buffers must be rebuilt given a set of
    /// directly-edited phrases. Because inheritance is forward-only, a change to
    /// one phrase invalidates that phrase and every phrase after it in song
    /// order (later inheritors may resolve to a different value).
    private static func phraseIDsAffectedByInheritance(
        directlyChanged: Set<UUID>,
        order: [UUID]
    ) -> Set<UUID> {
        guard !directlyChanged.isEmpty else { return [] }
        guard let earliestIndex = order.firstIndex(where: { directlyChanged.contains($0) }) else {
            // None of the changed phrases are in the ordered list (e.g. a
            // phrase not yet placed): fall back to just the direct set.
            return directlyChanged
        }
        var affected = Set(order[earliestIndex...])
        // Include any directly-changed IDs not present in the order, defensively.
        affected.formUnion(directlyChanged)
        return affected
    }

    private static func compilePhraseBuffer(
        for phrase: PhraseModel,
        stepOrderMaps: [StepOrderMap],
        layers: [PhraseLayerDefinition],
        trackPrograms: [UUID: TrackSourceProgram],
        tracks: [StepSequenceTrack],
        inherited: PhraseInheritedDefaults.Resolved
    ) -> PhrasePlaybackBuffer {
        let stepCount = max(1, phrase.stepCount)
        let patternLayer = layers.first(where: { $0.target == .patternIndex })
        let muteLayer = layers.first(where: { $0.target == .mute })
        let fillLayer = layers.first(where: { $0.target == .macroRow("fill-flag") })
        let densityLayer = layers.first(where: { $0.target == .macroRow("density") })

        let trackStates: [UUID: TrackPhrasePlaybackBuffer] = Dictionary(uniqueKeysWithValues: tracks.map { track in
            let macroBindings = trackPrograms[track.id]?.macroBindingIDs ?? []
            let macroLayers: [UUID: PhraseLayerDefinition] = Dictionary(uniqueKeysWithValues: macroBindings.compactMap { bindingID in
                guard let layer = layers.first(where: { layer in
                    guard case let .macroParam(trackID, candidateBindingID) = layer.target else {
                        return false
                    }
                    return trackID == track.id && candidateBindingID == bindingID
                }) else {
                    return nil
                }

                return (bindingID, layer)
            })

            let patternSlotIndex = (0..<stepCount).map { stepIndex -> UInt8 in
                let index: Int
                if let patternLayer {
                    switch phrase.resolvedValue(for: patternLayer, trackID: track.id, stepIndex: stepIndex, inherited: inherited) {
                    case let .index(value):
                        index = value
                    case let .scalar(value):
                        index = Int(value.rounded())
                    case let .bool(isOn):
                        index = isOn ? 1 : 0
                    }
                } else {
                    index = 0
                }
                return UInt8(min(max(index, 0), TrackPatternBank.slotCount - 1))
            }

            let mute = (0..<stepCount).map { stepIndex -> Bool in
                guard let muteLayer,
                      case let .bool(isMuted) = phrase.resolvedValue(for: muteLayer, trackID: track.id, stepIndex: stepIndex, inherited: inherited)
                else {
                    return false
                }
                return isMuted
            }

            let fillEnabled = (0..<stepCount).map { stepIndex -> Bool in
                guard let fillLayer,
                      case let .bool(isEnabled) = phrase.resolvedValue(for: fillLayer, trackID: track.id, stepIndex: stepIndex, inherited: inherited)
                else {
                    return false
                }
                return isEnabled
            }

            // WS5: density is generation-affecting, so it compiles into its
            // own typed buffer (consumed at note resolution) instead of the
            // dispatch-time macroValues rows.
            let density = (0..<stepCount).map { stepIndex -> Double in
                guard let densityLayer else {
                    return 0
                }
                return scalarDouble(
                    from: phrase.resolvedValue(for: densityLayer, trackID: track.id, stepIndex: stepIndex, inherited: inherited),
                    layer: densityLayer
                )
            }

            let macroValues = (0..<stepCount).map { stepIndex in
                macroBindings.map { bindingID in
                    guard let layer = macroLayers[bindingID] else {
                        return trackPrograms[track.id]?.macroDefaults[bindingID] ?? 0
                    }
                    return scalarDouble(
                        from: phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: stepIndex, inherited: inherited),
                        layer: layer
                    )
                }
            }

            return (
                track.id,
                TrackPhrasePlaybackBuffer(
                    patternSlotIndex: patternSlotIndex,
                    mute: mute,
                    fillEnabled: fillEnabled,
                    density: density,
                    macroValues: macroValues
                )
            )
        })

        return PhrasePlaybackBuffer(
            phraseID: phrase.id,
            stepCount: stepCount,
            repeatCount: phrase.repeatCount,
            loopEnabled: phrase.loopEnabled,
            sceneState: phrase.sceneState,
            stepOrderMap: compiledStepOrderMap(for: phrase, in: stepOrderMaps),
            trackStates: trackStates
        )
    }

    private static func compiledStepOrderMap(
        for phrase: PhraseModel,
        in stepOrderMaps: [StepOrderMap]
    ) -> [UInt8]? {
        guard let assignment = phrase.stepOrderAssignment,
              assignment.isEnabled,
              phrase.stepCount == StepOrderMap.stepCount,
              let map = stepOrderMaps.first(where: { $0.id == assignment.mapID })
        else {
            return nil
        }
        return map.validatedCompiledValues
    }

    private static func scalarDouble(from value: PhraseCellValue, layer: PhraseLayerDefinition) -> Double {
        switch value {
        case let .scalar(x):
            return min(max(x, layer.minValue), layer.maxValue)
        case let .bool(isOn):
            return isOn ? layer.maxValue : layer.minValue
        case let .index(index):
            return min(max(Double(index), layer.minValue), layer.maxValue)
        }
    }

    private static func replacingTracks(
        in previous: [StepSequenceTrack],
        from state: LiveSequencerStoreState,
        changedTrackIDs: Set<UUID>
    ) -> [StepSequenceTrack] {
        guard !changedTrackIDs.isEmpty else {
            return previous
        }

        let updatedByID = Dictionary(uniqueKeysWithValues: state.tracks.map { ($0.id, $0) })
        var tracks = previous
        for index in tracks.indices where changedTrackIDs.contains(tracks[index].id) {
            if let updated = updatedByID[tracks[index].id] {
                tracks[index] = updated
            }
        }
        return tracks
    }

    private static func replacingClips(
        in previous: [ClipPoolEntry],
        from state: LiveSequencerStoreState,
        changedClipIDs: Set<UUID>
    ) -> [ClipPoolEntry] {
        guard !changedClipIDs.isEmpty else {
            return previous
        }

        let updatedByID = Dictionary(uniqueKeysWithValues: state.clipPool.map { ($0.id, $0) })
        var clips = previous
        for index in clips.indices where changedClipIDs.contains(clips[index].id) {
            if let updated = updatedByID[clips[index].id] {
                clips[index] = updated
            }
        }
        return clips
    }

    private static func replacingGenerators(
        in previous: [GeneratorPoolEntry],
        from state: LiveSequencerStoreState,
        changedGeneratorIDs: Set<UUID>
    ) -> [GeneratorPoolEntry] {
        guard !changedGeneratorIDs.isEmpty else {
            return previous
        }

        let updatedByID = Dictionary(uniqueKeysWithValues: state.generatorPool.map { ($0.id, $0) })
        var generators = previous
        for index in generators.indices where changedGeneratorIDs.contains(generators[index].id) {
            if let updated = updatedByID[generators[index].id] {
                generators[index] = updated
            }
        }
        return generators
    }

    private static func replacingSliceSets(
        in previous: [SliceSet],
        from state: LiveSequencerStoreState,
        changedSliceSetIDs: Set<UUID>
    ) -> [SliceSet] {
        guard !changedSliceSetIDs.isEmpty else {
            return previous
        }

        let updatedByID = Dictionary(uniqueKeysWithValues: state.sliceSetPool.map { ($0.id, $0) })
        var sliceSets = previous
        for sliceSetID in changedSliceSetIDs {
            guard let updated = updatedByID[sliceSetID] else {
                return state.sliceSetPool
            }
            if let index = sliceSets.firstIndex(where: { $0.id == sliceSetID }) {
                sliceSets[index] = updated
            } else {
                sliceSets.append(updated)
            }
        }
        return sliceSets
    }
}

private extension LiveSequencerStoreState {
    func clipEntry(id: UUID) -> ClipPoolEntry? {
        clipPool.first(where: { $0.id == id })
    }

    func track(id: UUID) -> StepSequenceTrack? {
        tracks.first(where: { $0.id == id })
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
