import Foundation

enum SequencerSnapshotCompiler {
    static func compile(project: Project) -> PlaybackSnapshot {
        compile(
            selectedPhraseID: project.selectedPhraseID,
            tracks: project.tracks,
            clips: project.clipPool,
            generators: project.generatorPool,
            layers: project.layers,
            phrases: project.phrases,
            patternBankForTrackID: { project.patternBank(for: $0) }
        )
    }

    @MainActor
    static func compile(store: LiveSequencerStore) -> PlaybackSnapshot {
        compile(
            selectedPhraseID: store.selectedPhraseID,
            tracks: store.tracks,
            clips: store.clipPool,
            generators: store.generatorPool,
            layers: store.layers,
            phrases: store.phrases,
            patternBankForTrackID: { store.patternBank(for: $0) }
        )
    }

    private static func compile(
        selectedPhraseID: UUID,
        tracks: [StepSequenceTrack],
        clips: [ClipPoolEntry],
        generators: [GeneratorPoolEntry],
        layers: [PhraseLayerDefinition],
        phrases: [PhraseModel],
        patternBankForTrackID: (UUID) -> TrackPatternBank
    ) -> PlaybackSnapshot {
        let trackOrder = tracks.map(\.id)
        let trackOrdinalByID = Dictionary(uniqueKeysWithValues: trackOrder.enumerated().map { ($0.element, $0.offset) })
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let generatorsByID = Dictionary(uniqueKeysWithValues: generators.map { ($0.id, $0) })
        let clipBuffersByID = Dictionary(uniqueKeysWithValues: clips.map { clip in
            let buffer = compileClipBuffer(clip)
            return (clip.id, buffer)
        })
        let trackProgramsByTrackID = Dictionary(uniqueKeysWithValues: tracks.map { track in
            let bank = patternBankForTrackID(track.id)
            let program = compileTrackProgram(track: track, bank: bank)
            return (track.id, program)
        })
        let phraseBuffersByID = Dictionary(uniqueKeysWithValues: phrases.map { phrase in
            let buffer = compilePhraseBuffer(
                phrase: phrase,
                tracks: tracks,
                layers: layers,
                selectedPatternForTrackID: { trackID in
                    patternBankForTrackID(trackID)
                }
            )
            return (phrase.id, buffer)
        })

        return PlaybackSnapshot(
            selectedPhraseID: selectedPhraseID,
            trackOrder: trackOrder,
            trackOrdinalByID: trackOrdinalByID,
            tracksByID: tracksByID,
            clipsByID: clipsByID,
            clipBuffersByID: clipBuffersByID,
            trackProgramsByTrackID: trackProgramsByTrackID,
            phraseBuffersByID: phraseBuffersByID,
            generatorsByID: generatorsByID
        )
    }

    private static func compileTrackProgram(track: StepSequenceTrack, bank: TrackPatternBank) -> TrackSourceProgram {
        let slotPrograms = (0..<TrackPatternBank.slotCount).map { slotIndex -> SlotProgram in
            let slot = bank.slot(at: slotIndex)
            switch slot.sourceRef.mode {
            case .clip:
                guard let clipID = slot.sourceRef.clipID else {
                    return .empty
                }
                return .clip(
                    clipID: clipID,
                    modifierGeneratorID: slot.sourceRef.generatorID,
                    modifierBypassed: true
                )
            case .generator:
                guard let generatorID = slot.sourceRef.generatorID else {
                    return .empty
                }
                return .generator(
                    generatorID: generatorID,
                    modifierGeneratorID: nil,
                    modifierBypassed: false
                )
            }
        }

        return TrackSourceProgram(
            trackID: track.id,
            generatorBlockID: "gen-\(track.id.uuidString.lowercased())",
            slotPrograms: slotPrograms,
            macroBindingIDs: track.macros.map(\.id)
        )
    }

    private static func compileClipBuffer(_ clip: ClipPoolEntry) -> ClipBuffer {
        let steps = clipSteps(for: clip)
        let macroBindingOrder = clip.macroLanes.keys.sorted { $0.uuidString < $1.uuidString }
        let macroBindingIndexes = Dictionary(uniqueKeysWithValues: macroBindingOrder.enumerated().map { ($0.element, $0.offset) })
        let macroOverrideValues = (0..<max(1, clip.content.stepCount)).map { stepIndex in
            macroBindingOrder.map { bindingID in
                clip.macroLanes[bindingID]?.synced(stepCount: clip.content.stepCount).values[safe: stepIndex] ?? nil
            }
        }

        return ClipBuffer(
            clipID: clip.id,
            trackType: clip.trackType,
            lengthSteps: max(1, clip.content.stepCount),
            steps: steps,
            macroBindingOrder: macroBindingOrder,
            macroBindingIndexes: macroBindingIndexes,
            macroOverrideValues: macroOverrideValues
        )
    }

