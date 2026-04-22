import Foundation

struct PlaybackSnapshot: Equatable, Sendable {
    let selectedPhraseID: UUID
    let trackOrder: [UUID]
    let trackOrdinalByID: [UUID: Int]
    let tracksByID: [UUID: StepSequenceTrack]
    let clipsByID: [UUID: ClipPoolEntry]
    let clipBuffersByID: [UUID: ClipBuffer]
    let trackProgramsByTrackID: [UUID: TrackSourceProgram]
    let phraseBuffersByID: [UUID: PhrasePlaybackBuffer]
    let generatorsByID: [UUID: GeneratorPoolEntry]
}
