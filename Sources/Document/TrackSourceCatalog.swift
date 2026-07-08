import Foundation

enum TrackSourceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case generator
    case clip

    var label: String {
        switch self {
        case .generator:
            return "Generator"
        case .clip:
            return "Clip"
        }
    }

    var shortLabel: String {
        switch self {
        case .generator:
            return "Gen"
        case .clip:
            return "Clip"
        }
    }

    var isImplemented: Bool {
        true
    }

    static func available(for trackType: TrackType) -> [TrackSourceMode] {
        if trackType == .audioInput {
            return []
        }
        return [.generator, .clip]
    }
}

enum GeneratorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case monoGenerator
    case polyGenerator
    case progressionChordGenerator
    case sliceGenerator

    var label: String {
        switch self {
        case .monoGenerator:
            return "Mono Generator"
        case .polyGenerator:
            return "Poly Generator"
        case .progressionChordGenerator:
            return "Progression Chords"
        case .sliceGenerator:
            return "Slice Generator"
        }
    }

    var compatibleWith: Set<TrackType> {
        switch self {
        case .monoGenerator:
            return [.monoMelodic]
        case .polyGenerator, .progressionChordGenerator:
            return [.polyMelodic]
        case .sliceGenerator:
            return [.slice]
        }
    }

    var supportsModifierStage: Bool {
        switch self {
        case .monoGenerator, .polyGenerator:
            return true
        case .progressionChordGenerator, .sliceGenerator:
            return false
        }
    }

    var defaultParams: GeneratorParams {
        switch self {
        case .monoGenerator:
            return .defaultMono
        case .polyGenerator:
            return .poly(
                trigger: .native(
                    .init(
                        algo: .euclidean(pulses: 4, steps: 16, offset: 0),
                        basePitch: 60
                    )
                ),
                pitches: [.native(.defaultMono)],
                shape: .default
            )
        case .progressionChordGenerator:
            return .progressionChords(.default)
        case .sliceGenerator:
            return .slice(
                trigger: .native(.init(algo: .euclidean(pulses: 4, steps: 16, offset: 0), basePitch: 60)),
                sliceIndexes: []
            )
        }
    }
}

struct GeneratorPoolEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var kind: GeneratorKind
    var params: GeneratorParams

    init(
        id: UUID,
        name: String,
        trackType: TrackType,
        kind: GeneratorKind,
        params: GeneratorParams
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.kind = kind
        self.params = params
    }

    static func makeDefault(
        id: UUID,
        name: String,
        kind: GeneratorKind,
        trackType: TrackType
    ) -> GeneratorPoolEntry {
        GeneratorPoolEntry(id: id, name: name, trackType: trackType, kind: kind, params: kind.defaultParams)
    }

    static let defaultPool: [GeneratorPoolEntry] = [
        .makeDefault(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1") ?? UUID(),
            name: "Euclidean Mono",
            kind: .monoGenerator,
            trackType: .monoMelodic
        ),
        .makeDefault(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2") ?? UUID(),
            name: "Euclidean Poly",
            kind: .polyGenerator,
            trackType: .polyMelodic
        ),
        .makeDefault(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3") ?? UUID(),
            name: "Progression Chords",
            kind: .progressionChordGenerator,
            trackType: .polyMelodic
        ),
        .makeDefault(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4") ?? UUID(),
            name: "Slice Trigger",
            kind: .sliceGenerator,
            trackType: .slice
        )
    ]
}

extension GeneratorPoolEntry {
    func switchingKind(to targetKind: GeneratorKind) -> GeneratorPoolEntry {
        var copy = self
        copy.kind = targetKind
        copy.trackType = targetKind.compatibleWith.contains(trackType) ? trackType : targetKind.defaultTrackType
        copy.params = params.converted(to: targetKind)
        return copy
    }
}

extension GeneratorKind {
    var defaultTrackType: TrackType {
        switch self {
        case .monoGenerator:
            return .monoMelodic
        case .polyGenerator, .progressionChordGenerator:
            return .polyMelodic
        case .sliceGenerator:
            return .slice
        }
    }
}

