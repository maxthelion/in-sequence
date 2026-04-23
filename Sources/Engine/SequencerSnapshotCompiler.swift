import Foundation

enum SequencerSnapshotCompiler {
    static func compile(project: Project) -> PlaybackSnapshot {
        let trackOrder = project.tracks.map(\.id)
        let clipBuffers = Dictionary(uniqueKeysWithValues: project.clipPool.map { clip in
            (clip.id, compileClipBuffer(for: clip, project: project))
        })
        let trackPrograms = Dictionary(uniqueKeysWithValues: project.tracks.map { track in
            (track.id, compileTrackSourceProgram(for: track, project: project))
        })
        let phraseBuffers = Dictionary(uniqueKeysWithValues: project.phrases.map { phrase in
            (phrase.id, compilePhraseBuffer(for: phrase, project: project, trackPrograms: trackPrograms))
        })

        return PlaybackSnapshot(
            project: project,
            trackOrder: trackOrder,
            clipBuffersByID: clipBuffers,
            trackProgramsByTrackID: trackPrograms,
            phraseBuffersByID: phraseBuffers
        )
    }

    private static func compileClipBuffer(
        for clip: ClipPoolEntry,
        project: Project
    ) -> ClipBuffer {
        let normalized = clip.content.normalized
        let lengthSteps = normalized.stepCount
        let steps: [ClipStepBuffer]
        switch normalized {
        case let .noteGrid(_, clipSteps):
            steps = clipSteps.map(compileStepBuffer)
        case let .sliceTriggers(stepPattern, sliceIndexes):
            let normalizedIndexes = sliceIndexes.isEmpty ? [60] : sliceIndexes.map { 60 + $0 }
            steps = stepPattern.map { isOn in
                guard isOn else {
                    return ClipStepBuffer(main: nil, fill: nil)
                }
                let notes = normalizedIndexes.map {
                    ClipNoteBuffer(pitch: UInt8(min(max($0, 0), 127)), velocity: 100, lengthSteps: 1)
                }
                return ClipStepBuffer(main: ClipLaneBuffer(chance: 1, notes: notes), fill: nil)
            }
        }

        let macroBindingOrder = project.tracks
            .first(where: { $0.trackType == clip.trackType })?
            .macros
            .map(\.id) ?? Array(clip.macroLanes.keys).sorted { $0.uuidString < $1.uuidString }
        let macroOverrideValues = (0..<lengthSteps).map { stepIndex in
            macroBindingOrder.map { bindingID in
                let syncedLane = clip.macroLanes[bindingID]?.synced(stepCount: lengthSteps)
                return syncedLane?.values[safe: stepIndex] ?? nil
            }
        }

        return ClipBuffer(
            clipID: clip.id,
            lengthSteps: lengthSteps,
            steps: steps,
            macroBindingOrder: macroBindingOrder,
            macroOverrideValues: macroOverrideValues
        )
    }

    private static func compileStepBuffer(_ step: ClipStep) -> ClipStepBuffer {
        ClipStepBuffer(
            main: compileLaneBuffer(step.main),
            fill: compileLaneBuffer(step.fill)
        )
    }

    private static func compileLaneBuffer(_ lane: ClipLane?) -> ClipLaneBuffer? {
        guard let lane = lane?.normalized else {
            return nil
        }

        return ClipLaneBuffer(
            chance: lane.chance,
            notes: lane.notes.map {
                ClipNoteBuffer(
                    pitch: UInt8(min(max($0.pitch, 0), 127)),
                    velocity: UInt8(min(max($0.velocity, 1), 127)),
                    lengthSteps: UInt16(min(max($0.lengthSteps, 1), Int(UInt16.max)))
                )
            }
        )
    }

