import SwiftUI

func stepDisplayLabel(_ stage: StepStage) -> String {
    stepDisplayLabel(stage.algo)
}

func stepDisplayLabel(_ step: StepAlgo) -> String {
    switch step {
    case .manual:
        return "Manual"
    case .randomWeighted:
        return "Random Weighted"
    case .euclidean:
        return "Euclidean"
    case .perStepProbability:
        return "Per-Step Probability"
    case .fromClipSteps:
        return "From Clip Steps"
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
    case .manual:
        return StudioTheme.cyan
    case .euclidean:
        return StudioTheme.success
    case .randomWeighted:
        return StudioTheme.amber
    case .perStepProbability:
        return StudioTheme.violet
    case .fromClipSteps:
        return StudioTheme.violet
    }
}
