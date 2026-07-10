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
                sourceClipID: slot.sourceRef.sourceClipID,
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
                sourceClipID: slot.sourceRef.sourceClipID,
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

    @discardableResult
    func bakeRandomizedClip(
        at address: PatternSlotAddress,
        settings: ClipRandomizeSettings,
        seed: UInt64,
        impact: LiveMutationImpact = .snapshotOnly
    ) -> UUID? {
        var bakedClipID: UUID?
        _ = ensureClipAndMutate(at: address, impact: impact) { clipID, entry in
            var persistedSettings = settings.normalized
            persistedSettings.lastSeed = seed
            entry.content = ClipRandomizeBaker.bake(
                source: entry.content,
                settings: persistedSettings,
                seed: seed
            )
            entry.randomizeSettings = persistedSettings
            bakedClipID = clipID
        }
        return bakedClipID
    }

    @discardableResult
    func bakeRandomizedSelectedClip(
        trackID: UUID,
        settings: ClipRandomizeSettings,
        seed: UInt64,
        impact: LiveMutationImpact = .snapshotOnly
    ) -> UUID? {
        bakeRandomizedClip(
            at: PatternSlotAddress(trackID: trackID, slotIndex: store.selectedPatternIndex(for: trackID)),
            settings: settings,
            seed: seed,
            impact: impact
        )
    }

    @discardableResult
    func restoreClipSnapshot(
        _ snapshot: ClipPoolEntry,
        at address: PatternSlotAddress,
        impact: LiveMutationImpact = .snapshotOnly
    ) -> Bool {
        var changed = false
        batch(impact: impact, changed: .clip(snapshot.id).union(.patternBank(address.trackID))) { store in
            let slot = store.patternBank(for: address.trackID).slot(at: address.slotIndex)
            guard slot.sourceRef.clipID == snapshot.id else { return }
            changed = store.mutateClip(id: snapshot.id) { entry in
                entry = snapshot
            }
        }
        return changed
    }

    @discardableResult
    func auditionRandomizedClip(
        at address: PatternSlotAddress,
        settings: ClipRandomizeSettings,
        seed: UInt64
    ) -> PseudoClipState? {
        let slot = store.patternBank(for: address.trackID).slot(at: address.slotIndex)
        guard let clip = store.clipEntry(id: slot.sourceRef.clipID) else {
            return nil
        }
        let bakedContent = ClipRandomizeBaker.bake(
            source: clip.content,
            settings: settings,
            seed: seed
        )
        let state = PseudoClipState(
            sourceTrackID: address.trackID,
            startStep: 0,
            lengthSteps: bakedContent.cycleLength,
            noteGrid: bakedContent
        )
        engineController.setAuditionOverride(state, for: address.trackID)
        return state
    }

    @discardableResult
    func auditionRandomizedSelectedClip(
        trackID: UUID,
        settings: ClipRandomizeSettings,
        seed: UInt64
    ) -> PseudoClipState? {
        auditionRandomizedClip(
            at: PatternSlotAddress(trackID: trackID, slotIndex: store.selectedPatternIndex(for: trackID)),
            settings: settings,
            seed: seed
        )
    }

    func clearRandomizeAudition(trackID: UUID) {
        engineController.setAuditionOverride(nil, for: trackID)
    }

    @discardableResult
    func switchGeneratorKind(id generatorID: UUID, to kind: GeneratorKind) -> Bool {
        guard let entry = store.generatorEntry(id: generatorID),
              kind.isCreatable,
              kind.compatibleWith.contains(entry.trackType)
        else {
            return false
        }

        mutateGenerator(id: generatorID) { entry in
            entry = entry.switchingKind(to: kind)
        }
        return true
    }

    /// WS4 header dice: bake the slot's generator into a NEW clip and point
    /// the slot at it — the synthesis doc's one-way conversion primitive
    /// `bake(source, seed) -> clip content` applied to a generator source.
    /// The generator recipe is retained on the slot for later switch-back, but
    /// legacy source-as-modifier state is not left active on the baked clip.
    @discardableResult
    func bakeGeneratorToClip(trackID: UUID, slotIndex: Int, chordContext: Chord? = nil) -> UUID? {
        let slot = store.patternBank(for: trackID).slot(at: slotIndex)
        guard slot.sourceRef.mode == .generator,
              let generator = store.generatorEntry(id: slot.sourceRef.generatorID)
        else {
            return nil
        }

        let snapshot = SequencerSnapshotCompiler.compile(state: store.compileInput())
        let effectiveChordContext = chordContext ?? engineController.chordContextByLane["default"]
        var state = GeneratedSourceEvaluationState()
        var rng = PreviewRNG()
        let notesByStep = (0..<16).map { stepIndex in
            EngineController.resolvedStepNotes(
                for: trackID,
                in: snapshot,
                phraseID: snapshot.selectedPhraseID,
                stepIndex: stepIndex,
                chordContext: effectiveChordContext,
                quantisedPatternSlotOverrides: [trackID: slotIndex],
                state: &state,
                rng: &rng
            )
        }
        let steps = notesByStep.map { notes -> ClipStep in
            guard !notes.isEmpty else { return .empty }
            return ClipStep(
                main: ClipLane(
                    chance: 1,
                    notes: notes.map { note in
                        ClipStepNote(
                            pitch: note.pitch,
                            velocity: note.velocity,
                            lengthSteps: note.length
                        ).normalized
                    }
                ),
                fill: nil
            )
        }
        let content = ClipContent.noteGrid(lengthSteps: steps.count, steps: steps).normalized

        var bakedClipID: UUID?
        batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            let existingClipIDs = Set(store.clipPool.map(\.id))
            bakedClipID = project.bakeGeneratorSourceToClip(
                trackID: trackID,
                slotIndex: slotIndex,
                name: "\(generator.name) Bake",
                content: content,
                preserveSeparateModifier: slot.sourceRef.modifierBypassed
            )
            guard bakedClipID != nil else {
                return
            }
            for clip in project.clipPool where !existingClipIDs.contains(clip.id) {
                store.appendClip(clip)
            }
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else {
                return
            }
            store.setPatternBank(trackID: trackID, bank: bank)
        }
        return bakedClipID
    }

    @discardableResult
    func bakeChordTrackToClip(trackID: UUID, slotIndex: Int) -> UUID? {
        var bakedClipID: UUID?
        batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            let existingClipIDs = Set(store.clipPool.map(\.id))
            bakedClipID = project.bakeChordSourceToClip(
                trackID: trackID,
                slotIndex: slotIndex
            )
            guard bakedClipID != nil else {
                return
            }
            for clip in project.clipPool where !existingClipIDs.contains(clip.id) {
                store.appendClip(clip)
            }
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else {
                return
            }
            store.setPatternBank(trackID: trackID, bank: bank)
        }
        return bakedClipID
    }

    func restoreChordSourceClip(trackID: UUID, slotIndex: Int) {
        mutatePatternBank(trackID: trackID) { bank in
            let slot = bank.slot(at: slotIndex)
            guard let sourceClipID = slot.sourceRef.sourceClipID else {
                return
            }
            let restored = SourceRef(
                mode: .clip,
                generatorID: slot.sourceRef.generatorID,
                clipID: sourceClipID,
                sourceClipID: nil,
                modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                modifierBypassed: slot.sourceRef.modifierBypassed
            )
            bank.setSlot(
                TrackPatternSlot(slotIndex: slot.slotIndex, name: slot.name, sourceRef: restored),
                at: slotIndex
            )
        }
    }
}
