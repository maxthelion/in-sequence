import Foundation

extension SeqAIDocumentModel {
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

    mutating func setPatternGeneratorID(_ generatorID: UUID, for trackID: UUID, slotIndex: Int) {
        setPatternSourceRef(.generator(generatorID), for: trackID, slotIndex: slotIndex)
    }

    mutating func setPatternClipID(_ clipID: UUID, for trackID: UUID, slotIndex: Int) {
        setPatternSourceRef(.clip(clipID), for: trackID, slotIndex: slotIndex)
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
