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

    private static func defaultTrackName(for trackType: TrackType, index: Int) -> String {
        switch trackType {
        case .monoMelodic:
            return index == 1 ? "Main Track" : "Mono \(index)"
        case .polyMelodic:
            return "Poly \(index)"
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
        case .slice:
            return [60]
        case .audioInput:
            return [60]
        }
    }

    private static func defaultStepPattern(for trackType: TrackType) -> [Bool] {
        switch trackType {
        case .monoMelodic, .polyMelodic:
            return StepSequenceTrack.default.stepPattern
        case .slice:
            return Array(repeating: false, count: 16)
        case .audioInput:
            return Array(repeating: false, count: 16)
        }
    }

    static func defaultDestination(for trackType: TrackType) -> Destination {
        switch trackType {
        case .monoMelodic, .polyMelodic:
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
