import Foundation

extension Project {
    func compatibleGenerators(for track: StepSequenceTrack) -> [GeneratorPoolEntry] {
        generatorPool.filter { $0.trackType == track.trackType }
    }

    func compatibleClips(for track: StepSequenceTrack) -> [ClipPoolEntry] {
        clipPool.filter { $0.trackType == track.trackType }
    }

    func generatorEntry(id: UUID?) -> GeneratorPoolEntry? {
        guard let id else { return nil }
        return generatorPool.first(where: { $0.id == id })
    }

    func clipEntry(id: UUID?) -> ClipPoolEntry? {
        guard let id else { return nil }
        return clipPool.first(where: { $0.id == id })
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
        let merged = SourceRef(mode: .clip, generatorID: slot.sourceRef.generatorID, clipID: clipID)
        setPatternSourceRef(merged, for: trackID, slotIndex: slotIndex)
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
            let newRef = SourceRef(mode: .generator, generatorID: newEntry.id, clipID: existing.sourceRef.clipID)
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
                clipID: existing.sourceRef.clipID
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
                clipID: existing.sourceRef.clipID
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
            clipID: existing.sourceRef.clipID
        )
        bank.setSlot(
            TrackPatternSlot(slotIndex: existing.slotIndex, name: existing.name, sourceRef: newRef),
            at: clamped
        )
        let track = tracks[trackIndex]
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
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
}