extension GeneratorParams {
    func converted(to targetKind: GeneratorKind) -> GeneratorParams {
        let defaults = targetKind.defaultParams
        let trigger = sharedTrigger ?? defaults.sharedTrigger ?? .native(.defaultMono)
        let pitch = sharedPitch ?? defaults.sharedPitch ?? .native(.defaultMono)
        let shape = sharedShape ?? defaults.sharedShape ?? .default

        switch targetKind {
        case .monoGenerator:
            return .mono(trigger: trigger, pitch: pitch, shape: shape)
        case .polyGenerator:
            return .poly(trigger: trigger, pitches: sharedPitches(defaultingTo: pitch), shape: shape)
        case .progressionChordGenerator:
            var params = sharedProgressionParams ?? {
                var seeded = ProgressionChordGeneratorParams.default
                let pitchBasis = pitch.pitchStage.algo.rootScaleBasis
                seeded.rootMIDI = pitchBasis.root
                seeded.mode = pitchBasis.scale.progressionMode
                seeded.velocity = shape.velocity
                return seeded.normalized
            }()
            params.velocity = shape.velocity
            return .progressionChords(params.normalized)
        case .sliceGenerator:
            let indexes = sharedSliceIndexes ?? {
                if case let .slice(_, indexes) = defaults {
                    return indexes
                }
                return []
            }()
            return .slice(trigger: trigger, sliceIndexes: indexes)
        }
    }

    private var sharedTrigger: TriggerStageNode? {
        switch self {
        case let .mono(trigger, _, _), let .poly(trigger, _, _), let .slice(trigger, _):
            return trigger
        case .progressionChords, .drum, .template:
            return nil
        }
    }

    private var sharedPitch: PitchStageNode? {
        switch self {
        case let .mono(_, pitch, _):
            return pitch
        case let .poly(_, pitches, _):
            return pitches.first
        case let .progressionChords(params):
            let normalized = params.normalized
            return .native(.pool(
                root: normalized.rootMIDI,
                scale: normalized.mode.scaleID,
                spread: 12,
                selection: .balanced,
                deviation: .none
            ))
        case .drum, .template, .slice:
            return nil
        }
    }

    private func sharedPitches(defaultingTo pitch: PitchStageNode) -> [PitchStageNode] {
        switch self {
        case let .poly(_, pitches, _):
            return pitches.isEmpty ? [pitch] : pitches
        default:
            return [pitch]
        }
    }

    private var sharedShape: NoteShape? {
        switch self {
        case let .mono(_, _, shape), let .poly(_, _, shape), let .drum(_, shape):
            return shape
        case let .progressionChords(params):
            return NoteShape(velocity: params.normalized.velocity, gateLength: 4, accent: false)
        case .template, .slice:
            return nil
        }
    }

    private var sharedProgressionParams: ProgressionChordGeneratorParams? {
        if case let .progressionChords(params) = self {
            return params.normalized
        }
        return nil
    }

    private var sharedSliceIndexes: [Int]? {
        if case let .slice(_, indexes) = self {
            return indexes
        }
        return nil
    }
}

private extension PitchAlgo {
    var rootScaleBasis: (root: Int, scale: ScaleID) {
        switch self {
        case let .manual(pitches, _):
            return (pitches.first ?? 60, .major)
        case let .pool(root, scale, _, _, _):
            return (root, scale)
        case let .randomInScale(root, scale, _),
             let .intervalProb(root, scale, _),
             let .markov(root, scale, _, _, _):
            return (root, scale)
        case let .randomInChord(root, _, _, _):
            return (root, .major)
        case .fromClipPitches, .external:
            return (60, .major)
        }
    }
}

private extension ScaleID {
    var progressionMode: ProgressionChordMode {
        switch self {
        case .naturalMinor, .harmonicMinor, .melodicMinor, .minorPentatonic, .dorian,
             .phrygian, .locrian, .hungarianMinor:
            return .minor
        default:
            return .major
        }
    }
}

