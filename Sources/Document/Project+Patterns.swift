import Foundation

extension Project {
    var patternLayer: PhraseLayerDefinition? {
        layers.first(where: { $0.target == .patternIndex })
    }

    func patternBank(for trackID: UUID) -> TrackPatternBank {
        patternBanks.first(where: { $0.trackID == trackID })
            ?? TrackPatternBank.default(
                for: tracks.first(where: { $0.id == trackID }) ?? .default,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
    }

    func layer(id: String) -> PhraseLayerDefinition? {
        layers.first(where: { $0.id == id })
    }

    func cell(for trackID: UUID, layerID: String, phraseID: UUID? = nil) -> PhraseCell {
        let phrase = phrases.first(where: { $0.id == phraseID }) ?? selectedPhrase
        return phrase.cell(for: layerID, trackID: trackID)
    }

    func selectedPatternIndex(for trackID: UUID) -> Int {
        selectedPhrase.patternIndex(for: trackID, layers: layers)
    }

    func selectedPattern(for trackID: UUID) -> TrackPatternSlot {
        patternBank(for: trackID).slot(at: selectedPatternIndex(for: trackID))
    }

    func selectedSourceRef(for trackID: UUID) -> SourceRef {
        selectedPattern(for: trackID).sourceRef
    }

    func selectedSourceMode(for trackID: UUID) -> TrackSourceMode {
        selectedSourceRef(for: trackID).mode
    }

    mutating func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        var phrase = selectedPhrase
        phrase.setPatternIndex(index, for: trackID, layers: layers)
        selectedPhrase = phrase
    }

    mutating func setPatternSourceMode(_ mode: TrackSourceMode, for trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        var bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        let sourceRef = defaultSourceRef(for: mode, trackType: track.trackType)
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: sourceRef),
            at: slotIndex
        )
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    mutating func setPatternName(_ name: String, for trackID: UUID, slotIndex: Int) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID })
        else {
            return
        }

        let track = tracks[trackIndex]
        var bank = patternBanks[bankIndex]
        let slot = bank.slot(at: slotIndex)
        bank.setSlot(
            TrackPatternSlot(slotIndex: slot.slotIndex, name: name, sourceRef: slot.sourceRef),
            at: slotIndex
        )
        patternBanks[bankIndex] = bank.synced(track: track, generatorPool: generatorPool, clipPool: clipPool)
    }

    private func defaultSourceRef(for mode: TrackSourceMode, trackType: TrackType) -> SourceRef {
        switch mode {
        case .generator:
            return .generator(generatorPool.first(where: { $0.trackType == trackType })?.id)
        case .clip:
            return .clip(clipPool.first(where: { $0.trackType == trackType })?.id)
        }
    }
}