    private static func clipSteps(for clip: ClipPoolEntry) -> [ClipStepBuffer] {
        switch clip.content {
        case let .stepSequence(stepPattern, pitches):
            let resolvedPitches = pitches.isEmpty ? [60] : pitches
            return (0..<max(1, stepPattern.count)).map { stepIndex in
                guard stepPattern.indices.contains(stepIndex), stepPattern[stepIndex] else {
                    return ClipStepBuffer(main: nil, fill: nil)
                }
                let note = ClipNoteBuffer(
                    pitch: UInt8(clamping: resolvedPitches[stepIndex % resolvedPitches.count]),
                    velocity: 100,
                    lengthSteps: 4
                )
                return ClipStepBuffer(main: ClipLaneBuffer(chance: 1, notes: [note]), fill: nil)
            }

        case let .sliceTriggers(stepPattern, sliceIndexes):
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            return (0..<max(1, stepPattern.count)).map { stepIndex in
                guard stepPattern.indices.contains(stepIndex), stepPattern[stepIndex] else {
                    return ClipStepBuffer(main: nil, fill: nil)
                }
                let note = ClipNoteBuffer(
                    pitch: UInt8(clamping: 60 + resolvedIndexes[stepIndex % resolvedIndexes.count]),
                    velocity: 100,
                    lengthSteps: 4
                )
                return ClipStepBuffer(main: ClipLaneBuffer(chance: 1, notes: [note]), fill: nil)
            }

        case let .pianoRoll(lengthBars, stepsPerBar, notes):
            let stepCount = max(1, lengthBars * stepsPerBar)
            return (0..<stepCount).map { stepIndex in
                let notesAtStep = notes
                    .filter { $0.startStep == stepIndex }
                    .map {
                        ClipNoteBuffer(
                            pitch: UInt8(clamping: $0.pitch),
                            velocity: UInt8(clamping: $0.velocity),
                            lengthSteps: UInt16(clamping: $0.lengthSteps)
                        )
                    }
                guard !notesAtStep.isEmpty else {
                    return ClipStepBuffer(main: nil, fill: nil)
                }
                return ClipStepBuffer(main: ClipLaneBuffer(chance: 1, notes: notesAtStep), fill: nil)
            }
        }
    }

    private static func compilePhraseBuffer(
        phrase: PhraseModel,
        tracks: [StepSequenceTrack],
        layers: [PhraseLayerDefinition],
        selectedPatternForTrackID: (UUID) -> TrackPatternBank
    ) -> PhrasePlaybackBuffer {
        let stepCount = max(1, phrase.stepCount)
        let patternLayer = layers.first(where: { $0.target == .patternIndex })
        let muteLayer = layers.first(where: { $0.target == .mute })
        let fillLayer = layers.first(where: { layer in
            if case let .macroRow(key) = layer.target {
                return key == "fill-flag"
            }
            return false
        })

        let trackStates = tracks.map { track -> TrackPhrasePlaybackBuffer in
            let macroValues = (0..<stepCount).map { stepIndex in
                track.macros.map { binding in
                    let layerID = "macro-\(track.id.uuidString)-\(binding.id.uuidString)"
                    guard let layer = layers.first(where: { $0.id == layerID }) else {
                        return binding.descriptor.defaultValue
                    }
                    let resolved = phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: stepIndex)
                    return scalarDouble(resolved, layer: layer, fallback: binding.descriptor.defaultValue)
                }
            }

            let patternSlotIndex = (0..<stepCount).map { stepIndex -> UInt8 in
                guard let patternLayer else { return 0 }
                let resolved = phrase.resolvedValue(for: patternLayer, trackID: track.id, stepIndex: stepIndex)
                return UInt8(clamping: min(max(patternIndex(from: resolved), 0), selectedPatternForTrackID(track.id).slots.count - 1))
            }
            let mute = (0..<stepCount).map { stepIndex -> Bool in
                guard let muteLayer,
                      case let .bool(isMuted) = phrase.resolvedValue(for: muteLayer, trackID: track.id, stepIndex: stepIndex)
                else {
                    return false
                }
                return isMuted
            }
            let fillEnabled = (0..<stepCount).map { stepIndex -> Bool in
                guard let fillLayer,
                      case let .bool(isEnabled) = phrase.resolvedValue(for: fillLayer, trackID: track.id, stepIndex: stepIndex)
                else {
                    return false
                }
                return isEnabled
            }

            return TrackPhrasePlaybackBuffer(
                patternSlotIndex: patternSlotIndex,
                mute: mute,
                fillEnabled: fillEnabled,
                macroValues: macroValues
            )
        }

        return PhrasePlaybackBuffer(phraseID: phrase.id, stepCount: stepCount, trackStates: trackStates)
    }

    private static func scalarDouble(
        _ value: PhraseCellValue,
        layer: PhraseLayerDefinition,
        fallback: Double
    ) -> Double {
        switch value.normalized(for: layer) {
        case let .scalar(scalar):
            return min(max(scalar, layer.minValue), layer.maxValue)
        case let .bool(boolValue):
            return boolValue ? layer.maxValue : layer.minValue
        case let .index(index):
            return min(max(Double(index), layer.minValue), layer.maxValue)
        }
    }

    private static func patternIndex(from value: PhraseCellValue) -> Int {
        switch value {
        case let .index(index):
            return min(max(index, 0), TrackPatternBank.slotCount - 1)
        case let .scalar(value):
            return min(max(Int(value.rounded()), 0), TrackPatternBank.slotCount - 1)
        case let .bool(isOn):
            return isOn ? 1 : 0
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
