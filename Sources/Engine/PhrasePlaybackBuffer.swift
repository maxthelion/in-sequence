import Foundation

struct TrackPhrasePlaybackBuffer: Equatable, Sendable {
    let patternSlotIndex: [UInt8]
    let mute: [Bool]
    let fillEnabled: [Bool]
    let macroValues: [[Double]]
}

struct PhrasePlaybackBuffer: Equatable, Sendable {
    let phraseID: UUID
    let stepCount: Int
    let repeatCount: Int
    let loopEnabled: Bool
    let sceneState: PhraseSceneState?
    let stepOrderMap: [UInt8]?
    let trackStates: [UUID: TrackPhrasePlaybackBuffer]

    init(
        phraseID: UUID,
        stepCount: Int,
        repeatCount: Int,
        loopEnabled: Bool,
        sceneState: PhraseSceneState? = nil,
        stepOrderMap: [UInt8]? = nil,
        trackStates: [UUID: TrackPhrasePlaybackBuffer]
    ) {
        self.phraseID = phraseID
        self.stepCount = max(1, stepCount)
        self.repeatCount = repeatCount
        self.loopEnabled = loopEnabled
        self.sceneState = sceneState?.normalized()
        self.stepOrderMap = stepOrderMap
        self.trackStates = trackStates
    }

    func trackState(for trackID: UUID) -> TrackPhrasePlaybackBuffer? {
        trackStates[trackID]
    }

    func withStepOrderMap(_ stepOrderMap: [UInt8]?) -> PhrasePlaybackBuffer {
        PhrasePlaybackBuffer(
            phraseID: phraseID,
            stepCount: stepCount,
            repeatCount: repeatCount,
            loopEnabled: loopEnabled,
            sceneState: sceneState,
            stepOrderMap: stepOrderMap,
            trackStates: trackStates
        )
    }

    func sourceStepIndex(for outputStepIndex: Int) -> Int {
        let normalizedOutputStep = ((outputStepIndex % stepCount) + stepCount) % stepCount
        guard let stepOrderMap,
              stepCount == Self.stepOrderMapLength,
              stepOrderMap.count == Self.stepOrderMapLength
        else {
            return normalizedOutputStep
        }

        let sourceStepIndex = Int(stepOrderMap[normalizedOutputStep])
        guard (0..<stepCount).contains(sourceStepIndex) else {
            return normalizedOutputStep
        }
        return sourceStepIndex
    }

    private static let stepOrderMapLength = 16
}
