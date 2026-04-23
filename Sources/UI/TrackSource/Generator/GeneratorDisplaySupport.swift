import SwiftUI

func stepDisplayLabel(_ stage: StepStage) -> String {
    stepDisplayLabel(stage.algo)
}

func stepDisplayLabel(_ step: StepAlgo) -> String {
    switch step {
    case .euclidean:
        return "Euclidean"
    }
}

func pitchDisplayLabel(_ stage: PitchStage) -> String {
    pitchDisplayLabel(stage.algo)
}

func pitchDisplayLabel(_ pitch: PitchAlgo) -> String {
    switch pitch {
    case .manual:
        return "Manual"
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
    switch kind {
        case .euclidean:
        return StudioTheme.success
    }
}
