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
        clipPool.append(ownedClip)
        patternBanks.append(
            TrackPatternBank.default(for: nextTrack, initialClipID: ownedClip.id)
        )
        selectedTrackID = nextTrack.id
        syncPhrasesWithTracks()
    }

    @discardableResult
    mutating func addDrumKit(
        _ preset: DrumKitPreset,
        library: AudioSampleLibrary = .shared
    ) -> TrackGroupID? {
        addDrumGroup(plan: .templated(from: preset), library: library)
    }

    mutating func setSelectedTrackType(_ trackType: TrackType) {
        guard !tracks.isEmpty else {
            return
        }

        tracks[selectedTrackIndex].trackType = trackType
        let updatedTrack = tracks[selectedTrackIndex]
        // Always create a new owned clip for the updated track type so we never
        // silently reuse another track's clip.
        let ownedClip = Self.makeOwnedClip(for: updatedTrack)
        clipPool.append(ownedClip)
        patternBanks = patternBanks.map { bank in
            guard bank.trackID == selectedTrackID else {
                return bank
            }
            return TrackPatternBank.default(for: updatedTrack, initialClipID: ownedClip.id)
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

    private static func defaultTrackName(for trackType: TrackType, index: Int) -> String {
        switch trackType {
        case .monoMelodic:
            return index == 1 ? "Main Track" : "Mono \(index)"
        case .polyMelodic:
            return "Poly \(index)"
        case .slice:
            return "Slice \(index)"
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
        }
    }

    private static func defaultStepPattern(for trackType: TrackType) -> [Bool] {
        switch trackType {
        case .monoMelodic, .polyMelodic:
            return StepSequenceTrack.default.stepPattern
        case .slice:
            return [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]
        }
    }

    static func defaultDestination(for trackType: TrackType) -> Destination {
        switch trackType {
        case .monoMelodic, .polyMelodic:
            return .none
        case .slice:
            return .internalSampler(bankID: .sliceDefault, preset: "empty-slice")
        }
    }

    static func makeOwnedClip(for track: StepSequenceTrack) -> ClipPoolEntry {
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
