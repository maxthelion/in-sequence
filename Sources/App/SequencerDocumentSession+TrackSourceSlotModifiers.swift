import Foundation

extension SequencerDocumentSession {
    func setPhraseCell(
        _ cell: PhraseCell,
        at address: PhraseCellAddress,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        guard let phraseID = address.phraseID else {
            return
        }
        setPhraseCell(
            cell,
            layerID: address.layerID,
            trackIDs: [address.trackID],
            phraseID: phraseID,
            impact: impact
        )
    }

    func setPatternSourceRef(
        _ sourceRef: SourceRef,
        at address: PatternSlotAddress,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        setPatternSourceRef(sourceRef, for: address.trackID, slotIndex: address.slotIndex, impact: impact)
    }

    @discardableResult
    func createBlankModifierGenerator(trackID: UUID, slotIndex: Int) -> GeneratorPoolEntry? {
        createBlankModifierGenerator(at: PatternSlotAddress(trackID: trackID, slotIndex: slotIndex))
    }

    @discardableResult
    func createBlankModifierGenerator(at address: PatternSlotAddress) -> GeneratorPoolEntry? {
        var created: GeneratorPoolEntry?
        batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            created = project.createBlankModifierGenerator(trackID: address.trackID, slotIndex: address.slotIndex)
            guard let bank = project.patternBanks.first(where: { $0.trackID == address.trackID }) else {
                return
            }
            if let created {
                store.appendGenerator(created)
            }
            store.setPatternBank(trackID: address.trackID, bank: bank)
        }
        return created
    }

    func assignModifierGenerator(_ modifierGeneratorID: UUID, to trackID: UUID, slotIndex: Int) {
        assignModifierGenerator(
            modifierGeneratorID,
            to: PatternSlotAddress(trackID: trackID, slotIndex: slotIndex)
        )
    }

    func assignModifierGenerator(_ modifierGeneratorID: UUID, to address: PatternSlotAddress) {
        batch(impact: .snapshotOnly, changed: .patternBank(address.trackID)) { store in
            var project = store.exportToProject()
            project.assignModifierGenerator(modifierGeneratorID, to: address.trackID, slotIndex: address.slotIndex)
            guard let bank = project.patternBanks.first(where: { $0.trackID == address.trackID }) else {
                return
            }
            store.setPatternBank(trackID: address.trackID, bank: bank)
        }
    }

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

    func setPatternModifierBypassed(_ bypassed: Bool, at address: PatternSlotAddress) {
        setPatternModifierBypassed(bypassed, for: address.trackID, slotIndex: address.slotIndex)
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

    func setPatternModifierGeneratorID(_ modifierGeneratorID: UUID?, at address: PatternSlotAddress) {
        setPatternModifierGeneratorID(modifierGeneratorID, for: address.trackID, slotIndex: address.slotIndex)
    }

    /// Ensure the addressed pattern slot has a clip, then mutate that clip.
    ///
    /// This mirrors `ensureClipAndMutate(trackID:)` but keeps the track/slot pair
    /// bundled so call sites do not pass a selected track and selected slot as
    /// separate primitive values.
    @discardableResult
    func ensureClipAndMutate(
        at address: PatternSlotAddress,
        impact: LiveMutationImpact = .snapshotOnly,
        _ update: (UUID, inout ClipPoolEntry) -> Void
    ) -> UUID? {
        let existingClipID = store.patternBank(for: address.trackID).slot(at: address.slotIndex).sourceRef.clipID
        let initialChange = existingClipID.map { SnapshotChange.clip($0).union(.patternBank(address.trackID)) } ?? .full
        batch(impact: impact, changed: initialChange) { store in
            var project = store.exportToProject()
            guard let clipID = project.ensureClip(at: address) else { return }
            for clip in project.clipPool where store.exportToProject().clipPool.first(where: { $0.id == clip.id }) == nil {
                store.appendClip(clip)
            }
            for bank in project.patternBanks {
                store.setPatternBank(trackID: bank.trackID, bank: bank)
            }
            store.mutateClip(id: clipID) { entry in
                update(clipID, &entry)
            }
        }
        return nil
    }
}
