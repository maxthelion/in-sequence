import Foundation

struct ResolvedTrackPlaybackStep: Equatable, Sendable {
    let sourceStepIndex: Int
    let slotIndex: Int
    let mute: Bool
    let fillEnabled: Bool
    /// Phrase-layer DENSITY macro value (0..1, WS5) — generation-affecting,
    /// consumed at note resolution (never a dispatch-time macro).
    let density: Double
    let macroValues: [UUID: Double]
}

struct ResolvedTrackDestination: Equatable, Sendable {
    let destination: Destination
    let pitchOffset: Int
}

struct PlaybackSnapshot: Equatable, Sendable {
    // NOTE: `project` has been removed. The tick path reads typed fields only.
    // Phase 1b of the live-store v2 remediation.
    let selectedPhraseID: UUID
    let clipPool: [ClipPoolEntry]
    let sliceSetPool: [SliceSet]
    let generatorPool: [GeneratorPoolEntry]
    /// Ordered track list, carried from `LiveSequencerStoreState.tracks`.
    /// The tick path iterates this instead of `currentDocumentModel.tracks` (Phase 1b).
    let tracks: [StepSequenceTrack]
    let resolvedDestinationsByTrackID: [UUID: ResolvedTrackDestination]
    let trackOrder: [UUID]
    let phraseOrder: [UUID]
    let clipBuffersByID: [UUID: ClipBuffer]
    let trackProgramsByTrackID: [UUID: TrackSourceProgram]
    let phraseBuffersByID: [UUID: PhrasePlaybackBuffer]

    // MARK: - O(1) lookup helpers

    func clipEntry(id: UUID?) -> ClipPoolEntry? {
        guard let id else { return nil }
        return clipPool.first(where: { $0.id == id })
    }

    func generatorEntry(id: UUID?) -> GeneratorPoolEntry? {
        guard let id else { return nil }
        return generatorPool.first(where: { $0.id == id })
    }

    func sliceSet(id: UUID?) -> SliceSet? {
        guard let id else { return nil }
        if id == SliceSet.emptyID {
            return SliceSet.empty
        }
        return sliceSetPool.first(where: { $0.id == id })
    }

    // MARK: - Buffer accessors

    func phraseBuffer(for phraseID: UUID) -> PhrasePlaybackBuffer? {
        phraseBuffersByID[phraseID]
    }

    func replacingPhraseBuffer(_ phraseBuffer: PhrasePlaybackBuffer) -> PlaybackSnapshot {
        var phraseBuffers = phraseBuffersByID
        phraseBuffers[phraseBuffer.phraseID] = phraseBuffer
        return PlaybackSnapshot(
            selectedPhraseID: selectedPhraseID,
            clipPool: clipPool,
            sliceSetPool: sliceSetPool,
            generatorPool: generatorPool,
            tracks: tracks,
            resolvedDestinationsByTrackID: resolvedDestinationsByTrackID,
            trackOrder: trackOrder,
            phraseOrder: phraseOrder,
            clipBuffersByID: clipBuffersByID,
            trackProgramsByTrackID: trackProgramsByTrackID,
            phraseBuffersByID: phraseBuffers
        )
    }

    func sourceProgram(for trackID: UUID) -> TrackSourceProgram? {
        trackProgramsByTrackID[trackID]
    }

    func resolvedDestination(for trackID: UUID) -> ResolvedTrackDestination {
        resolvedDestinationsByTrackID[trackID] ?? ResolvedTrackDestination(destination: .none, pitchOffset: 0)
    }

    func resolvedStep(
        phraseID: UUID,
        trackID: UUID,
        stepInPhrase: Int
    ) -> ResolvedTrackPlaybackStep? {
        guard let phraseBuffer = phraseBuffersByID[phraseID],
              let trackState = phraseBuffer.trackState(for: trackID),
              let program = trackProgramsByTrackID[trackID]
        else {
            return nil
        }

        let outputStepIndex = ((stepInPhrase % phraseBuffer.stepCount) + phraseBuffer.stepCount) % phraseBuffer.stepCount
        let sourceStepIndex = phraseBuffer.sourceStepIndex(for: outputStepIndex)
        let slotIndex = Int(trackState.patternSlotIndex[sourceStepIndex])
        var resolvedMacros = Dictionary(
            uniqueKeysWithValues: zip(program.macroBindingIDs, trackState.macroValues[outputStepIndex])
        )

        if case let .clip(clipID, _, _) = program.slotProgram(at: slotIndex),
           let clip = clipBuffersByID[clipID]
        {
            let clipStep = ((sourceStepIndex % clip.lengthSteps) + clip.lengthSteps) % clip.lengthSteps
            for (bindingID, value) in clip.macroOverrides(at: clipStep) {
                resolvedMacros[bindingID] = value
            }
        }

        return ResolvedTrackPlaybackStep(
            sourceStepIndex: sourceStepIndex,
            slotIndex: slotIndex,
            mute: trackState.mute[outputStepIndex],
            fillEnabled: trackState.fillEnabled[outputStepIndex],
            density: trackState.density.indices.contains(outputStepIndex) ? trackState.density[outputStepIndex] : 0,
            macroValues: resolvedMacros
        )
    }

    /// Fallback ghost pitch for the density transform when a source carries
    /// no representative hits.
    func fallbackPitch(for trackID: UUID) -> Int {
        tracks.first(where: { $0.id == trackID })?.pitches.first ?? 60
    }

    func layerSnapshot(phraseID: UUID, stepInPhrase: Int) -> LayerSnapshot {
        guard let phraseBuffer = phraseBuffersByID[phraseID] else {
            return .empty
        }

        let normalizedIndex = ((stepInPhrase % phraseBuffer.stepCount) + phraseBuffer.stepCount) % phraseBuffer.stepCount
        var mute: [UUID: Bool] = [:]
        var fillEnabled: [UUID: Bool] = [:]
        var macroValues: [UUID: [UUID: Double]] = [:]

        for trackID in trackOrder {
            guard let resolved = resolvedStep(phraseID: phraseID, trackID: trackID, stepInPhrase: normalizedIndex) else {
                continue
            }
            if resolved.mute {
                mute[trackID] = true
            }
            if resolved.fillEnabled {
                fillEnabled[trackID] = true
            }
            if !resolved.macroValues.isEmpty {
                macroValues[trackID] = resolved.macroValues
            }
        }

        return LayerSnapshot(mute: mute, fillEnabled: fillEnabled, macroValues: macroValues)
    }
}
