import Foundation

struct ResolvedTrackPlaybackStep: Equatable, Sendable {
    let slotIndex: Int
    let mute: Bool
    let fillEnabled: Bool
    let macroValues: [UUID: Double]
}

struct PlaybackSnapshot: Equatable, Sendable {
    // NOTE: `project` has been removed. The tick path reads typed fields only.
    // Phase 1b of the live-store v2 remediation.
    let selectedPhraseID: UUID
    let clipPool: [ClipPoolEntry]
    let generatorPool: [GeneratorPoolEntry]
    /// Ordered track list, carried from `LiveSequencerStoreState.tracks`.
    /// The tick path iterates this instead of `currentDocumentModel.tracks` (Phase 1b).
    let tracks: [StepSequenceTrack]
    let trackOrder: [UUID]
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

    // MARK: - Buffer accessors

    func phraseBuffer(for phraseID: UUID) -> PhrasePlaybackBuffer? {
        phraseBuffersByID[phraseID]
    }

    func sourceProgram(for trackID: UUID) -> TrackSourceProgram? {
        trackProgramsByTrackID[trackID]
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

        let normalizedIndex = ((stepInPhrase % phraseBuffer.stepCount) + phraseBuffer.stepCount) % phraseBuffer.stepCount
        let slotIndex = Int(trackState.patternSlotIndex[normalizedIndex])
        var resolvedMacros = Dictionary(
            uniqueKeysWithValues: zip(program.macroBindingIDs, trackState.macroValues[normalizedIndex])
        )

        if case let .clip(clipID, _, _) = program.slotProgram(at: slotIndex),
           let clip = clipBuffersByID[clipID]
        {
            let clipStep = ((normalizedIndex % clip.lengthSteps) + clip.lengthSteps) % clip.lengthSteps
            for (bindingID, value) in clip.macroOverrides(at: clipStep) {
                resolvedMacros[bindingID] = value
            }
        }

        return ResolvedTrackPlaybackStep(
            slotIndex: slotIndex,
            mute: trackState.mute[normalizedIndex],
            fillEnabled: trackState.fillEnabled[normalizedIndex],
            macroValues: resolvedMacros
        )
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
