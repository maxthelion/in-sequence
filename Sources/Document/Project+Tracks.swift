import Foundation

extension Project {
    mutating func appendTrack(trackType: TrackType = .monoMelodic) {
        let nextTrack = StepSequenceTrack(
            name: Self.defaultTrackName(for: trackType, index: tracks.count + 1),
            trackType: trackType,
            pitches: Self.defaultPitches(for: trackType),
            stepPattern: Self.defaultStepPattern(for: trackType),
            destination: Self.defaultDestination(for: trackType),
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
        tracks.append(nextTrack)
        let ownedClip = Self.makeOwnedClip(for: nextTrack)
        if let ownedClip {
            clipPool.append(ownedClip)
        }
        patternBanks.append(
            TrackPatternBank.default(for: nextTrack, initialClipID: ownedClip?.id)
        )
        selectedTrackID = nextTrack.id
        syncPhrasesWithTracks()
    }

    @discardableResult
    mutating func appendSliceTrack(sample: AudioSample) -> UUID {
        appendTrack(trackType: .slice)

        let trackID = selectedTrackID
        let sampleLengthFrames = max(0, sample.lengthFrames ?? 0)
        var sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [SliceMarker(startFrame: 0, endFrame: sampleLengthFrames)],
            mode: .manual
        )
        sliceSet.normalize(sampleLengthFrames: sampleLengthFrames)
        addSliceSet(sliceSet)

        if let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) {
            tracks[trackIndex].name = sample.name
            tracks[trackIndex].destination = .slicer(sliceSetID: sliceSet.id, settings: .default)
            tracks[trackIndex].stepPattern = Array(repeating: false, count: 16)
            tracks[trackIndex].stepAccents = Array(repeating: false, count: 16)
        }

        if let clipID = patternBank(for: trackID).slot(at: 0).sourceRef.clipID {
            updateClipEntry(id: clipID) { clip in
                clip.name = "\(sample.name) clip"
                clip.content = .emptySliceTriggers(lengthSteps: 16)
                clip.macroLanes = clip.macroLanes.mapValues { $0.synced(stepCount: 16) }
            }
        }

