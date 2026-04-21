import Foundation

struct NoteSeed: Codable, Equatable, Hashable, Sendable {
    var pitch: Int
    var voiceTag: VoiceTag?
}

struct GeneratedNote: Codable, Equatable, Hashable, Sendable {
    var pitch: Int
    var velocity: Int
    var length: Int
    var voiceTag: VoiceTag?
}

enum HarmonicSidechainSource: Codable, Equatable, Hashable, Sendable {
    case none
    case projectChordContext
    case clip(UUID)
}

struct StepStage: Codable, Equatable, Hashable, Sendable {
    var algo: StepAlgo
    var basePitch: Int

    static let defaultMono = StepStage(
        algo: .manual(pattern: Array(repeating: false, count: 16)),
        basePitch: 60
    )
}

struct PitchStage: Codable, Equatable, Hashable, Sendable {
    var algo: PitchAlgo
    var harmonicSidechain: HarmonicSidechainSource

    static let defaultMono = PitchStage(
        algo: .manual(pitches: [60, 62, 64, 67], pickMode: .random),
        harmonicSidechain: .none
    )
}

enum TriggerStageNode: Codable, Equatable, Hashable, Sendable {
    case native(StepStage)

    static func native(_ algo: StepAlgo, basePitch: Int = 60) -> TriggerStageNode {
        .native(StepStage(algo: algo, basePitch: basePitch))
    }

    var stepStage: StepStage {
        switch self {
        case let .native(stage):
            return stage
        }
    }
}

enum PitchStageNode: Codable, Equatable, Hashable, Sendable {
    case native(PitchStage)

    static func native(_ algo: PitchAlgo, harmonicSidechain: HarmonicSidechainSource = .none) -> PitchStageNode {
        .native(PitchStage(algo: algo, harmonicSidechain: harmonicSidechain))
    }

    var pitchStage: PitchStage {
        switch self {
        case let .native(stage):
            return stage
        }
    }
}

struct GeneratedSourcePipeline: Codable, Equatable, Hashable, Sendable {
    var trigger: TriggerStageNode
    var pitches: [PitchStageNode]
    var shape: NoteShape
}

struct GeneratedSourceEvaluationState: Equatable, Sendable {
    var lastPitchesByLane: [Int?]

    init(lastPitchesByLane: [Int?] = []) {
        self.lastPitchesByLane = lastPitchesByLane
    }

    mutating func lastPitch(for laneIndex: Int) -> Int? {
        if !lastPitchesByLane.indices.contains(laneIndex) {
            lastPitchesByLane.append(contentsOf: Array(repeating: nil, count: laneIndex - lastPitchesByLane.count + 1))
        }
        return lastPitchesByLane[laneIndex]
    }

    mutating func setLastPitch(_ pitch: Int?, for laneIndex: Int) {
        if !lastPitchesByLane.indices.contains(laneIndex) {
            lastPitchesByLane.append(contentsOf: Array(repeating: nil, count: laneIndex - lastPitchesByLane.count + 1))
        }
        lastPitchesByLane[laneIndex] = pitch
    }
}

extension GeneratorParams {
    var generatedSourcePipeline: GeneratedSourcePipeline? {
        switch self {
        case let .mono(trigger, pitch, shape):
            return GeneratedSourcePipeline(trigger: trigger, pitches: [pitch], shape: shape)
        case let .poly(trigger, pitches, shape):
            return GeneratedSourcePipeline(trigger: trigger, pitches: pitches, shape: shape)
        case .drum, .template, .slice:
            return nil
        }
    }
}