    private static func compileTrackSourceProgram(
        for track: StepSequenceTrack,
        project: Project
    ) -> TrackSourceProgram {
        let bank = project.patternBank(for: track.id)
        let slotPrograms = (0..<TrackPatternBank.slotCount).map { index -> SlotProgram in
            let slot = bank.slot(at: index)
            switch slot.sourceRef.mode {
            case .clip:
                guard let clipID = slot.sourceRef.clipID else {
                    return .empty
                }
                return .clip(
                    clipID: clipID,
                    modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                    modifierBypassed: slot.sourceRef.modifierBypassed
                )
            case .generator:
                guard let generatorID = slot.sourceRef.generatorID else {
                    return .empty
                }
                return .generator(
                    generatorID: generatorID,
                    modifierGeneratorID: slot.sourceRef.modifierGeneratorID,
                    modifierBypassed: slot.sourceRef.modifierBypassed
                )
            }
        }

        return TrackSourceProgram(
            trackID: track.id,
            slotPrograms: slotPrograms,
            macroBindingIDs: track.macros.map(\.id),
            macroDefaults: Dictionary(uniqueKeysWithValues: track.macros.map {
                ($0.id, $0.descriptor.defaultValue)
            })
        )
    }

    private static func compilePhraseBuffer(
        for phrase: PhraseModel,
        project: Project,
        trackPrograms: [UUID: TrackSourceProgram]
    ) -> PhrasePlaybackBuffer {
        let stepCount = max(1, phrase.stepCount)
        let patternLayer = project.layers.first(where: { $0.target == .patternIndex })
        let muteLayer = project.layers.first(where: { $0.target == .mute })
        let fillLayer = project.layers.first(where: { $0.target == .macroRow("fill-flag") })

        let trackStates: [UUID: TrackPhrasePlaybackBuffer] = Dictionary(uniqueKeysWithValues: project.tracks.map { track in
            let macroBindings = trackPrograms[track.id]?.macroBindingIDs ?? []
            let macroLayers: [UUID: PhraseLayerDefinition] = Dictionary(uniqueKeysWithValues: macroBindings.compactMap { bindingID in
                guard let layer = project.layers.first(where: { layer in
                    guard case let .macroParam(trackID, candidateBindingID) = layer.target else {
                        return false
                    }
                    return trackID == track.id && candidateBindingID == bindingID
                }) else {
                    return nil
                }

                return (bindingID, layer)
            })

            let patternSlotIndex = (0..<stepCount).map { stepIndex -> UInt8 in
                let index: Int
                if let patternLayer {
                    switch phrase.resolvedValue(for: patternLayer, trackID: track.id, stepIndex: stepIndex) {
                    case let .index(value):
                        index = value
                    case let .scalar(value):
                        index = Int(value.rounded())
                    case let .bool(isOn):
                        index = isOn ? 1 : 0
                    }
                } else {
                    index = 0
                }
                return UInt8(min(max(index, 0), TrackPatternBank.slotCount - 1))
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

            let macroValues = (0..<stepCount).map { stepIndex in
                macroBindings.map { bindingID in
                    guard let layer = macroLayers[bindingID] else {
                        return trackPrograms[track.id]?.macroDefaults[bindingID] ?? 0
                    }
                    return scalarDouble(
                        from: phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: stepIndex),
                        layer: layer
                    )
                }
            }

            return (
                track.id,
                TrackPhrasePlaybackBuffer(
                    patternSlotIndex: patternSlotIndex,
                    mute: mute,
                    fillEnabled: fillEnabled,
                    macroValues: macroValues
                )
            )
        })

        return PhrasePlaybackBuffer(
            phraseID: phrase.id,
            stepCount: stepCount,
            trackStates: trackStates
        )
    }

    private static func scalarDouble(from value: PhraseCellValue, layer: PhraseLayerDefinition) -> Double {
        switch value {
        case let .scalar(x):
            return min(max(x, layer.minValue), layer.maxValue)
        case let .bool(isOn):
            return isOn ? layer.maxValue : layer.minValue
        case let .index(index):
            return min(max(Double(index), layer.minValue), layer.maxValue)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