private extension ProgressionChordMode {
    var scaleID: ScaleID {
        switch self {
        case .major:
            return .major
        case .minor:
            return .naturalMinor
        }
    }
}

struct ClipPoolEntry: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var content: ClipContent
    /// Per-step macro overrides keyed by binding descriptor id.
    /// A missing key means no lane exists for that binding (defer to phrase layer / default).
    /// Legacy docs without this field decode as empty -- no migration needed.
    var macroLanes: [UUID: MacroLane]
    /// Persisted clip-randomize rules and last seed. Legacy docs decode as nil.
    var randomizeSettings: ClipRandomizeSettings?

    init(
        id: UUID,
        name: String,
        trackType: TrackType,
        content: ClipContent,
        macroLanes: [UUID: MacroLane] = [:],
        randomizeSettings: ClipRandomizeSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.content = content
        self.macroLanes = macroLanes
        self.randomizeSettings = randomizeSettings
    }

    /// Drop lanes for removed bindings and resize remaining lanes to match step count.
    func synced(with macros: [TrackMacroBinding], stepCount: Int) -> ClipPoolEntry {
        let validIDs = Set(macros.map(\.id))
        let syncedLanes = macroLanes
            .filter { validIDs.contains($0.key) }
            .mapValues { $0.synced(stepCount: stepCount) }
        return ClipPoolEntry(
            id: id,
            name: name,
            trackType: trackType,
            content: content,
            macroLanes: syncedLanes,
            randomizeSettings: randomizeSettings
        )
    }

    /// Remove a single macro lane (used on binding cascade removal).
    func removingMacroLane(id bindingID: UUID) -> ClipPoolEntry {
        var copy = self
        copy.macroLanes.removeValue(forKey: bindingID)
        return copy
    }

    static let defaultPool: [ClipPoolEntry] = [
        ClipPoolEntry(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1") ?? UUID(),
            name: "Mono Step Clip",
            trackType: .monoMelodic,
            content: .stepSequence(
                stepPattern: [true, false, true, false, true, false, false, true, true, false, true, false, true, false, false, true],
                pitches: [60, 62, 64, 67]
            )
        ),
        ClipPoolEntry(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2") ?? UUID(),
            name: "Chord Roll",
            trackType: .polyMelodic,
            content: .pianoRoll(
                lengthBars: 2,
                stepsPerBar: 16,
                notes: [
                    ClipNote(pitch: 60, startStep: 0, lengthSteps: 8, velocity: 100),
                    ClipNote(pitch: 64, startStep: 0, lengthSteps: 8, velocity: 92),
                    ClipNote(pitch: 67, startStep: 0, lengthSteps: 8, velocity: 88),
                    ClipNote(pitch: 62, startStep: 8, lengthSteps: 8, velocity: 100),
                    ClipNote(pitch: 65, startStep: 8, lengthSteps: 8, velocity: 92),
                    ClipNote(pitch: 69, startStep: 8, lengthSteps: 8, velocity: 88),
                    ClipNote(pitch: 59, startStep: 16, lengthSteps: 8, velocity: 96),
                    ClipNote(pitch: 62, startStep: 16, lengthSteps: 8, velocity: 88),
                    ClipNote(pitch: 67, startStep: 16, lengthSteps: 8, velocity: 84),
                    ClipNote(pitch: 55, startStep: 24, lengthSteps: 8, velocity: 96),
                    ClipNote(pitch: 60, startStep: 24, lengthSteps: 8, velocity: 88),
                    ClipNote(pitch: 64, startStep: 24, lengthSteps: 8, velocity: 84),
                ]
            )
        ),
        ClipPoolEntry(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4") ?? UUID(),
            name: "Chord Palette Clip",
            trackType: .chord,
            content: .chordReferences(
                stepPattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false],
                slotIDs: [
                    ChordPalette.default.slotID(at: 0),
                    ChordPalette.default.slotID(at: 0),
                    ChordPalette.default.slotID(at: 0),
                    ChordPalette.default.slotID(at: 0),
                    ChordPalette.default.slotID(at: 1),
                    ChordPalette.default.slotID(at: 1),
                    ChordPalette.default.slotID(at: 1),
                    ChordPalette.default.slotID(at: 1),
                    ChordPalette.default.slotID(at: 2),
                    ChordPalette.default.slotID(at: 2),
                    ChordPalette.default.slotID(at: 2),
                    ChordPalette.default.slotID(at: 2),
                    ChordPalette.default.slotID(at: 3),
                    ChordPalette.default.slotID(at: 3),
                    ChordPalette.default.slotID(at: 3),
                    ChordPalette.default.slotID(at: 3),
                ],
                inversions: Array(repeating: 0, count: 16),
                chordIDs: Array(repeating: nil, count: 16),
                velocities: Array(repeating: 96, count: 16),
                lengthSteps: Array(repeating: 4, count: 16)
            )
        ),
        ClipPoolEntry(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3") ?? UUID(),
            name: "Slice Lane",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: [true, false, false, true, false, false, true, false, true, false, false, true, false, true, false, false],
                sliceIndexes: [0, 2, 4, 5],
                stepModes: Array(repeating: .single, count: 16)
            )
        )
    ]
}

