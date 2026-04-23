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
        algo: .euclidean(pulses: 4, steps: 16, offset: 0),
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

enum GeneratedSourcePipelineContent: Codable, Equatable, Hashable, Sendable {
    case melodic(pitches: [PitchStageNode], shape: NoteShape)
    case drum(triggers: [VoiceTag: TriggerStageNode], shape: NoteShape)
    case slice(sliceIndexes: [Int])
    case template(templateID: UUID)
}

struct GeneratedSourcePipeline: Codable, Equatable, Hashable, Sendable {
    var trigger: TriggerStageNode?
    var content: GeneratedSourcePipelineContent

    static func melodic(
        trigger: TriggerStageNode,
        pitches: [PitchStageNode],
        shape: NoteShape
    ) -> GeneratedSourcePipeline {
        GeneratedSourcePipeline(
            trigger: trigger,
            content: .melodic(pitches: pitches, shape: shape)
        )
    }

    static func drum(
        triggers: [VoiceTag: TriggerStageNode],
        shape: NoteShape
    ) -> GeneratedSourcePipeline {
        GeneratedSourcePipeline(
            trigger: nil,
            content: .drum(triggers: triggers, shape: shape)
        )
    }

    static func slice(
        trigger: TriggerStageNode,
        sliceIndexes: [Int]
    ) -> GeneratedSourcePipeline {
        GeneratedSourcePipeline(
            trigger: trigger,
            content: .slice(sliceIndexes: sliceIndexes)
        )
    }

    static func template(_ templateID: UUID) -> GeneratedSourcePipeline {
        GeneratedSourcePipeline(
            trigger: nil,
            content: .template(templateID: templateID)
        )
    }
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
    var generatedSourcePipeline: GeneratedSourcePipeline {
        switch self {
        case let .mono(trigger, pitch, shape):
            return .melodic(trigger: trigger, pitches: [pitch], shape: shape)
        case let .poly(trigger, pitches, shape):
            return .melodic(trigger: trigger, pitches: pitches, shape: shape)
        case let .drum(triggers, shape):
            return .drum(triggers: triggers, shape: shape)
        case let .slice(trigger, sliceIndexes):
            return .slice(trigger: trigger, sliceIndexes: sliceIndexes)
        case let .template(templateID):
            return .template(templateID)
        }
    }
}
