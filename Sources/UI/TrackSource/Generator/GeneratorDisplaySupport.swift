import SwiftUI

func stepDisplayLabel(_ stage: StepStage) -> String {
    stepDisplayLabel(stage.algo)
}

func stepDisplayLabel(_ step: StepAlgo) -> String {
    switch step {
    case .euclidean:
        return "Euclidean"
    case .manual:
        return "Manual"
    case .weighted:
        return "Weighted"
    }
}

func pitchDisplayLabel(_ stage: PitchStage) -> String {
    pitchDisplayLabel(stage.algo)
}

func pitchDisplayLabel(_ pitch: PitchAlgo) -> String {
    switch pitch {
    case .manual:
        return "Manual"
    case .pool:
        return "Pool"
    case .randomInScale:
        return "Random In Scale"
    case .randomInChord:
        return "Random In Chord"
    case .intervalProb:
        return "Interval Probability"
    case .markov:
        return "Markov"
    case .fromClipPitches:
        return "From Clip Pitches"
    case .external:
        return "External"
    }
}

func stepAlgoAccentColor(for kind: StepAlgoKind) -> Color {
    StudioTheme.transportAccent
}