extension ClipPoolEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(trackType)
        hasher.combine(content)
        // macroLanes is not Hashable (values are [Double?]) -- use id as primary hash.
    }
}

extension ClipPoolEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trackType
        case content
        case macroLanes
        case randomizeSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackType = try container.decode(TrackType.self, forKey: .trackType)
        content = try container.decode(ClipContent.self, forKey: .content)
        // Legacy docs without macroLanes decode as empty -- no migration needed.
        macroLanes = try container.decodeIfPresent([UUID: MacroLane].self, forKey: .macroLanes) ?? [:]
        randomizeSettings = try container.decodeIfPresent(ClipRandomizeSettings.self, forKey: .randomizeSettings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackType, forKey: .trackType)
        try container.encode(content, forKey: .content)
        try container.encode(macroLanes, forKey: .macroLanes)
        try container.encodeIfPresent(randomizeSettings, forKey: .randomizeSettings)
    }
}

extension ClipPoolEntry {
    var pitchPool: [Int] {
        switch content {
        case let .noteGrid(_, steps):
            return Array(
                Set(
                    steps.flatMap { step in
                        (step.main?.notes ?? []) + (step.fill?.notes ?? [])
                    }
                    .map(\.pitch)
                )
            )
            .sorted()
        case .chordReferences:
            guard case let .noteGrid(_, steps) = content.resolvedChordNoteGrid(palette: .default) else {
                return []
            }
            return Array(
                Set(
                    steps.flatMap { step in
                        (step.main?.notes ?? []) + (step.fill?.notes ?? [])
                    }
                    .map(\.pitch)
                )
            )
            .sorted()
        case let .sliceTriggers(_, sliceIndexes, _, _):
            return sliceIndexes.map { 60 + $0 }
        }
    }

    var hasPitchMaterial: Bool {
        !pitchPool.isEmpty
    }
}

struct SourceRef: Codable, Equatable, Hashable, Sendable {
    var mode: TrackSourceMode
    var generatorID: UUID?
    var clipID: UUID?
    var sourceClipID: UUID?
    var modifierGeneratorID: UUID?
    var modifierBypassed: Bool

    private enum CodingKeys: String, CodingKey {
        case mode
        case generatorID
        case clipID
        case sourceClipID
        case modifierGeneratorID
        case modifierBypassed
    }

    init(
        mode: TrackSourceMode,
        generatorID: UUID? = nil,
        clipID: UUID? = nil,
        sourceClipID: UUID? = nil,
        modifierGeneratorID: UUID? = nil,
        modifierBypassed: Bool = false
    ) {
        self.mode = mode
        self.generatorID = generatorID
        self.clipID = clipID
        self.sourceClipID = sourceClipID
        self.modifierGeneratorID = modifierGeneratorID
        self.modifierBypassed = modifierBypassed
    }

