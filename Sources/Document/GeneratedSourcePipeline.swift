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
    var sliceParameters: SliceTriggerStepParameters?

    init(
        pitch: Int,
        velocity: Int,
        length: Int,
        voiceTag: VoiceTag?,
        sliceParameters: SliceTriggerStepParameters? = nil
    ) {
        self.pitch = pitch
        self.velocity = velocity
        self.length = length
        self.voiceTag = voiceTag
        self.sliceParameters = sliceParameters
    }
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

    init(algo: PitchAlgo, harmonicSidechain: HarmonicSidechainSource) {
        self.algo = algo
        self.harmonicSidechain = harmonicSidechain
    }

    static let defaultMono = PitchStage(
        algo: .pool(
            root: 60,
            scale: .major,
            spread: 12,
            selection: .balanced,
            deviation: .none
        ),
        harmonicSidechain: .none
    )
}

extension PitchStage {
    private enum CodingKeys: String, CodingKey {
        case algo
        case harmonicSidechain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algo = try container.decode(PitchAlgo.self, forKey: .algo).normalizedForPitchGrammar
        harmonicSidechain = try container.decode(HarmonicSidechainSource.self, forKey: .harmonicSidechain)
    }
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
    case chordGenerator(ChordGeneratorParams)
    case progressionChords(ProgressionChordGeneratorParams)
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

    static func progressionChords(
        _ params: ProgressionChordGeneratorParams
    ) -> GeneratedSourcePipeline {
        GeneratedSourcePipeline(
            trigger: nil,
            content: .progressionChords(params.normalized)
        )
    }

    static func chordGenerator(_ params: ChordGeneratorParams) -> GeneratedSourcePipeline {
        let normalized = params.normalized
        return GeneratedSourcePipeline(
            trigger: normalized.trigger,
            content: .chordGenerator(normalized)
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

enum GeneratedSourceEvaluationScope: Hashable, Sendable {
    case primary
    case generatorSource(slotIndex: Int, generatorID: UUID)
    case generatorModifier(slotIndex: Int, generatorID: UUID)
}

struct GeneratedSourceEvaluationState: Equatable, Sendable {
    var lastPitchesByLane: [Int?]
    var scopedLastPitchesByLane: [GeneratedSourceEvaluationScope: [Int?]]

    init(
        lastPitchesByLane: [Int?] = [],
        scopedLastPitchesByLane: [GeneratedSourceEvaluationScope: [Int?]] = [:]
    ) {
        self.lastPitchesByLane = lastPitchesByLane
        self.scopedLastPitchesByLane = scopedLastPitchesByLane
    }

    mutating func lastPitch(for laneIndex: Int) -> Int? {
        expand(&lastPitchesByLane, through: laneIndex)
        return lastPitchesByLane[laneIndex]
    }

    mutating func setLastPitch(_ pitch: Int?, for laneIndex: Int) {
        expand(&lastPitchesByLane, through: laneIndex)
        lastPitchesByLane[laneIndex] = pitch
    }

    mutating func lastPitch(for laneIndex: Int, scope: GeneratedSourceEvaluationScope) -> Int? {
        guard scope != .primary else {
            return lastPitch(for: laneIndex)
        }
        var lanes = scopedLastPitchesByLane[scope] ?? fallbackLanes(for: scope)
        expand(&lanes, through: laneIndex)
        scopedLastPitchesByLane[scope] = lanes
        return lanes[laneIndex]
    }

    mutating func setLastPitch(
        _ pitch: Int?,
        for laneIndex: Int,
        scope: GeneratedSourceEvaluationScope
    ) {
        guard scope != .primary else {
            setLastPitch(pitch, for: laneIndex)
            return
        }
        var lanes = scopedLastPitchesByLane[scope] ?? []
        expand(&lanes, through: laneIndex)
        lanes[laneIndex] = pitch
        scopedLastPitchesByLane[scope] = lanes
        if case .generatorSource = scope {
            setLastPitch(pitch, for: laneIndex)
        }
    }

    private func fallbackLanes(for scope: GeneratedSourceEvaluationScope) -> [Int?] {
        switch scope {
        case .primary, .generatorSource:
            return lastPitchesByLane
        case .generatorModifier:
            return []
        }
    }

    private func expand(_ lanes: inout [Int?], through laneIndex: Int) {
        if !lanes.indices.contains(laneIndex) {
            lanes.append(contentsOf: Array(repeating: nil, count: laneIndex - lanes.count + 1))
        }
    }
}

extension GeneratorParams {
    /// The generator's CLUSTER character for the density transform (synthesis
    /// §4: "a phrase-level density sweep densifies in the generator's own
    /// character"). Only the WS4 weighted trigger carries the bipolar cluster
    /// factor; every other trigger kind is neutral.
    var densityCluster: Double {
        switch self {
        case let .mono(trigger, _, _),
             let .poly(trigger, _, _),
             let .slice(trigger, _):
            return trigger.stepStage.algo.densityCluster
        case let .chordGenerator(params):
            return params.normalized.trigger.stepStage.algo.densityCluster
        case let .drum(triggers, _):
            let clusters = triggers.values.map { $0.stepStage.algo.densityCluster }
            guard !clusters.isEmpty else { return 0 }
            return clusters.reduce(0, +) / Double(clusters.count)
        case .progressionChords, .template:
            return 0
        }
    }

    var generatedSourcePipeline: GeneratedSourcePipeline {
        switch self {
        case let .mono(trigger, pitch, shape):
            return .melodic(trigger: trigger, pitches: [pitch], shape: shape)
        case let .poly(trigger, pitches, shape):
            return .melodic(trigger: trigger, pitches: pitches, shape: shape)
        case let .chordGenerator(params):
            return .chordGenerator(params)
        case let .progressionChords(params):
            return .progressionChords(params)
        case let .drum(triggers, shape):
            return .drum(triggers: triggers, shape: shape)
        case let .slice(trigger, sliceIndexes):
            return .slice(trigger: trigger, sliceIndexes: sliceIndexes)
        case let .template(templateID):
            return .template(templateID)
        }
    }
}

private extension StepAlgo {
    var densityCluster: Double {
        switch self {
        case let .weighted(_, _, cluster):
            return min(max(cluster, -1), 1)
        case .euclidean, .manual:
            return 0
        }
    }
}