        return trackID
    }

    mutating func setSelectedTrackType(_ trackType: TrackType) {
        guard !tracks.isEmpty else {
            return
        }

        tracks[selectedTrackIndex].trackType = trackType
        let updatedTrack = tracks[selectedTrackIndex]
        // Always create a new owned clip for the updated track type so we never
        // silently reuse another track's clip. Audio input tracks intentionally
        // have no authored clip source in this model slice.
        let ownedClip = Self.makeOwnedClip(for: updatedTrack)
        if let ownedClip {
            clipPool.append(ownedClip)
        }
        patternBanks = patternBanks.map { bank in
            guard bank.trackID == selectedTrackID else {
                return bank
            }
            return TrackPatternBank.default(for: updatedTrack, initialClipID: ownedClip?.id)
        }
        syncPhrasesWithTracks()
    }

    mutating func removeSelectedTrack() {
        guard tracks.count > 1 else {
            return
        }

        let removedTrack = tracks[selectedTrackIndex]
        if removedTrack.groupID != nil {
            removeFromGroup(trackID: removedTrack.id)
        }
        tracks.remove(at: selectedTrackIndex)
        selectedTrackID = tracks[min(selectedTrackIndex, tracks.count - 1)].id
        syncPhrasesWithTracks()
    }

    /// Remove a specific track by id (guard: must leave at least one track).
    /// Mirrors `removeSelectedTrack`'s group/phrase bookkeeping but addresses the
    /// track explicitly so a multi-selection or a detail-page delete can target
    /// it without first making it the selected track.
    mutating func removeTrack(id: UUID) {
        guard tracks.count > 1,
              let index = tracks.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let removedTrack = tracks[index]
        if removedTrack.groupID != nil {
            removeFromGroup(trackID: removedTrack.id)
        }
        // `removeFromGroup` may have reordered/removed entries; re-resolve.
        guard let removeIndex = tracks.firstIndex(where: { $0.id == id }) else {
            syncPhrasesWithTracks()
            return
        }
        let wasSelected = selectedTrackID == id
        tracks.remove(at: removeIndex)
        if wasSelected {
            selectedTrackID = tracks[min(removeIndex, tracks.count - 1)].id
        } else if !tracks.contains(where: { $0.id == selectedTrackID }) {
            selectedTrackID = tracks[0].id
        }
        syncPhrasesWithTracks()
    }

    /// Remove a set of tracks by id, one at a time, always leaving at least one
    /// track in the project (so the document never reaches the no-track state).
    mutating func removeTracks(ids: [UUID]) {
        for id in ids {
            guard tracks.count > 1 else { break }
            removeTrack(id: id)
        }
    }

    /// Duplicate tracks in project order. Copies are intentionally ungrouped:
    /// pasting a kit member should not silently mutate the kit's membership
    /// graph, but it should preserve the track's authored pattern bank and
    /// phrase-layer values under a fresh track id.
    @discardableResult
    mutating func duplicateTracks(ids: [UUID]) -> [UUID] {
        let requestedIDs = Set(ids)
        guard !requestedIDs.isEmpty else { return [] }

        var usedNames = Set(tracks.map(\.name))
        var createdIDs: [UUID] = []

        for sourceTrack in tracks where requestedIDs.contains(sourceTrack.id) {
            let sourceID = sourceTrack.id
            var duplicate = sourceTrack
            duplicate.id = UUID()
            duplicate.name = Self.uniqueTrackCopyName(for: sourceTrack.name, usedNames: &usedNames)
            duplicate.groupID = nil
            duplicate.voiceTag = nil

            tracks.append(duplicate)
            createdIDs.append(duplicate.id)

            if var sourceBank = patternBanks.first(where: { $0.trackID == sourceID }) {
                sourceBank.trackID = duplicate.id
                sourceBank = duplicatePatternBank(sourceBank)
                patternBanks.append(sourceBank)
            } else {
                patternBanks.append(
                    TrackPatternBank.default(
                        for: duplicate,
                        initialClipID: clipPool.first(where: { $0.trackType == duplicate.trackType })?.id
                    )
                )
            }

            for phraseIndex in phrases.indices {
                let copiedCells = phrases[phraseIndex].cells
                    .filter { $0.trackID == sourceID }
                    .map { PhraseCellAssignment(trackID: duplicate.id, layerID: $0.layerID, cell: $0.cell) }
                phrases[phraseIndex].cells.append(contentsOf: copiedCells)
            }
        }

        if let lastCreatedID = createdIDs.last {
            selectedTrackID = lastCreatedID
        }
        syncPhrasesWithTracks()
        return createdIDs
    }

    private mutating func duplicatePatternBank(_ sourceBank: TrackPatternBank) -> TrackPatternBank {
        var copiedBank = sourceBank
        var copiedClipIDs: [UUID: UUID] = [:]

        for slotIndex in copiedBank.slots.indices {
            guard let sourceClipID = copiedBank.slots[slotIndex].sourceRef.clipID else {
                continue
            }

            let copiedClipID: UUID
            if let existingCopiedID = copiedClipIDs[sourceClipID] {
                copiedClipID = existingCopiedID
            } else if let sourceClip = clipPool.first(where: { $0.id == sourceClipID }) {
                var copiedClip = sourceClip
                copiedClip.id = UUID()
                copiedClip.name = Self.uniqueClipCopyName(for: sourceClip.name, existingNames: Set(clipPool.map(\.name)))
                clipPool.append(copiedClip)
                copiedClipIDs[sourceClipID] = copiedClip.id
                copiedClipID = copiedClip.id
            } else {
                continue
            }

            let sourceRef = copiedBank.slots[slotIndex].sourceRef
            copiedBank.slots[slotIndex].sourceRef = SourceRef(
                mode: sourceRef.mode,
                generatorID: sourceRef.generatorID,
                clipID: copiedClipID,
                modifierGeneratorID: sourceRef.modifierGeneratorID,
                modifierBypassed: sourceRef.modifierBypassed
            )
        }

        return copiedBank
    }

    private static func defaultTrackName(for trackType: TrackType, index: Int) -> String {
        switch trackType {
        case .monoMelodic:
            return index == 1 ? "Main Track" : "Mono \(index)"
        case .polyMelodic:
            return "Poly \(index)"
        case .chord:
            return "Chord \(index)"
        case .slice:
            return "Slice \(index)"
        case .audioInput:
            return index == 1 ? "Audio Input" : "Audio Input \(index)"
        }
    }

    private static func defaultPitches(for trackType: TrackType) -> [Int] {
        switch trackType {
        case .monoMelodic:
            return StepSequenceTrack.default.pitches
        case .polyMelodic:
            return [60, 64, 67]
        case .chord:
            return [60, 64, 67]
        case .slice:
            return [60]
        case .audioInput:
            return [60]
        }
    }

    private static func defaultStepPattern(for trackType: TrackType) -> [Bool] {
        switch trackType {
        case .monoMelodic, .polyMelodic, .chord:
            return StepSequenceTrack.default.stepPattern
        case .slice:
            return Array(repeating: false, count: 16)
        case .audioInput:
            return Array(repeating: false, count: 16)
        }
    }

    private static func uniqueTrackCopyName(for sourceName: String, usedNames: inout Set<String>) -> String {
        let baseName = "\(sourceName) Copy"
        if !usedNames.contains(baseName) {
            usedNames.insert(baseName)
            return baseName
        }

        var index = 2
        while usedNames.contains("\(baseName) \(index)") {
            index += 1
        }
        let resolvedName = "\(baseName) \(index)"
        usedNames.insert(resolvedName)
        return resolvedName
    }

    private static func uniqueClipCopyName(for name: String, existingNames: Set<String>) -> String {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Clip" : name
        var candidate = "\(baseName) Copy"
        var index = 2
        while existingNames.contains(candidate) {
            candidate = "\(baseName) Copy \(index)"
            index += 1
        }
        return candidate
    }

    static func defaultDestination(for trackType: TrackType) -> Destination {
        switch trackType {
        case .monoMelodic, .polyMelodic, .chord:
            return .none
        case .slice:
            return .slicer(sliceSetID: SliceSet.emptyID, settings: .default)
        case .audioInput:
            return .none
        }
    }

    static func makeOwnedClip(for track: StepSequenceTrack) -> ClipPoolEntry? {
        if track.trackType == .audioInput {
            return nil
        }

        if track.trackType == .slice {
            return ClipPoolEntry(
                id: UUID(),
                name: "\(track.name) clip",
                trackType: .slice,
                content: .emptySliceTriggers(lengthSteps: 16)
            )
        }

        if track.trackType == .chord {
            return ClipPoolEntry(
                id: UUID(),
                name: "\(track.name) clip",
                trackType: .chord,
                content: .emptyChordReferences(lengthSteps: 16, defaultSlotID: track.chordPalette.normalized.slots.first?.id)
            )
        }

        guard let template = ClipPoolEntry.defaultPool.first(where: { $0.trackType == track.trackType }) else {
            // No template for this trackType — synthesise an empty note-grid clip.
            return ClipPoolEntry(
                id: UUID(),
                name: "\(track.name) clip",
                trackType: track.trackType,
                content: .emptyNoteGrid(lengthSteps: 16)
            )
        }
        return ClipPoolEntry(
            id: UUID(),
            name: "\(track.name) clip",
            trackType: template.trackType,
            content: template.content
        )
    }
}
