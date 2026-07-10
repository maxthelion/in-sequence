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
    private func dispatchImpact(_ impact: LiveMutationImpact, changed change: SnapshotChange = .full) {
        revision = store.revision
        switch impact {
        case .snapshotOnly:
            if change.requiresPlaybackSnapshotInstall {
                publishSnapshot(changed: change)
            }
        case .fullEngineApply:
            // apply(documentModel:) installs a fresh snapshot internally.
            // Also update the publisher so UI visualisers see the new state.
            // We read currentPlaybackSnapshotForTesting to avoid a second compile call.
            engineController.apply(documentModel: store.exportToProject())
            snapshotPublisher.replace(engineController.currentPlaybackSnapshotForTesting)
        case .scopedRuntime(let update):
            dispatchScopedRuntimeUpdate(update)
            if change.requiresPlaybackSnapshotInstall {
                publishSnapshot(changed: change)
            }
        }
        scheduleFlushToDocument()
    }

    private func recordBatchChange(_ change: SnapshotChange) {
        guard isInBatch else { return }
        pendingBatchChange.formUnion(change)
    }

    private func publishPhrasePerformOverlayChange(phraseID: UUID?) {
        if let phraseID {
            publishSnapshot(changed: .phrase(phraseID))
        } else {
            publishSnapshot(changed: .full)
        }
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
    func batch(
        impact: LiveMutationImpact = .snapshotOnly,
        changed initialChange: SnapshotChange,
        _ body: (LiveSequencerStore) -> Void
    ) -> Bool {
        let revisionBefore = store.revision
        isInBatch = true
        pendingBatchChange = initialChange
        body(store)
        isInBatch = false
        let change = pendingBatchChange
        pendingBatchChange = .none
        guard store.revision != revisionBefore else {
            return false
        }
        dispatchImpact(impact, changed: change)
        return true
    }

    // MARK: - Clip mutations

    /// Mutate a clip in the clip pool by ID, then dispatch impact.
    @discardableResult
    func mutateClip(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout ClipPoolEntry) -> Void) -> Bool {
        let changed = store.mutateClip(id: id, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.clip(id))
            return true
        }
        dispatchImpact(impact, changed: .clip(id))
        return true
    }

    @discardableResult
    func saveRollingCaptureToPatternSlot(
        trackID: UUID,
        slotIndex: Int,
        lengthSteps: Int
    ) -> UUID? {
        guard let content = engineController.capturedClipContent(
            trackID: trackID,
            lengthSteps: lengthSteps
        ) else {
            return nil
        }
        return saveMaterializedClipToPatternSlot(
            trackID: trackID,
            slotIndex: slotIndex,
            content: content,
            name: "Capture P\(slotIndex + 1)"
        )
    }

    @discardableResult
    func saveMaterializedClipToPatternSlot(
        trackID: UUID,
        slotIndex: Int,
        content: ClipContent,
        name: String? = nil
    ) -> UUID? {
        var project = store.exportToProject()
        guard let clipID = project.saveCapturedClip(
            content,
            trackID: trackID,
            destinationSlotIndex: slotIndex,
            name: name
        ) else {
            return nil
        }

        guard store.replaceProject(project) else {
            return clipID
        }
        dispatchImpact(.fullEngineApply, changed: .full)
        return clipID
    }

    // MARK: - Asset pool mutations

    /// Add a global library asset to the project pool. Pool membership is
    /// document state only — no engine impact, no file IO; flows through the
    /// standard flush path so it is undoable like any document mutation.
    @discardableResult
    func addAssetToPool(kind: PooledAssetKind, assetID: UUID) -> Bool {
        let changed = store.addPooledAsset(PooledAssetRef(kind: kind, assetID: assetID))
        guard changed else { return false }
        revision = store.revision
        scheduleFlushToDocument()
        return true
    }

    /// Remove a pooled reference (never deletes the global asset).
    @discardableResult
    func removeAssetFromPool(kind: PooledAssetKind, assetID: UUID) -> Bool {
        let changed = store.removePooledAsset(kind: kind, assetID: assetID)
        guard changed else { return false }
        revision = store.revision
        scheduleFlushToDocument()
        return true
    }

    func isAssetPooled(kind: PooledAssetKind, assetID: UUID) -> Bool {
        store.assetPool.contains { $0.kind == kind && $0.assetID == assetID }
    }

    // MARK: - Track mutations

    /// Mutate a track by ID, then dispatch impact.
    @discardableResult
    func mutateTrack(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout StepSequenceTrack) -> Void) -> Bool {
        let changed = store.mutateTrack(id: id, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.track(id))
            return true
        }
        dispatchImpact(impact, changed: .track(id))
        return true
    }

    /// Mutate a track's FX insert chain in place, normalise it, then dispatch
    /// the scoped runtime update carrying the resulting chain (no full
    /// document-model rebuild — Performance-Time Mutation Rule). `.none`
    /// snapshot change: FX inserts do not change compiled note data, so no
    /// note-buffer recompile is needed. Batches defer to the batch record.
    @discardableResult
    func mutateTrackFXInserts(
        trackID: UUID,
        _ update: (inout [TrackFXInsert]) -> Void
    ) -> Bool {
        var resultingInserts: [TrackFXInsert] = []
        let changed = store.mutateTrack(id: trackID) { track in
            update(&track.fxInserts)
            track.fxInserts = TrackFXInsert.normalizedChain(track.fxInserts)
            resultingInserts = track.fxInserts
        }
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.track(trackID))
            return true
        }
        dispatchImpact(
            .scopedRuntime(update: .trackInserts(trackID: trackID, inserts: resultingInserts)),
            changed: .none
        )
        return true
    }

    @discardableResult
    func setTrackNoteRepeatInterval(_ interval: NoteRepeatInterval, trackID: UUID) -> Bool {
        mutateTrack(id: trackID) { track in
            track.noteRepeatInterval = interval
        }
    }

    func isNoteRepeatAvailable(trackID: UUID) -> Bool {
        guard store.tracks.contains(where: { $0.id == trackID }) else {
            return false
        }

        let pattern = store.selectedPattern(for: trackID)
        guard pattern.sourceRef.mode == .clip else {
            return false
        }

        return store.clipEntry(id: pattern.sourceRef.clipID) != nil
    }

    @discardableResult
    func engageNoteRepeat(trackID: UUID) -> Bool {
        guard isNoteRepeatAvailable(trackID: trackID) else {
            engineController.releaseNoteRepeat(trackID: trackID)
            return false
        }

        engineController.engageNoteRepeat(trackID: trackID)
        return true
    }

    func releaseNoteRepeat(trackID: UUID) {
        engineController.releaseNoteRepeat(trackID: trackID)
    }

    // MARK: - Generator mutations

    /// Mutate a generator pool entry by ID, then dispatch impact.
    @discardableResult
    func mutateGenerator(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout GeneratorPoolEntry) -> Void) -> Bool {
        let changed = store.mutateGenerator(id: id, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.generator(id))
            return true
        }
        dispatchImpact(impact, changed: .generator(id))
        return true
    }

    // MARK: - Slice set mutations

    @discardableResult
    func mutateSliceSet(
        id: UUID,
        sampleLengthFrames: Int64,
        impact: LiveMutationImpact = .snapshotOnly,
        _ update: (inout SliceSet) -> Void
    ) -> Bool {
        let changed = store.mutateSliceSet(id: id) { sliceSet in
            update(&sliceSet)
            sliceSet.normalize(sampleLengthFrames: sampleLengthFrames)
        }
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.sliceSet(id))
            return true
        }
        dispatchImpact(impact, changed: .sliceSet(id))
        return true
    }

    func setSlicerDestination(sliceSet: SliceSet, settings: SlicerSettings, for trackID: UUID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            s.appendSliceSet(sliceSet)
            var p = s.exportToProject()
            p.addSliceSet(sliceSet)
            p.setDestinationWithMacros(
                .slicer(sliceSetID: sliceSet.id, settings: settings.clamped),
                for: trackID
            )
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, trackGroups: true, clips: true)
        }
    }

    func setSlicerSettings(_ settings: SlicerSettings, for trackID: UUID) {
        guard case let .slicer(sliceSetID, _) = store.resolvedDestination(for: trackID) else {
            return
        }
        setEditedDestination(.slicer(sliceSetID: sliceSetID, settings: settings.clamped), for: trackID)
    }

    // MARK: - Step Order map mutations

    var stepOrderPendingToggle: StepOrderPendingToggleRequest? {
        engineController.stepOrderPendingToggle
    }

    func stepOrderToggleState(phraseID: UUID) -> StepOrderToggleState {
        if let pending = engineController.stepOrderPendingToggle,
           pending.phraseID == phraseID {
            return pending.requestedEnabled ? .pendingOn : .pendingOff
        }

        guard let phrase = store.phrases.first(where: { $0.id == phraseID }),
              let assignment = phrase.stepOrderAssignment,
              phrase.stepCount == StepOrderMap.stepCount,
              let map = store.stepOrderMaps.first(where: { $0.id == assignment.mapID }),
              map.isValid
        else {
            return .unavailable
        }

        return assignment.isEnabled ? .on : .off
    }

    private func enabledStepOrderMapValues(phraseID: UUID) -> [UInt8]? {
        guard let phrase = store.phrases.first(where: { $0.id == phraseID }),
              let assignment = phrase.stepOrderAssignment,
              phrase.stepCount == StepOrderMap.stepCount,
              let map = store.stepOrderMaps.first(where: { $0.id == assignment.mapID })
        else {
            return nil
        }
        return map.validatedCompiledValues
    }

    private func reconcilePendingStepOrderToggle() {
        guard let pending = engineController.stepOrderPendingToggle else {
            return
        }

        guard let mapValues = enabledStepOrderMapValues(phraseID: pending.phraseID) else {
            engineController.clearPendingStepOrderToggle(phraseID: pending.phraseID)
            return
        }

        if pending.requestedEnabled {
            engineController.refreshPendingStepOrderEnabledMapValues(
                phraseID: pending.phraseID,
                enabledMapValues: mapValues
            )
        }
    }

    @discardableResult
    func requestPhraseStepOrderEnabled(_ enabled: Bool, phraseID: UUID) -> Bool {
        guard enabledStepOrderMapValues(phraseID: phraseID) != nil else {
            engineController.clearPendingStepOrderToggle(phraseID: phraseID)
            return false
        }

        if engineController.isRunning {
            let mapValues = enabled ? enabledStepOrderMapValues(phraseID: phraseID) : nil
            return engineController.requestStepOrderEnabled(
                enabled,
                phraseID: phraseID,
                enabledMapValues: mapValues
            )
        }

        engineController.clearPendingStepOrderToggle(phraseID: phraseID)
        return setPhraseStepOrderEnabled(enabled, phraseID: phraseID)
    }

    func applyResolvedStepOrderToggle(_ request: StepOrderPendingToggleRequest) {
        let changed = store.mutatePhrase(id: request.phraseID) { phrase in
            guard var assignment = phrase.stepOrderAssignment else {
                return
            }
            assignment.isEnabled = request.requestedEnabled
            phrase.stepOrderAssignment = assignment
        }
        guard changed else {
            return
        }
        revision = store.revision
        snapshotPublisher.replace(engineController.currentPlaybackSnapshotForTesting)
        scheduleFlushToDocument()
    }

    @discardableResult
    func appendStepOrderMap(_ map: StepOrderMap) -> Bool {
        let changed = store.appendStepOrderMap(map)
        guard changed else { return false }
        if isInBatch {
            return true
        }
        dispatchImpact(.snapshotOnly, changed: .none)
        return true
    }

    @discardableResult
    func mutateStepOrderMap(
        id: StepOrderMapID,
        changed change: SnapshotChange = .none,
        _ update: (inout StepOrderMap) -> Void
    ) -> Bool {
        let changed = store.mutateStepOrderMap(id: id, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(change)
            return true
        }
        dispatchImpact(.snapshotOnly, changed: change)
        return true
    }

    @discardableResult
    func renameStepOrderMap(id: StepOrderMapID, name: String) -> Bool {
        mutateStepOrderMap(id: id) { map in
            map = map.renamed(name)
        }
    }

    @discardableResult
    func setStepOrderMapValues(id: StepOrderMapID, values: [UInt8]) -> Bool {
        let changed = mutateStepOrderMap(id: id, changed: .stepOrderMap(id)) { map in
            map = map.withValues(values)
        }
        if changed {
            reconcilePendingStepOrderToggle()
        }
        return changed
    }

    func stepOrderMapDeletionStatus(id: StepOrderMapID) -> StepOrderMapDeletionStatus {
        store.stepOrderMapDeletionStatus(id: id)
    }

    @discardableResult
    func deleteUnusedStepOrderMap(id: StepOrderMapID) -> Bool {
        let changed = store.deleteUnusedStepOrderMap(id: id)
        guard changed else { return false }
        reconcilePendingStepOrderToggle()
        if isInBatch {
            return true
        }
        dispatchImpact(.snapshotOnly, changed: .none)
        return true
    }

    func applySlicerAnalysis(
        sliceSet: SliceSet,
        sampleLengthFrames: Int64,
        clipLengthSteps: Int,
        for trackID: UUID
    ) {
        let resolvedStepCount = max(1, clipLengthSteps)
        batch(impact: .snapshotOnly, changed: .sliceSet(sliceSet.id).union(.patternBank(trackID))) { s in
            var normalizedSliceSet = sliceSet
            normalizedSliceSet.normalize(sampleLengthFrames: sampleLengthFrames)
            if s.sliceSet(id: normalizedSliceSet.id) == nil {
                s.appendSliceSet(normalizedSliceSet)
            } else {
                s.mutateSliceSet(id: normalizedSliceSet.id) { current in
                    current = normalizedSliceSet
                }
            }
            recordBatchChange(.sliceSet(normalizedSliceSet.id))

            var p = s.exportToProject()
            guard let clipID = p.ensureClipForCurrentPattern(trackID: trackID) else {
                return
            }

            let liveClipIDs = Set(s.clipPool.map(\.id))
            for clip in p.clipPool where !liveClipIDs.contains(clip.id) {
                s.appendClip(clip)
                recordBatchChange(.clip(clip.id))
            }
            for bank in p.patternBanks {
                s.setPatternBank(trackID: bank.trackID, bank: bank)
            }
            recordBatchChange(.patternBank(trackID))

            s.mutateClip(id: clipID) { entry in
                entry.content = Self.sliceTriggerContent(
                    userSliceCount: normalizedSliceSet.userSliceCount,
                    stepCount: resolvedStepCount
                )
                entry.macroLanes = entry.macroLanes.mapValues { $0.synced(stepCount: resolvedStepCount) }
            }
            recordBatchChange(.clip(clipID))
        }
    }

    private static func sliceTriggerContent(userSliceCount: Int, stepCount: Int) -> ClipContent {
        let resolvedStepCount = max(1, stepCount)
        guard userSliceCount > 0 else {
            return .emptySliceTriggers(lengthSteps: resolvedStepCount)
        }

        var pattern = Array(repeating: false, count: resolvedStepCount)
        var indexes = Array(repeating: 1, count: resolvedStepCount)
        let sliceCount = max(1, userSliceCount)
        for sliceOffset in 0..<sliceCount {
            let ratio = Double(sliceOffset) / Double(sliceCount)
            let step = min(resolvedStepCount - 1, Int((ratio * Double(resolvedStepCount)).rounded(.down)))
            pattern[step] = true
            indexes[step] = sliceOffset + 1
        }

        return .sliceTriggers(
            stepPattern: pattern,
            sliceIndexes: indexes,
            stepModes: Array(repeating: .single, count: resolvedStepCount),
            stepParameters: Array(repeating: .default, count: resolvedStepCount)
        )
    }

    // MARK: - Master bus mutations

    @discardableResult
    func mutateMasterBus(_ update: (inout MasterBusState) -> Void) -> Bool {
        let changed = store.mutateMasterBus(update)
        guard changed else { return false }
        let masterBus = store.masterBus
        if isInBatch {
            recordBatchChange(.none)
            return true
        }
        dispatchImpact(.scopedRuntime(update: .masterBus(masterBus)), changed: .none)
        return true
    }

    func setActiveMasterScene(_ sceneID: UUID) {
        mutateMasterBus { masterBus in
            masterBus.setActiveScene(id: sceneID)
        }
    }

    @discardableResult
    func addMasterBusScene(name: String? = nil) -> UUID {
        var createdID = MasterBusScene.cleanID
        mutateMasterBus { masterBus in
            createdID = masterBus.addScene(name: name)
        }
        return createdID
    }

    @discardableResult
    func duplicateMasterBusScene(_ sceneID: UUID) -> UUID? {
        var createdID: UUID?
        mutateMasterBus { masterBus in
            createdID = masterBus.addScene(copyFrom: sceneID)
        }
        return createdID
    }

    func removeMasterBusScene(_ sceneID: UUID) {
        mutateMasterBus { masterBus in
            masterBus.removeScene(id: sceneID)
        }
    }

    func updateMasterBusScene(_ sceneID: UUID, edit: (inout MasterBusScene) -> Void) {
        mutateMasterBus { masterBus in
            masterBus.updateScene(id: sceneID, edit)
        }
    }

    func setMasterSceneName(_ sceneID: UUID, name: String) {
        updateMasterBusScene(sceneID) { scene in
            scene.name = name
        }
    }

    func addMasterBusInsert(_ insert: MasterBusInsert, to sceneID: UUID? = nil) {
        mutateMasterBus { masterBus in
            masterBus.addInsert(insert, sceneID: sceneID)
        }
    }

    func updateMasterBusInsert(_ insertID: UUID, in sceneID: UUID? = nil, edit: (inout MasterBusInsert) -> Void) {
        mutateMasterBus { masterBus in
            masterBus.updateInsert(id: insertID, sceneID: sceneID, edit)
        }
    }

    func setMasterAUEffectStateBlob(_ insertID: UUID, in sceneID: UUID, stateBlob: Data?) {
        updateMasterBusInsert(insertID, in: sceneID) { insert in
            guard case let .auEffect(componentID, _) = insert.kind else { return }
            insert.kind = .auEffect(componentID: componentID, stateBlob: stateBlob)
        }
    }

    func removeMasterBusInsert(_ insertID: UUID, from sceneID: UUID? = nil) {
        mutateMasterBus { masterBus in
            masterBus.removeInsert(id: insertID, sceneID: sceneID)
        }
    }

    func reorderMasterBusInserts(_ ids: [UUID], in sceneID: UUID? = nil) {
        mutateMasterBus { masterBus in
            masterBus.reorderInserts(ids: ids, sceneID: sceneID)
        }
    }

    func addMasterOutputInsert(_ insert: MasterBusInsert) {
        mutateMasterBus { masterBus in
            masterBus.addMasterInsert(insert)
        }
    }

    func updateMasterOutputInsert(_ insertID: UUID, edit: (inout MasterBusInsert) -> Void) {
        mutateMasterBus { masterBus in
            masterBus.updateMasterInsert(id: insertID, edit)
        }
    }

    func removeMasterOutputInsert(_ insertID: UUID) {
        mutateMasterBus { masterBus in
            masterBus.removeMasterInsert(id: insertID)
        }
    }

    func reorderMasterOutputInserts(_ ids: [UUID]) {
        mutateMasterBus { masterBus in
            masterBus.reorderMasterInserts(ids: ids)
        }
    }

    func upsertMasterSceneMacroBinding(_ binding: MasterSceneMacroBinding, in sceneID: UUID) {
        mutateMasterBus { masterBus in
            masterBus.upsertMacroBinding(binding, sceneID: sceneID)
        }
    }

    func removeMasterSceneMacroBinding(_ bindingID: UUID, from sceneID: UUID) {
        mutateMasterBus { masterBus in
            masterBus.removeMacroBinding(id: bindingID, sceneID: sceneID)
        }
    }

    func setMasterSceneMacroValue(sceneID: UUID, macroID: UUID, value: Double) {
        mutateMasterBus { masterBus in
            masterBus.setMacroValue(sceneID: sceneID, macroID: macroID, value: value)
        }
    }

    func saveMasterScenePerformanceOverrides(_ valuesByMacroID: [UUID: Double], to sceneID: UUID) {
        mutateMasterBus { masterBus in
            for (macroID, value) in valuesByMacroID {
                masterBus.setMacroValue(sceneID: sceneID, macroID: macroID, value: value)
            }
        }
    }

    func setMasterABMode(_ selection: MasterBusABSelection?) {
        mutateMasterBus { masterBus in
            masterBus.setABSelection(selection)
        }
    }

    func setMasterCrossfader(_ value: Double) {
        mutateMasterBus { masterBus in
            masterBus.setCrossfader(value)
        }
    }

    func setMasterOutputGain(_ value: Double) {
        mutateMasterBus { masterBus in
            masterBus.setMasterOutputGain(value)
        }
    }

    // MARK: - Phrase mutations

    /// Mutate a phrase by ID, then dispatch impact.
    @discardableResult
    func mutatePhrase(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout PhraseModel) -> Void) -> Bool {
        let changed = store.mutatePhrase(id: id, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.phrase(id))
            return true
        }
        dispatchImpact(impact, changed: .phrase(id))
        return true
    }

    @discardableResult
    func setPhraseBarCount(_ barCount: Int, phraseID: UUID) -> Bool {
        let changed = mutatePhrase(id: phraseID) { phrase in
            phrase.lengthBars = barCount
        }
        if changed {
            reconcilePendingStepOrderToggle()
        }
        return changed
    }

    @discardableResult
    func setPhraseRepeatCount(_ repeatCount: Int, phraseID: UUID) -> Bool {
        mutatePhrase(id: phraseID) { phrase in
            phrase.repeatCount = repeatCount
        }
    }

    @discardableResult
    func setPhraseLoopEnabled(_ enabled: Bool, phraseID: UUID) -> Bool {
        mutatePhrase(id: phraseID) { phrase in
            phrase.loopEnabled = enabled
        }
    }

    @discardableResult
    func setStepOrderAssignment(
        phraseID: UUID,
        mapID: StepOrderMapID?,
        isEnabled: Bool
    ) -> Bool {
        let changed = mutatePhrase(id: phraseID) { phrase in
            phrase.stepOrderAssignment = mapID.map {
                StepOrderAssignment(mapID: $0, isEnabled: isEnabled)
            }
        }
        if changed {
            reconcilePendingStepOrderToggle()
        }
        return changed
    }

    @discardableResult
    func setPhraseStepOrderEnabled(_ enabled: Bool, phraseID: UUID) -> Bool {
        let changed = mutatePhrase(id: phraseID) { phrase in
            guard var assignment = phrase.stepOrderAssignment else {
                return
            }
            assignment.isEnabled = enabled
            phrase.stepOrderAssignment = assignment
        }
        if changed {
            reconcilePendingStepOrderToggle()
        }
        return changed
    }

    func canSwitchBasisPhrase(to phraseID: UUID) -> Bool {
        !phrasePerformOverlay.blocksBasisSwitch(to: phraseID)
    }

    @discardableResult
    func queuePhrase(_ phraseID: UUID) -> Bool {
        guard canSwitchBasisPhrase(to: phraseID) else {
            return false
        }
        return engineController.queuePhrase(phraseID)
    }

    @discardableResult
    func switchPhraseNow(_ phraseID: UUID) -> Bool {
        guard canSwitchBasisPhrase(to: phraseID) else {
            return false
        }
        return engineController.switchPhraseNow(phraseID)
    }

    // MARK: - Selection

    /// Set the selected track ID, publish a snapshot. Always `.snapshotOnly` —
    /// selection has no audible impact.
    func setSelectedTrackID(_ id: UUID) {
        let selectedTrackBefore = store.selectedTrackID
        if selectedTrackBefore != id {
            clearTrackFillPreview(reason: .selectedTrackChanged)
        }
        store.setSelectedTrackID(id)
        guard store.revision > revision else { return }
        if isInBatch {
            recordBatchChange(.selectedTrack)
            return
        }
        revision = store.revision
        scheduleFlushToDocument()
    }

    /// Set the selected phrase ID, publish a snapshot. Always `.snapshotOnly`.
    func setSelectedPhraseID(_ id: UUID) {
        guard !phrasePerformOverlay.blocksBasisSwitch(to: id) else {
            return
        }
        store.setSelectedPhraseID(id)
        if workspaceMode == .perform {
            _ = phrasePerformOverlay.begin(basisPhraseID: id)
        }
        guard store.revision > revision else { return }
        if isInBatch {
            recordBatchChange(.selectedPhrase)
            return
        }
        dispatchImpact(.snapshotOnly, changed: .selectedPhrase)
    }

    /// Set both selected phrase ID and selected track ID atomically.
    func setSelectedPhraseAndTrackID(phraseID: UUID, trackID: UUID) {
        guard !phrasePerformOverlay.blocksBasisSwitch(to: phraseID) else {
            return
        }
        let selectedPhraseBefore = store.selectedPhraseID
        let selectedTrackBefore = store.selectedTrackID

        if selectedTrackBefore != trackID {
            clearTrackFillPreview(reason: .selectedTrackChanged)
        }
        store.setSelectedPhraseID(phraseID)
        store.setSelectedTrackID(trackID)
        if workspaceMode == .perform {
            _ = phrasePerformOverlay.begin(basisPhraseID: phraseID)
        }

        guard store.revision > revision else {
            return
        }

        var change = SnapshotChange.none
        if selectedPhraseBefore != phraseID {
            change.formUnion(.selectedPhrase)
        }
        if selectedTrackBefore != trackID {
            change.formUnion(.selectedTrack)
        }
        dispatchImpact(.snapshotOnly, changed: change)
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
        let clearedOverlay = phrasePerformOverlay.reconcile(availablePhraseIDs: p.phrases.map(\.id))
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
        if clearedOverlay {
            publishPhrasePerformOverlayChange(phraseID: phraseID)
        }
    }

    // MARK: - Phrase cell content

    func phraseWithPerformOverlay(_ phrase: PhraseModel) -> PhraseModel {
        phrasePerformOverlay.applying(to: phrase)
    }

    func resolvedPhraseSceneState(for phrase: PhraseModel) -> PhraseSceneState {
        let displayedPhrase = phraseWithPerformOverlay(phrase)
        if let sceneState = displayedPhrase.sceneState {
            return sceneState.normalized()
        }

        let masterBus = store.masterBus
        let selection = masterBus.abSelection ?? MasterBusABSelection(
            sceneAID: masterBus.scenes.first?.id ?? MasterBusScene.sceneAID,
            sceneBID: masterBus.scenes.dropFirst().first?.id ?? masterBus.scenes.first?.id ?? MasterBusScene.sceneBID,
            crossfader: masterBus.abSelection?.crossfader ?? 0
        )
        return PhraseSceneState(
            sceneAID: selection.sceneAID,
            sceneBID: selection.sceneBID,
            crossfader: selection.crossfader
        )
    }

    func performOverlayCell(phraseID: UUID, layerID: String, trackID: UUID) -> PhraseCell? {
        phrasePerformOverlay.cell(phraseID: phraseID, layerID: layerID, trackID: trackID)
    }

    func performOverlaySceneState(phraseID: UUID) -> PhraseSceneState? {
        phrasePerformOverlay.stagedSceneState(phraseID: phraseID)
    }

    @discardableResult
    func stagePhrasePerformCell(
        _ cell: PhraseCell,
        layerID: String,
        trackIDs: [UUID],
        basisPhraseID: UUID
    ) -> Bool {
        let changed = phrasePerformOverlay.stage(
            cell,
            basisPhraseID: basisPhraseID,
            layerID: layerID,
            trackIDs: trackIDs
        )
        guard changed else {
            return false
        }
        publishPhrasePerformOverlayChange(phraseID: basisPhraseID)
        return true
    }

    @discardableResult
    func beginPhrasePerformOverlay(basisPhraseID: UUID) -> Bool {
        let changed = phrasePerformOverlay.begin(basisPhraseID: basisPhraseID)
        guard changed else {
            return false
        }
        publishPhrasePerformOverlayChange(phraseID: basisPhraseID)
        return true
    }

    @discardableResult
    func stagePhrasePerformSceneState(
        _ state: PhraseSceneState,
        basisPhraseID: UUID
    ) -> Bool {
        let changed = phrasePerformOverlay.stageSceneState(
            state,
            basisPhraseID: basisPhraseID
        )
        guard changed else {
            return false
        }
        publishPhrasePerformOverlayChange(phraseID: basisPhraseID)
        return true
    }

    @discardableResult
    func savePhrasePerformOverlayBack() -> Bool {
        guard phrasePerformOverlay.isDirty,
              let targetPhraseID = phrasePerformOverlay.basisPhraseID,
              store.phrases.contains(where: { $0.id == targetPhraseID })
        else {
            phrasePerformOverlay.clear()
            publishPhrasePerformOverlayChange(phraseID: nil)
            return false
        }

        let overlay = phrasePerformOverlay
        let tracks = store.tracks
        let layers = store.layers
        let changed = mutatePhrase(id: targetPhraseID) { phrase in
            phrase = overlay.applying(to: phrase).synced(with: tracks, layers: layers)
        }

        phrasePerformOverlay.clear()
        publishPhrasePerformOverlayChange(phraseID: targetPhraseID)
        return changed
    }

    @discardableResult
    func capturePhrasePerformOverlay(to targetPhraseID: UUID) -> Bool {
        guard let basisPhraseID = phrasePerformOverlay.basisPhraseID,
              let basisPhrase = store.phrases.first(where: { $0.id == basisPhraseID }),
              let targetIndex = store.phrases.firstIndex(where: { $0.id == targetPhraseID })
        else {
            return false
        }

        var phrases = store.phrases
        let targetPhrase = phrases[targetIndex]
        var capturedPhrase = phrasePerformOverlay.applying(to: basisPhrase)
        capturedPhrase.id = targetPhrase.id
        capturedPhrase.name = targetPhrase.name
        phrases[targetIndex] = capturedPhrase.synced(with: store.tracks, layers: store.layers)
        store.replacePhrases(phrases, selectedPhraseID: targetPhrase.id)
        phrasePerformOverlay.clear()
        dispatchImpact(.snapshotOnly, changed: .phrase(targetPhrase.id))
        return true
    }

    @discardableResult
    func capturePhrasePerformOverlayToNewPhrase() -> UUID? {
        guard let basisPhraseID = phrasePerformOverlay.basisPhraseID,
              let basisPhrase = store.phrases.first(where: { $0.id == basisPhraseID })
        else {
            return nil
        }

        var project = store.exportToProject()
        project.insertPhrase(below: basisPhraseID)
        guard let newIndex = project.phrases.firstIndex(where: { $0.id == project.selectedPhraseID }) else {
            return nil
        }

        let newPhraseShell = project.phrases[newIndex]
        var capturedPhrase = phrasePerformOverlay.applying(to: basisPhrase)
        capturedPhrase.id = newPhraseShell.id
        capturedPhrase.name = newPhraseShell.name
        project.phrases[newIndex] = capturedPhrase.synced(with: project.tracks, layers: project.layers)
        store.replacePhrases(project.phrases, selectedPhraseID: capturedPhrase.id)
        phrasePerformOverlay.clear()
        dispatchImpact(.snapshotOnly, changed: .full)
        return capturedPhrase.id
    }

    func revertPhrasePerformOverlay() {
        let phraseID = phrasePerformOverlay.basisPhraseID
        phrasePerformOverlay.clear()
        publishPhrasePerformOverlayChange(phraseID: phraseID)
    }

    /// Set a phrase cell for the given layer and track IDs. Publishes one snapshot.
    func setPhraseCell(
        _ cell: PhraseCell,
        layerID: String,
        trackIDs: [UUID],
        phraseID: UUID,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        if workspaceMode == .perform {
            _ = stagePhrasePerformCell(
                cell,
                layerID: layerID,
                trackIDs: trackIDs,
                basisPhraseID: phraseID
            )
            return
        }

        let changed = store.mutatePhrase(id: phraseID) { phrase in
            for trackID in trackIDs {
                phrase.setCell(cell, for: layerID, trackID: trackID)
            }
        }
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.phrase(phraseID))
            return
        }
        dispatchImpact(impact, changed: .phrase(phraseID))
    }

    func setPhraseSceneState(
        _ state: PhraseSceneState,
        phraseID: UUID,
        impact: LiveMutationImpact = .snapshotOnly
    ) {
        let normalizedState = state.normalized()
        if workspaceMode == .perform {
            _ = stagePhrasePerformSceneState(normalizedState, basisPhraseID: phraseID)
            return
        }

        let changed = store.mutatePhrase(id: phraseID) { phrase in
            phrase.sceneState = normalizedState
        }
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.phrase(phraseID))
            return
        }
        dispatchImpact(impact, changed: .phrase(phraseID))
    }

    // MARK: - Pattern bank

    /// Mutate the pattern bank for a given track ID in place, then dispatch impact.
    @discardableResult
    func mutatePatternBank(trackID: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout TrackPatternBank) -> Void) -> Bool {
        let changed = store.mutatePatternBank(trackID: trackID, update)
        guard changed else { return false }
        if isInBatch {
            recordBatchChange(.patternBank(trackID))
            return true
        }
        dispatchImpact(impact, changed: .patternBank(trackID))
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
        let clipsBefore = Set(store.clipPool.map(\.id))
        let changed = batch(impact: impact, changed: .patternBank(trackID)) { s in
            var p = s.exportToProject()
            p.setPatternSourceRef(sourceRef, for: trackID, slotIndex: slotIndex)
            for bank in p.patternBanks {
                s.setPatternBank(trackID: bank.trackID, bank: bank)
            }
            // Sync clip pool if new clips were added (setPatternSourceRef may call ensureClip).
            for clip in p.clipPool where !clipsBefore.contains(clip.id) {
                s.appendClip(clip)
            }
        }
        if changed, trackFillPreviewState.activeTrackID == trackID, !isTrackFillPreviewAvailable(trackID: trackID) {
            clearTrackFillPreview(reason: .sourceBecameUnsupported)
        }
    }

    private func applySelectedSlotSourceMutation(
        trackID: UUID,
        impact: LiveMutationImpact = .snapshotOnly,
        _ update: (inout Project) -> Void
    ) {
        let clipIDsBefore = Set(store.clipPool.map(\.id))
        let generatorIDsBefore = Set(store.generatorPool.map(\.id))
        let changed = batch(impact: impact, changed: .patternBank(trackID)) { s in
            var project = s.exportToProject()
            update(&project)
            for clip in project.clipPool where !clipIDsBefore.contains(clip.id) {
                s.appendClip(clip)
                recordBatchChange(.clip(clip.id))
            }
            for generator in project.generatorPool where !generatorIDsBefore.contains(generator.id) {
                s.appendGenerator(generator)
                recordBatchChange(.generator(generator.id))
            }
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else { return }
            s.setPatternBank(trackID: trackID, bank: bank)
            recordBatchChange(.patternBank(trackID))
        }
        if changed, trackFillPreviewState.activeTrackID == trackID, !isTrackFillPreviewAvailable(trackID: trackID) {
            clearTrackFillPreview(reason: .sourceBecameUnsupported)
        }
    }

    func removeSelectedSlotSource(trackID: UUID, slotIndex: Int) {
        applySelectedSlotSourceMutation(trackID: trackID) { $0.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex) }
    }

    @discardableResult
    func createBlankClipSource(trackID: UUID, slotIndex: Int) -> UUID? {
        var clipID: UUID?
        applySelectedSlotSourceMutation(trackID: trackID) { clipID = $0.createBlankClipSource(trackID: trackID, slotIndex: slotIndex) }
        return clipID
    }

    func assignClipSource(_ clipID: UUID, to trackID: UUID, slotIndex: Int) {
        applySelectedSlotSourceMutation(trackID: trackID) { $0.assignClipSource(clipID, to: trackID, slotIndex: slotIndex) }
    }

    @discardableResult
    func createBlankGeneratorSource(trackID: UUID, slotIndex: Int) -> GeneratorPoolEntry? {
        var generator: GeneratorPoolEntry?
        applySelectedSlotSourceMutation(trackID: trackID) { generator = $0.createBlankGeneratorSource(trackID: trackID, slotIndex: slotIndex) }
        return generator
    }

    func assignGeneratorSource(_ generatorID: UUID, to trackID: UUID, slotIndex: Int) {
        applySelectedSlotSourceMutation(trackID: trackID) { $0.assignGeneratorSource(generatorID, to: trackID, slotIndex: slotIndex) }
    }

    // MARK: - Macro slot assign / remove (canonical typed mutations)

    /// Assign an AU parameter descriptor to a specific macro slot on a track.
    ///
    /// Canonical path for "user picks a parameter for slot N". Owns the full
    /// write-back: tracks, layers, phrases, **and** clip macro lanes so that no
    /// lane data is orphaned.
    func assignAUMacroToSlot(
        _ descriptor: TrackMacroDescriptor,
        to trackID: UUID,
        slotIndex: Int
    ) -> Bool {
        var accepted = false
        batch(impact: .snapshotOnly, changed: .full) { s in
            var p = s.exportToProject()
            accepted = p.addAUMacro(descriptor: descriptor, to: trackID, slotIndex: slotIndex)
            guard accepted else { return }
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p)
            // addAUMacro does not touch clipPool — no clip diff loop needed here.
        }
        return accepted
    }

    /// Remove a macro slot from a track by binding ID.
    ///
    /// Canonical path for "user removes macro slot". Owns the full write-back:
    /// tracks, layers, phrases, **and** clip macro lanes so orphaned lane data
    /// is purged from the clip pool.
    func removeAUMacroSlot(bindingID: UUID, trackID: UUID) {
        batch(impact: .snapshotOnly, changed: .full) { s in
            var p = s.exportToProject()
            p.removeMacro(id: bindingID, from: trackID)
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, clips: true)
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
        batch(impact: .snapshotOnly, changed: .full) { s in
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
                let descriptor = TrackMacroDescriptor(auParameter: param)
                p.addAUMacro(descriptor: descriptor, to: trackID)
            }
            p.syncMacroLayers()
            // Write back all affected fields.
            s.writeBackProjectStructure(from: p, clips: true)
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
        // WS5 routing: a GENERATION-AFFECTING macro changes compiled note
        // data, so its edits must install a snapshot (generation-revision
        // bump → precompute invalidation, the chord-context precedent
        // 4e0ba807). The scoped-runtime fast path below is ONLY for
        // dispatch-time values.
        let bindingIsGenerationAffecting = store.tracks
            .first(where: { $0.id == trackID })?
            .macros.first(where: { $0.id == bindingID })?
            .descriptor.generationAffecting ?? false
        if bindingIsGenerationAffecting {
            dispatchImpact(.snapshotOnly, changed: .layers)
            return
        }
        // Deliberately NOT `.snapshotOnly`/`.layers`: track macros are
        // dispatch-time only (sampler/filter/AU params — never compiled note
        // data), and a snapshot install per drag tick bumps the generation
        // revision, busts the precompute cache, and clears the event queue at
        // mouse-move rate (the same latency class fixed for `setTrackMix`).
        // The engine hears the drag through the scoped-runtime override; the
        // store write above keeps persistence/undo/export correct, and the
        // next structural snapshot install compiles it and clears the
        // override.
        dispatchImpact(
            .scopedRuntime(update: .macroLayerDefault(trackID: trackID, bindingID: bindingID, value: value)),
            changed: .none
        )
    }

    /// Write a phrase-layer default value for one track. Phrases whose cell is
    /// `.inheritDefault` for that layer/track resolve to this value.
    ///
    /// Same project-export round-trip as `setMacroLayerDefault`: layer
    /// defaults are embedded in `storeLayers` and there is no narrower
    /// per-layer typed method on the store.
    func setPhraseLayerDefault(
        _ value: PhraseCellValue,
        layerID: String,
        trackID: UUID
    ) {
        var p = store.exportToProject()
        guard let index = p.layers.firstIndex(where: { $0.id == layerID }) else { return }
        p.layers[index].defaults[trackID] = value.normalized(for: p.layers[index])
        store.setLayers(p.layers)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly, changed: .layers)
    }

    // MARK: - Destination mutations

    /// Set the edited destination for a track, then dispatch `.fullEngineApply`.
    ///
    /// Routes through `Project.setDestinationWithMacros` so that `syncBuiltinMacros`
    /// is always called — ensuring sampler built-ins are installed and AU macros are
    /// dropped on kind transitions. Without this routing, `syncBuiltinMacros` was
    /// unreachable from production code (it was only called from tests directly).
    ///
    /// `.fullEngineApply` is preserved: destination changes require
    /// `apply(documentModel:)` to tear down and rebuild the AU host.
    func setEditedDestination(_ destination: Destination, for trackID: UUID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setDestinationWithMacros(destination, for: trackID)
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, trackGroups: true, clips: true)
        }
    }

    /// Set the MIDI port for a track's destination. `.fullEngineApply` preserved
    /// from original call site: MIDI port change requires engine re-apply.
    func setEditedMIDIPort(_ port: MIDIEndpointName?, for trackID: UUID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setEditedMIDIPort(port, for: trackID)
            s.writeBackProjectStructure(from: p, trackGroups: true)
        }
    }

    /// Set the MIDI channel for a track's destination. `.fullEngineApply` preserved.
    func setEditedMIDIChannel(_ channel: UInt8, for trackID: UUID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setEditedMIDIChannel(channel, for: trackID)
            s.writeBackProjectStructure(from: p, trackGroups: true)
        }
    }

    /// Set the MIDI note offset for a track's destination. `.fullEngineApply` preserved.
    func setEditedMIDINoteOffset(_ noteOffset: Int, for trackID: UUID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setEditedMIDINoteOffset(noteOffset, for: trackID)
            s.writeBackProjectStructure(from: p, trackGroups: true)
        }
    }

    func setDrumGroupSharedDestination(_ destination: Destination?, groupID: TrackGroupID) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setGroupSharedDestinationWithMacros(destination, groupID: groupID)
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, trackGroups: true, clips: true)
        }
    }

    func setDrumGroupMemberInheritsDestination(
        _ inheritsGroupDestination: Bool,
        trackID: UUID,
        ownDestination: Destination = .none
    ) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.setDrumGroupMemberInheritsDestination(
                inheritsGroupDestination,
                trackID: trackID,
                ownDestination: ownDestination
            )
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, trackGroups: true, clips: true)
        }
    }

    func setDrumGroupTriggerMappingMode(_ mode: DrumTriggerMappingMode, groupID: TrackGroupID) {
        let changed = store.mutateTrackGroup(id: groupID) { group in
            group.triggerMappingMode = mode
        }
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.full)
            return
        }
        dispatchImpact(.snapshotOnly, changed: .full)
    }

    func setDrumGroupMemberNoteOffset(_ offset: Int, trackID: UUID) {
        guard let groupID = store.tracks.first(where: { $0.id == trackID })?.groupID else {
            return
        }
        let changed = store.mutateTrackGroup(id: groupID) { group in
            guard group.memberIDs.contains(trackID) else { return }
            group.noteMapping[trackID] = offset
        }
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.full)
            return
        }
        dispatchImpact(.snapshotOnly, changed: .full)
    }

    func setDrumGroupMemberMIDIChannel(_ channel: UInt8, trackID: UUID) {
        guard let groupID = store.tracks.first(where: { $0.id == trackID })?.groupID else {
            return
        }
        let changed = store.mutateTrackGroup(id: groupID) { group in
            guard group.memberIDs.contains(trackID) else { return }
            group.channelMapping[trackID] = min(channel, 15)
        }
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.full)
            return
        }
        dispatchImpact(.snapshotOnly, changed: .full)
    }

    func applyDrumGroupRoutingDraft(_ draft: Project.DrumGroupRoutingDraft) {
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.applyDrumGroupRoutingDraft(draft)
            p.syncMacroLayers()
            s.writeBackProjectStructure(from: p, trackGroups: true, clips: true)
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

        batch(
            impact: .scopedRuntime(update: .auState(trackID: runtimeTrackID, blob: stateBlob)),
            changed: .track(runtimeTrackID)
        ) { s in
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
        if isInBatch {
            recordBatchChange(.track(trackID))
            return
        }
        dispatchImpact(
            .scopedRuntime(update: .filter(trackID: trackID, settings: settings)),
            changed: .track(trackID)
        )
    }

    // MARK: - Mute / velocity / gate (track property helpers)

    /// Toggle mute for a track, dispatching `.fullEngineApply`.
    ///
    /// `.fullEngineApply` preserved from original call sites: mute affects the
    /// engine's active-voice state which requires a document-model rebuild.
    func toggleTrackMute(trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix.isMuted.toggle()
            // #60: mute and solo are mutually exclusive per track. The
            // just-engaged control wins: engaging mute drops the track from
            // solo so the two indicators never both show active.
            if track.mix.isMuted { track.mix.isSoloed = false }
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.fullEngineApply)
    }

    /// Set mute state for a track, dispatching `.fullEngineApply`.
    func setTrackMuted(_ muted: Bool, trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix.isMuted = muted
            // #60: engaging mute drops the track from solo (mutually exclusive).
            if muted { track.mix.isSoloed = false }
        }
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.fullEngineApply)
    }

    func setSelectedPatternIndex(_ index: Int, for trackID: UUID) {
        var p = store.exportToProject()
        p.setSelectedPatternIndex(index, for: trackID)
        store.replacePhrases(p.phrases, selectedPhraseID: p.selectedPhraseID)
        guard store.revision > revision else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly, changed: .phrase(p.selectedPhraseID))
    }

    /// Update a generator entry by ID and dispatch impact, using a project round-trip
    func updateGeneratorEntry(id: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (inout GeneratorPoolEntry) -> Void) {
        let changed = store.mutateGenerator(id: id, update)
        guard changed else { return }
        if isInBatch {
            recordBatchChange(.generator(id))
            return
        }
        dispatchImpact(impact, changed: .generator(id))
    }

    @discardableResult
    func ensureClipAndMutate(trackID: UUID, impact: LiveMutationImpact = .snapshotOnly, _ update: (UUID, inout ClipPoolEntry) -> Void) -> UUID? {
        ensureClipAndMutate(
            at: PatternSlotAddress(trackID: trackID, slotIndex: store.selectedPatternIndex(for: trackID)),
            impact: impact,
            update
        )
    }

    // MARK: - Track add / remove

    var canAppendAudioInputTrack: Bool {
        !store.tracks.contains { $0.trackType == .audioInput }
    }

    /// Append a new track of the given type.
    ///
    /// Uses a project round-trip because `appendTrack` also creates an owned clip,
    /// a pattern bank, and calls `syncPhrasesWithTracks` — all of which are inter-
    /// dependent and not individually decomposed into store typed methods yet.
    func appendTrack(trackType: TrackType = .monoMelodic) {
        if trackType == .audioInput, !canAppendAudioInputTrack {
            return
        }

        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.appendTrack(trackType: trackType)
            s.importFromProject(p)
        }
    }

    @discardableResult
    func appendSliceTrack(sample: AudioSample) -> UUID? {
        var createdTrackID: UUID?
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            createdTrackID = p.appendSliceTrack(sample: sample)
            s.importFromProject(p)
        }
        return createdTrackID
    }

    /// Append a new track and give it a sound destination in one user gesture
    /// (Create Track flow's mono/poly sound step, Library "create track from AU
    /// instrument"). Composition of the two existing mutations — `appendTrack`
    /// then `setEditedDestination` — so the destination change keeps its
    /// `.fullEngineApply` AU host teardown/build path. Returns the new track's
    /// id, or nil when the append was refused.
    @discardableResult
    func appendTrack(trackType: TrackType, soundDestination: Destination) -> UUID? {
        let idsBefore = Set(store.tracks.map(\.id))
        appendTrack(trackType: trackType)
        let newTrackID = store.selectedTrackID
        guard !idsBefore.contains(newTrackID) else { return nil }
        setEditedDestination(soundDestination, for: newTrackID)
        return newTrackID
    }

    /// The ONE "create a track that plays an AU instrument" composition:
    /// append the track with the `.auInstrument` destination (keeping the
    /// `.fullEngineApply` AU host teardown/build path) AND prime the AU host
    /// for the new track. Every entry point (Create Track flow, Library page,
    /// future surfaces) must call this seam — composing the two steps
    /// independently lets a new entry point silently omit the
    /// `prepareAudioUnit` prime. Returns the new track's id, or nil when the
    /// append was refused.
    @discardableResult
    func appendTrack(
        trackType: TrackType,
        auInstrument choice: AudioInstrumentChoice,
        preparingAudioUnitWith engineController: EngineController
    ) -> UUID? {
        let newTrackID = appendTrack(
            trackType: trackType,
            soundDestination: .auInstrument(componentID: choice.audioComponentID, stateBlob: nil)
        )
        if let newTrackID {
            engineController.prepareAudioUnit(for: newTrackID)
        }
        return newTrackID
    }

    /// Append a new track of the generator's track type and assign the
    /// generator as its slot-0 source (Library "create track from generator").
    /// Reuses `appendTrack` + `assignGeneratorSource` verbatim. Returns the new
    /// track's id, or nil when the append was refused.
    @discardableResult
    func appendTrack(generator: GeneratorPoolEntry) -> UUID? {
        let idsBefore = Set(store.tracks.map(\.id))
        appendTrack(trackType: generator.trackType)
        let newTrackID = store.selectedTrackID
        guard !idsBefore.contains(newTrackID) else { return nil }
        assignGeneratorSource(generator.id, to: newTrackID, slotIndex: 0)
        return newTrackID
    }

    /// Remove the currently selected track (guard: must have >1 track).
    ///
    /// Uses a project round-trip for the same reasons as `appendTrack`.
    func removeSelectedTrack() {
        let removedTrackID = store.selectedTrackID
        clearTrackFillPreviewIfActiveTrack(removedTrackID, reason: .selectedTrackDeleted)
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.removeSelectedTrack()
            s.importFromProject(p)
        }
    }

    /// Remove a specific track by id (detail-page delete affordance). Uses the
    /// same project round-trip as `removeSelectedTrack`; the project guard keeps
    /// at least one track in the document.
    func removeTrack(id: UUID) {
        clearTrackFillPreviewIfActiveTrack(id, reason: .selectedTrackDeleted)
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.removeTrack(id: id)
            s.importFromProject(p)
        }
    }

    /// Remove a set of tracks by id (tracks-page selection action). Clears the
    /// transient tracks selection afterwards so the navigator returns cleanly.
    func removeTracks(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            clearTrackFillPreviewIfActiveTrack(id, reason: .selectedTrackDeleted)
        }
        let orderedIDs = store.tracks.map(\.id).filter { ids.contains($0) }
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            p.removeTracks(ids: orderedIDs)
            s.importFromProject(p)
        }
        tracksSelection.removeAll()
    }

    @discardableResult
    func setPerformanceTrackGroup(slotIndex: Int, memberIDs: Set<UUID>) -> PerformanceTrackGroup? {
        guard !memberIDs.isEmpty else { return nil }
        var created: PerformanceTrackGroup?
        batch(impact: .snapshotOnly, changed: .none) { store in
            var project = store.exportToProject()
            created = project.setPerformanceTrackGroup(slotIndex: slotIndex, memberIDs: memberIDs)
            store.replacePerformanceTrackGroups(project.performanceTrackGroups)
        }
        return created
    }

    func clearPerformanceTrackGroup(slotIndex: Int) {
        batch(impact: .snapshotOnly, changed: .none) { store in
            var project = store.exportToProject()
            project.clearPerformanceTrackGroup(slotIndex: slotIndex)
            store.replacePerformanceTrackGroups(project.performanceTrackGroups)
        }
    }

    /// Duplicate selected navigator tracks. Track copy/paste is a document
    /// mutation, so it uses the same project round-trip as append/remove.
    @discardableResult
    func duplicateTracks(ids: Set<UUID>) -> [UUID] {
        guard !ids.isEmpty else { return [] }
        let orderedIDs = store.tracks.map(\.id).filter { ids.contains($0) }
        var createdIDs: [UUID] = []
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            createdIDs = p.duplicateTracks(ids: orderedIDs)
            s.importFromProject(p)
        }
        tracksSelection = Set(createdIDs)
        tracksSelectionMode = !createdIDs.isEmpty
        return createdIDs
    }

    @discardableResult
    func armAudioInputTrack(
        trackID: UUID,
        quantize: EngineController.AudioInputRecordQuantize = .bar
    ) -> Bool {
        engineController.armAudioInput(trackID: trackID, quantize: quantize)
    }

    @discardableResult
    func setTrackRecordBarLength(_ bars: Int, trackID: UUID) -> Bool {
        let normalized = StepSequenceTrack.normalizedRecordBarLength(bars)
        let changed = mutateTrack(id: trackID) { track in
            track.recordBarLength = normalized
        }
        let accepted = engineController.setAudioInputRecordBarLength(trackID: trackID, bars: normalized)
        return changed || accepted
    }

    @discardableResult
    func cancelAudioInputArm(trackID: UUID) -> Bool {
        engineController.cancelAudioInputArm(trackID: trackID)
    }

    @discardableResult
    func setAudioInputMonitorMode(trackID: UUID, mode: EngineController.AudioInputMonitorMode) -> Bool {
        engineController.setAudioInputMonitorMode(trackID: trackID, mode: mode)
    }

    @discardableResult
    func setAudioInputChannel(trackID: UUID, channel: AudioInputChannel) -> Bool {
        let changed = mutateTrack(id: trackID) { track in
            track.inputChannel = channel
        }
        let accepted = engineController.rerouteAudioInput(trackID: trackID, channel: channel)
        return changed || accepted
    }

    /// Add a drum group using the given plan.
    ///
    /// Uses a project round-trip because `addDrumGroup` creates multiple tracks,
    /// clips, pattern banks, a track group, and syncs phrases — all in one composite
    /// operation.
    @discardableResult
    func addDrumGroup(plan: DrumGroupPlan) -> TrackGroupID? {
        var resultGroupID: TrackGroupID?
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            resultGroupID = p.addDrumGroup(plan: plan)
            s.importFromProject(p)
        }
        return resultGroupID
    }

    /// Add a single sample-backed part (member track) to an existing drum group
    /// while the engine may be playing.
    ///
    /// The new part reuses the `.sample(...)` destination of an existing resident
    /// member track (`sampleSourceTrackID`) so it makes SOUND immediately without
    /// minting a new sample asset at runtime — the same working render path the
    /// fixture uses. It is armed with a basic pattern so a sounding voice is
    /// present during the structural edit.
    ///
    /// Routes through the standard `.fullEngineApply` structural path (the same
    /// path drum-group add/remove and track add/remove use). This is the path the
    /// routing-stress rig exercises to prove drum-part add/remove is live-safe.
    @discardableResult
    func addDrumPart(groupID: TrackGroupID, sampleSourceTrackID: UUID) -> UUID? {
        var createdTrackID: UUID?
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            guard p.trackGroups.contains(where: { $0.id == groupID }),
                  let source = p.tracks.first(where: { $0.id == sampleSourceTrackID }),
                  case .sample = source.destination
            else { return }
            // Append a real track (gets clip / pattern-bank / phrase bookkeeping),
            // then re-point it at the source's sample destination and arm it.
            p.appendTrack(trackType: .monoMelodic)
            let newTrackID = p.selectedTrackID
            let armedPattern = Self.everyNthDrumPartStep(every: 4, count: 16)
            if let index = p.tracks.firstIndex(where: { $0.id == newTrackID }) {
                p.tracks[index].name = "Added Part \(p.tracks.count)"
                p.tracks[index].destination = source.destination
                p.tracks[index].stepPattern = armedPattern
            }
            // Seed the new part's owned clip so it actually TRIGGERS during
            // playback — the snapshot compiler reads clip CONTENT, not the
            // track's `stepPattern` (matching `appendSliceTrack`/`addDrumGroup`).
            if let clipID = p.patternBank(for: newTrackID).slot(at: 0).sourceRef.clipID {
                p.updateClipEntry(id: clipID) { clip in
                    clip.content = .stepSequence(stepPattern: armedPattern, pitches: [60])
                }
            }
            p.addToGroup(trackID: newTrackID, groupID: groupID)
            s.importFromProject(p)
            createdTrackID = newTrackID
        }
        return createdTrackID
    }

    /// Add the first/default part to a drum group that may currently be empty.
    /// This keeps the stress-test-oriented `addDrumPart(groupID:sampleSourceTrackID:)`
    /// strict while giving the UI a real empty-kit affordance.
    @discardableResult
    func addDefaultDrumPart(groupID: TrackGroupID) -> UUID? {
        var createdTrackID: UUID?
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            createdTrackID = p.addDrumPart(groupID: groupID)
            s.importFromProject(p)
        }
        return createdTrackID
    }

    /// Remove the member at `memberIndex` from an existing drum group while the
    /// engine may be playing. Removes the underlying member track from the
    /// document (which cascades the group membership cleanup) through the standard
    /// `.fullEngineApply` structural path.
    @discardableResult
    func removeDrumPart(groupID: TrackGroupID, memberIndex: Int) -> Bool {
        var removed = false
        batch(impact: .fullEngineApply, changed: .full) { s in
            var p = s.exportToProject()
            guard let group = p.trackGroups.first(where: { $0.id == groupID }),
                  group.memberIDs.indices.contains(memberIndex)
            else { return }
            let memberID = group.memberIDs[memberIndex]
            p.removeTrack(id: memberID)
            s.importFromProject(p)
            removed = true
        }
        return removed
    }

    private static func everyNthDrumPartStep(every: Int, count: Int) -> [Bool] {
        (0..<count).map { every > 0 && $0 % every == 0 }
    }

    // MARK: - Route mutations

    /// Returns a default route originating from the given track.
    ///
    /// Pure read helper — no side-effects, no impact dispatch.
    func makeDefaultRoute(from trackID: UUID) -> Route {
        store.makeDefaultRoute(from: trackID)
    }

    /// Upsert a route rule (insert or replace by ID).
    func upsertRoute(_ route: Route) {
        let changed = store.upsertRoute(route)
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }

    /// Remove a route rule by ID.
    func removeRoute(id: UUID) {
        let changed = store.removeRoute(id: id)
        guard changed else { return }
        guard !isInBatch else { return }
        dispatchImpact(.snapshotOnly)
    }
}

private extension LiveSequencerStore {
    /// Apply the standard Project-side structural cascade back into the resident
    /// store. This keeps callers from re-encoding which sub-collections a Project
    /// helper may have touched.
    func writeBackProjectStructure(
        from project: Project,
        trackGroups: Bool = false,
        clips: Bool = false
    ) {
        replaceTracks(project.tracks)
        replacePerformanceTrackGroups(project.performanceTrackGroups)
        if trackGroups {
            replaceTrackGroups(project.trackGroups)
        }
        setLayers(project.layers)
        replacePhrases(project.phrases, selectedPhraseID: project.selectedPhraseID)
        if clips {
            writeBackChangedClips(from: project)
        }
    }

    /// Write back any clips in `project` that differ from the live clip pool.
    /// Used after `Project`-side helpers (e.g. `removeMacro`, `setDestinationWithMacros`)
    /// that may mutate `clipPool[].macroLanes` so the cascade reaches the store.
    func writeBackChangedClips(from project: Project) {
        let liveByID = Dictionary(uniqueKeysWithValues: clipPool.map { ($0.id, $0) })
        for clip in project.clipPool where liveByID[clip.id] != clip {
            _ = mutateClip(id: clip.id) { $0 = clip }
        }
    }
}
