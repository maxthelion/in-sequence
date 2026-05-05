import Foundation

extension Project {
    func compatibleGenerators(for track: StepSequenceTrack) -> [GeneratorPoolEntry] {
        generatorPool.filter { $0.trackType == track.trackType }
    }

    func compatibleModifierGenerators(for track: StepSequenceTrack) -> [GeneratorPoolEntry] {
        generatorPool.filter { $0.trackType == track.trackType && $0.kind.supportsModifierStage }
    }

    func compatibleClips(for track: StepSequenceTrack) -> [ClipPoolEntry] {
        clipPool.filter { $0.trackType == track.trackType }
    }

    func generatedSourceInputClips() -> [ClipPoolEntry] {
        clipPool
    }

    func harmonicSidechainClips() -> [ClipPoolEntry] {
        clipPool.filter(\.hasPitchMaterial)
    }

    func generatorEntry(id: UUID?) -> GeneratorPoolEntry? {
        guard let id else { return nil }
        return generatorPool.first(where: { $0.id == id })
    }

    func clipEntry(id: UUID?) -> ClipPoolEntry? {
        guard let id else { return nil }
        return clipPool.first(where: { $0.id == id })
    }

    @discardableResult
    mutating func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
        let slotIndex = selectedPatternIndex(for: trackID)
        guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            NSLog("[Project] ensureClipForCurrentPattern missing pattern bank trackID=\(trackID)")
            return nil
        }

        let bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        if let existing = slot.sourceRef.clipID {
            return existing
        }

        return createBlankClipSource(trackID: trackID, slotIndex: slotIndex)
    }

    mutating func removeSelectedSlotSource(trackID: UUID, slotIndex: Int) {
        guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            return
        }
        let slot = patternBanks[bankIndex].slot(at: slotIndex)
        let updated = SourceRef(
            mode: .clip,
            generatorID: slot.sourceRef.generatorID,
            clipID: nil,
            modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
            modifierBypassed: slot.sourceRef.modifierBypassed
        )
        setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
        reconcileAttachedGeneratorID(for: trackID, preferredGeneratorID: updated.generatorID)
    }

    @discardableResult
    mutating func createBlankClipSource(trackID: UUID, slotIndex: Int) -> UUID? {
        guard let track = tracks.first(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return nil
        }
        let slot = patternBanks[bankIndex].slot(at: slotIndex)

        let newClip = ClipPoolEntry(
            id: UUID(),
            name: "\(track.name) pattern \(slot.slotIndex + 1)",
            trackType: track.trackType,
            content: blankClipContent(for: track.trackType)
        )
        clipPool.append(newClip)

        assignClipSource(newClip.id, to: trackID, slotIndex: slotIndex)
        return newClip.id
    }

    mutating func setPatternSourceRef(_ sourceRef: SourceRef, for trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        var bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: sourceRef),
            at: slotIndex
        )
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func setPatternClipID(_ clipID: UUID, for trackID: UUID, slotIndex: Int) {
        guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            return
        }
        let bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        // Preserve the existing generatorID so bypass→change-clip→un-bypass re-engages the same generator.
        let merged = SourceRef(
            mode: .clip,
            generatorID: slot.sourceRef.generatorID,
            clipID: clipID,
            modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
            modifierBypassed: slot.sourceRef.modifierBypassed
        )
        setPatternSourceRef(merged, for: trackID, slotIndex: slotIndex)
    }

    mutating func assignClipSource(_ clipID: UUID, to trackID: UUID, slotIndex: Int) {
        guard let track = tracks.first(where: { $0.id == trackID }),
              clipPool.contains(where: { $0.id == clipID && $0.trackType == track.trackType })
        else {
            return
        }
        setPatternClipID(clipID, for: trackID, slotIndex: slotIndex)
        let preferredGeneratorID = patternBank(for: trackID).slot(at: slotIndex).sourceRef.generatorID
        reconcileAttachedGeneratorID(for: trackID, preferredGeneratorID: preferredGeneratorID)
    }

    @discardableResult
    mutating func createBlankGeneratorSource(trackID: UUID, slotIndex: Int) -> GeneratorPoolEntry? {
        guard let track = tracks.first(where: { $0.id == trackID }),
              patternBanks.contains(where: { $0.trackID == trackID })
        else {
            return nil
        }
        guard let templateKind = GeneratorKind.allCases.first(where: { $0.compatibleWith.contains(track.trackType) }) else {
            return nil
        }

        let nextIndex = generatorPool.filter { $0.trackType == track.trackType }.count + 1
        let newEntry = GeneratorPoolEntry(
            id: UUID(),
            name: "\(templateKind.label) \(nextIndex)",
            trackType: track.trackType,
            kind: templateKind,
            params: templateKind.defaultParams
        )
        generatorPool.append(newEntry)
        assignGeneratorSource(newEntry.id, to: trackID, slotIndex: slotIndex)
        return newEntry
    }

    mutating func assignGeneratorSource(_ generatorID: UUID, to trackID: UUID, slotIndex: Int) {
        guard let track = tracks.first(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }),
              generatorPool.contains(where: { $0.id == generatorID && $0.trackType == track.trackType })
        else {
            return
        }
        let slot = patternBanks[bankIndex].slot(at: slotIndex)
        let updated = SourceRef(
            mode: .generator,
            generatorID: generatorID,
            clipID: slot.sourceRef.clipID,
            modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
            modifierBypassed: slot.sourceRef.modifierBypassed
        )
        setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
        reconcileAttachedGeneratorID(for: trackID, preferredGeneratorID: generatorID)
    }

    @discardableResult
    mutating func createBlankModifierGenerator(trackID: UUID, slotIndex: Int) -> GeneratorPoolEntry? {
        guard let track = tracks.first(where: { $0.id == trackID }),
              patternBanks.contains(where: { $0.trackID == trackID }),
              let templateKind = GeneratorKind.allCases.first(where: {
                  $0.compatibleWith.contains(track.trackType) && $0.supportsModifierStage
              })
        else {
            return nil
        }

        let nextIndex = generatorPool.filter { $0.trackType == track.trackType }.count + 1
        let newEntry = GeneratorPoolEntry(
            id: UUID(),
            name: "\(templateKind.label) \(nextIndex)",
            trackType: track.trackType,
            kind: templateKind,
            params: templateKind.defaultParams
        )
        generatorPool.append(newEntry)
        assignModifierGenerator(newEntry.id, to: trackID, slotIndex: slotIndex)
        return newEntry
    }

    mutating func assignModifierGenerator(_ modifierGeneratorID: UUID, to trackID: UUID, slotIndex: Int) {
        guard let track = tracks.first(where: { $0.id == trackID }),
              generatorPool.contains(where: {
                  $0.id == modifierGeneratorID
                      && $0.trackType == track.trackType
                      && $0.kind.supportsModifierStage
              })
        else {
            return
        }

        setPatternModifierGeneratorID(modifierGeneratorID, for: trackID, slotIndex: slotIndex)
    }

    mutating func removeModifierGenerator(from trackID: UUID, slotIndex: Int) {
        setPatternModifierGeneratorID(nil, for: trackID, slotIndex: slotIndex)
    }

    mutating func updateGeneratorEntry(id: UUID, _ update: (inout GeneratorPoolEntry) -> Void) {
        guard let index = generatorPool.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&generatorPool[index])
    }

    mutating func updateClipEntry(id: UUID, _ update: (inout ClipPoolEntry) -> Void) {
        guard let index = clipPool.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&clipPool[index])
    }

    @discardableResult
    mutating func attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry? {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return nil
        }

        let track = tracks[trackIndex]
        guard let templateKind = GeneratorKind.allCases.first(where: { $0.compatibleWith.contains(track.trackType) }) else {
            return nil
        }

        let nextIndex = generatorPool.filter { $0.trackType == track.trackType }.count + 1
        let newEntry = GeneratorPoolEntry(
            id: UUID(),
            name: "\(templateKind.label) \(nextIndex)",
            trackType: track.trackType,
            kind: templateKind,
            params: templateKind.defaultParams
        )
        generatorPool.append(newEntry)

        var bank = patternBanks[bankIndex]
        bank.attachedGeneratorID = newEntry.id
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(
                mode: existing.sourceRef.mode,
                generatorID: newEntry.id,
                clipID: existing.sourceRef.clipID,
                modifierGeneratorID: newEntry.id,
                modifierBypassed: existing.sourceRef.modifierBypassed
            )
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
        return newEntry
    }

    mutating func removeAttachedGenerator(from trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        var bank = patternBanks[bankIndex]
        guard bank.attachedGeneratorID != nil else {
            return
        }

        bank.attachedGeneratorID = nil
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(
                mode: .clip,
                generatorID: existing.sourceRef.generatorID,
                clipID: existing.sourceRef.clipID,
                modifierGeneratorID: existing.sourceRef.modifierGeneratorID,
                modifierBypassed: existing.sourceRef.modifierBypassed
            )
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func switchAttachedGenerator(to newGeneratorID: UUID, for trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        var bank = patternBanks[bankIndex]
        bank.attachedGeneratorID = newGeneratorID
        for index in 0..<bank.slots.count {
            let existing = bank.slots[index]
            let newRef = SourceRef(
                mode: existing.sourceRef.mode,
                generatorID: newGeneratorID,
                clipID: existing.sourceRef.clipID,
                modifierGeneratorID: newGeneratorID,
                modifierBypassed: existing.sourceRef.modifierBypassed
            )
            bank.slots[index] = TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef)
        }
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }
        var bank = patternBanks[bankIndex]
        guard bank.attachedGeneratorID != nil else {
            return
        }

        let clamped = min(max(slotIndex, 0), TrackPatternBank.slotCount - 1)
        let existing = bank.slot(at: clamped)
        let newMode: TrackSourceMode = bypassed ? .clip : .generator
        let newRef = SourceRef(
            mode: newMode,
            generatorID: existing.sourceRef.generatorID,
            clipID: existing.sourceRef.clipID,
            modifierGeneratorID: existing.sourceRef.modifierGeneratorID,
            modifierBypassed: existing.sourceRef.modifierBypassed
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef),
            at: clamped
        )
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func setPatternModifierGeneratorID(
        _ modifierGeneratorID: UUID?,
        bypassed: Bool = false,
        for trackID: UUID,
        slotIndex: Int
    ) {
        guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            return
        }
        let slot = patternBanks[bankIndex].slot(at: slotIndex)
        let updated = SourceRef(
            mode: slot.sourceRef.mode,
            generatorID: slot.sourceRef.generatorID,
            clipID: slot.sourceRef.clipID,
            modifierGeneratorID: modifierGeneratorID,
            modifierBypassed: modifierGeneratorID == nil ? false : bypassed
        )
        setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
    }

    mutating func setPatternModifierBypassed(
        _ bypassed: Bool,
        for trackID: UUID,
        slotIndex: Int
    ) {
        guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            return
        }
        let slot = patternBanks[bankIndex].slot(at: slotIndex)
        guard slot.sourceRef.modifierGeneratorID != nil else {
            return
        }
        let updated = SourceRef(
            mode: slot.sourceRef.mode,
            generatorID: slot.sourceRef.generatorID,
            clipID: slot.sourceRef.clipID,
            modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
            modifierBypassed: bypassed
        )
        setPatternSourceRef(updated, for: trackID, slotIndex: slotIndex)
    }

    @discardableResult
    mutating func ensureCompatibleClip(for track: StepSequenceTrack) -> ClipPoolEntry? {
        if let existing = compatibleClips(for: track).first {
            return existing
        }

        guard let template = ClipPoolEntry.defaultPool.first(where: { $0.trackType == track.trackType }) else {
            return nil
        }

        clipPool.append(template)
        return template
    }

    private func blankClipContent(for trackType: TrackType) -> ClipContent {
        switch trackType {
        case .slice:
            return .emptySliceTriggers(lengthSteps: 16)
        case .monoMelodic, .polyMelodic:
            return .emptyNoteGrid(lengthSteps: 16)
        }
    }

    mutating func reconcileAttachedGeneratorID(for trackID: UUID, preferredGeneratorID: UUID? = nil) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        let compatibleGeneratorIDs = Set(
            generatorPool
                .filter { $0.trackType == track.trackType }
                .map(\.id)
        )

        var bank = patternBanks[bankIndex]
        let candidateIDs = [preferredGeneratorID] + bank.slots.map(\.sourceRef.generatorID)
        bank.attachedGeneratorID = candidateIDs
            .compactMap { $0 }
            .first(where: { compatibleGeneratorIDs.contains($0) })
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }
}