    static func generator(_ id: UUID?) -> SourceRef {
        SourceRef(mode: .generator, generatorID: id, modifierGeneratorID: id)
    }

    static func clip(_ id: UUID?) -> SourceRef {
        SourceRef(mode: .clip, clipID: id)
    }

    var hasActiveModifier: Bool {
        modifierGeneratorID != nil && !modifierBypassed
    }

    var isEmpty: Bool {
        switch mode {
        case .generator:
            return generatorID == nil
        case .clip:
            return clipID == nil
        }
    }

    func normalized(
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> SourceRef {
        if trackType == .audioInput {
            return .clip(nil)
        }

        let compatibleSourceGeneratorID: UUID? = {
            switch mode {
            case .generator:
                return generatorPool.first(where: { $0.id == generatorID && $0.trackType == trackType })?.id
                    ?? generatorPool.first(where: { $0.trackType == trackType })?.id
            case .clip:
                return generatorID
            }
        }()

        let compatibleModifierGeneratorID = generatorPool.first(where: {
            $0.id == modifierGeneratorID
                && $0.trackType == trackType
                && $0.kind.supportsModifierStage
        })?.id
        let compatibleSourceClipID = sourceClipID.flatMap { candidateID in
            clipPool.first(where: { $0.id == candidateID && $0.trackType == trackType })?.id
        }

        switch mode {
        case .generator:
            return SourceRef(
                mode: .generator,
                generatorID: compatibleSourceGeneratorID,
                clipID: clipID,
                sourceClipID: compatibleSourceClipID,
                modifierGeneratorID: compatibleModifierGeneratorID,
                modifierBypassed: compatibleModifierGeneratorID == nil ? false : modifierBypassed
            )
        case .clip:
            guard let clipID else {
                return SourceRef(
                    mode: .clip,
                    generatorID: compatibleSourceGeneratorID,
                    clipID: nil,
                    sourceClipID: compatibleSourceClipID,
                    modifierGeneratorID: compatibleModifierGeneratorID,
                    modifierBypassed: compatibleModifierGeneratorID == nil ? false : modifierBypassed
                )
            }
            let compatibleID = clipPool.first(where: { $0.id == clipID && $0.trackType == trackType })?.id
            return SourceRef(
                mode: .clip,
                generatorID: compatibleSourceGeneratorID,
                clipID: compatibleID,
                sourceClipID: compatibleSourceClipID,
                modifierGeneratorID: compatibleModifierGeneratorID,
                modifierBypassed: compatibleModifierGeneratorID == nil ? false : modifierBypassed
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(TrackSourceMode.self, forKey: .mode)
        let generatorID = try container.decodeIfPresent(UUID.self, forKey: .generatorID)
        let clipID = try container.decodeIfPresent(UUID.self, forKey: .clipID)
        let sourceClipID = try container.decodeIfPresent(UUID.self, forKey: .sourceClipID)
        let hasModifierKey = container.contains(.modifierGeneratorID)
        let decodedModifierID = try container.decodeIfPresent(UUID.self, forKey: .modifierGeneratorID)
        let modifierBypassed = try container.decodeIfPresent(Bool.self, forKey: .modifierBypassed) ?? false

        let resolvedModifierID: UUID? = {
            if hasModifierKey {
                return decodedModifierID
            }
            return generatorID
        }()

        self.init(
            mode: mode,
            generatorID: generatorID,
            clipID: clipID,
            sourceClipID: sourceClipID,
            modifierGeneratorID: resolvedModifierID,
            modifierBypassed: modifierBypassed
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(generatorID, forKey: .generatorID)
        try container.encodeIfPresent(clipID, forKey: .clipID)
        try container.encodeIfPresent(sourceClipID, forKey: .sourceClipID)
        if let modifierGeneratorID {
            try container.encode(modifierGeneratorID, forKey: .modifierGeneratorID)
        } else {
            try container.encodeNil(forKey: .modifierGeneratorID)
        }
        try container.encode(modifierBypassed, forKey: .modifierBypassed)
    }
}
