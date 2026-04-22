import Foundation

struct PhraseModel: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var lengthBars: Int
    var stepsPerBar: Int
    var cells: [PhraseCellAssignment]

    init(
        id: UUID,
        name: String,
        lengthBars: Int,
        stepsPerBar: Int,
        cells: [PhraseCellAssignment]
    ) {
        self.id = id
        self.name = name
        self.lengthBars = max(1, lengthBars)
        self.stepsPerBar = max(1, stepsPerBar)
        self.cells = cells
    }

    static func `default`(
        tracks: [StepSequenceTrack],
        layers: [PhraseLayerDefinition]? = nil,
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = []
    ) -> PhraseModel {
        _ = generatorPool
        _ = clipPool

        let resolvedLayers = layers ?? PhraseLayerDefinition.defaultSet(for: tracks)
        return PhraseModel(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            name: "Phrase A",
            lengthBars: 8,
            stepsPerBar: 16,
            cells: resolvedLayers.flatMap { layer in
                tracks.map { track in
                    PhraseCellAssignment(trackID: track.id, layerID: layer.id, cell: .inheritDefault)
                }
            }
        )
    }

    var stepCount: Int {
        max(1, lengthBars * stepsPerBar)
    }

    func cell(for layerID: String, trackID: UUID) -> PhraseCell {
        cells.first(where: { $0.trackID == trackID && $0.layerID == layerID })?.cell ?? .inheritDefault
    }

    mutating func setCell(_ cell: PhraseCell, for layerID: String, trackID: UUID) {
        if let index = cells.firstIndex(where: { $0.trackID == trackID && $0.layerID == layerID }) {
            cells[index].cell = cell
        } else {
            cells.append(PhraseCellAssignment(trackID: trackID, layerID: layerID, cell: cell))
        }
    }

    func cellMode(for layerID: String, trackID: UUID) -> PhraseCellEditMode {
        cell(for: layerID, trackID: trackID).editMode
    }

    mutating func setCellMode(
        _ mode: PhraseCellEditMode,
        for layer: PhraseLayerDefinition,
        trackID: UUID
    ) {
        let updated = PhraseCell.makeDefault(
            mode: mode,
            layer: layer,
            defaultValue: layer.defaultValue(for: trackID),
            stepCount: stepCount,
            barCount: lengthBars
        )
        setCell(updated, for: layer.id, trackID: trackID)
    }

    func resolvedValue(
        for layer: PhraseLayerDefinition,
        trackID: UUID,
        stepIndex: Int
    ) -> PhraseCellValue {
        let clampedStep = min(max(stepIndex, 0), stepCount - 1)
        let fallback = layer.defaultValue(for: trackID).normalized(for: layer)

        switch cell(for: layer.id, trackID: trackID) {
        case .inheritDefault:
            return fallback
        case let .single(value):
            return value.normalized(for: layer)
        case let .bars(values):
            guard !values.isEmpty else { return fallback }
            let barIndex = min(max(clampedStep / stepsPerBar, 0), values.count - 1)
            return values[barIndex].normalized(for: layer)
        case let .steps(values):
            guard !values.isEmpty else { return fallback }
            return values[min(clampedStep, values.count - 1)].normalized(for: layer)
        case let .curve(points):
            let sampled = PhraseCurveSampler.sample(
                points: points,
                at: clampedStep,
                stepCount: stepCount,
                range: layer.scalarRange
            )
            return .scalar(sampled)
        }
    }

    func patternIndex(for trackID: UUID, layers: [PhraseLayerDefinition]) -> Int {
        guard let layer = layers.first(where: { $0.target == .patternIndex }) else {
            return 0
        }

        switch resolvedValue(for: layer, trackID: trackID, stepIndex: 0) {
        case let .index(index):
            return min(max(index, 0), TrackPatternBank.slotCount - 1)
        case let .scalar(value):
            return min(max(Int(value.rounded()), 0), TrackPatternBank.slotCount - 1)
        case let .bool(isOn):
            return isOn ? 1 : 0
        }
    }

    func usedPatternIndexes(for trackID: UUID, layers: [PhraseLayerDefinition]) -> Set<Int> {
        guard let layer = layers.first(where: { $0.target == .patternIndex }) else {
            return [0]
        }

        switch cell(for: layer.id, trackID: trackID) {
        case .inheritDefault, .single, .curve:
            return [patternIndex(for: trackID, layers: layers)]
        case let .bars(values), let .steps(values):
            let indexes = values.map { value -> Int in
                switch value.normalized(for: layer) {
                case let .index(index):
                    return min(max(index, 0), TrackPatternBank.slotCount - 1)
                case let .scalar(scalar):
                    return min(max(Int(scalar.rounded()), 0), TrackPatternBank.slotCount - 1)
                case let .bool(isOn):
                    return isOn ? 1 : 0
                }
            }
            return Set(indexes)
        }
    }

    mutating func setPatternIndex(_ index: Int, for trackID: UUID, layers: [PhraseLayerDefinition]) {
        guard let layer = layers.first(where: { $0.target == .patternIndex }) else {
            return
        }
        setCell(.single(.index(min(max(index, 0), TrackPatternBank.slotCount - 1))), for: layer.id, trackID: trackID)
    }

    func synced(with tracks: [StepSequenceTrack], layers: [PhraseLayerDefinition]) -> PhraseModel {
        let trackIDs = Set(tracks.map(\.id))
        let layerIDs = Set(layers.map(\.id))
        let normalizedCells = layers.flatMap { layer in
            tracks.map { track in
                cells.first(where: { $0.trackID == track.id && $0.layerID == layer.id })
                    ?? PhraseCellAssignment(trackID: track.id, layerID: layer.id, cell: .inheritDefault)
            }
        }
        .filter { trackIDs.contains($0.trackID) && layerIDs.contains($0.layerID) }

        return PhraseModel(
            id: id,
            name: name,
            lengthBars: max(1, lengthBars),
            stepsPerBar: max(1, stepsPerBar),
            cells: normalizedCells
        )
    }
}

struct PhraseLayerDefinition: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var valueType: PhraseLayerValueType
    var minValue: Double
    var maxValue: Double
    var target: PhraseLayerTarget
    var defaults: [UUID: PhraseCellValue]

    var editorKind: PhraseLayerEditorKind {
        valueType.editorKind
    }

    var availableModes: [PhraseCellEditMode] {
        editorKind.availableModes
    }

    var scalarRange: ClosedRange<Double> {
        minValue...maxValue
    }

    func defaultValue(for trackID: UUID) -> PhraseCellValue {
        defaults[trackID]?.normalized(for: self) ?? valueType.fallbackValue(in: scalarRange)
    }

    func synced(with tracks: [StepSequenceTrack]) -> PhraseLayerDefinition {
        let trackIDs = Set(tracks.map(\.id))
        var normalizedDefaults = defaults.filter { trackIDs.contains($0.key) }
        for track in tracks where normalizedDefaults[track.id] == nil {
            normalizedDefaults[track.id] = Self.defaultValue(for: id, track: track)
        }

        return PhraseLayerDefinition(
            id: id,
            name: name,
            valueType: valueType,
            minValue: minValue,
            maxValue: maxValue,
            target: target,
            defaults: normalizedDefaults
        )
    }

    static func defaultSet(for tracks: [StepSequenceTrack]) -> [PhraseLayerDefinition] {
        let builtins: [(String, String, PhraseLayerValueType, ClosedRange<Double>, PhraseLayerTarget)] = [
            ("pattern", "Pattern", .patternIndex, 0...15, .patternIndex),
            ("mute", "Mute", .boolean, 0...1, .mute),
            ("volume", "Volume", .scalar, 0...127, .macroRow("volume")),
            ("transpose", "Transpose", .scalar, -24...24, .macroRow("transpose")),
            ("intensity", "Intensity", .scalar, 0...1, .macroRow("intensity")),
            ("density", "Density", .scalar, 0...1, .macroRow("density")),
            ("tension", "Tension", .scalar, 0...1, .macroRow("tension")),
            ("register", "Register", .scalar, 0...1, .macroRow("register")),
            ("variance", "Variance", .scalar, 0...1, .macroRow("variance")),
            ("brightness", "Brightness", .scalar, 0...1, .macroRow("brightness")),
            ("fill-flag", "Fill", .boolean, 0...1, .macroRow("fill-flag")),
            ("swing", "Swing", .scalar, 0...1, .macroRow("swing-amount")),
        ]

        let builtinLayers = builtins.map { id, name, valueType, range, target in
            PhraseLayerDefinition(
                id: id,
                name: name,
                valueType: valueType,
                minValue: range.lowerBound,
                maxValue: range.upperBound,
                target: target,
                defaults: Dictionary(uniqueKeysWithValues: tracks.map { track in
                    (track.id, defaultValue(for: id, track: track))
                })
            )
        }
        // Append per-track macro layers after built-ins.
        let macros = macroLayers(for: tracks)
        return builtinLayers + macros
    }

    /// Synthesise phrase layers for all (track, binding) pairs across the given tracks.
    /// Layer id format: `"macro-<trackID>-<bindingID>"` — deterministic and stable.
    static func macroLayers(for tracks: [StepSequenceTrack]) -> [PhraseLayerDefinition] {
        var layers: [PhraseLayerDefinition] = []
        for track in tracks {
            for binding in track.macros {
                let layerID = "macro-\(track.id.uuidString)-\(binding.id.uuidString)"
                let defaults = Dictionary(uniqueKeysWithValues: tracks.map { t -> (UUID, PhraseCellValue) in
                    let value: PhraseCellValue = binding.descriptor.valueType == .boolean
                        ? .bool(binding.descriptor.defaultValue >= 0.5)
                        : .scalar(binding.descriptor.defaultValue)
                    return (t.id, value)
                })
                layers.append(
                    PhraseLayerDefinition(
                        id: layerID,
                        name: binding.descriptor.displayName,
                        valueType: binding.descriptor.valueType,
                        minValue: binding.descriptor.minValue,
                        maxValue: binding.descriptor.maxValue,
                        target: .macroParam(trackID: track.id, bindingID: binding.id),
                        defaults: defaults
                    )
                )
            }
        }
        return layers
    }

    private static func defaultValue(for id: String, track: StepSequenceTrack) -> PhraseCellValue {
        switch id {
        case "pattern":
            return .index(0)
        case "mute":
            return .bool(false)
        case "volume":
            return .scalar(track.mix.level * 127)
        case "transpose",
             "intensity",
             "density",
             "tension",
             "register",
             "variance",
             "brightness",
             "swing":
            return .scalar(0)
        case "fill-flag":
            return .bool(false)
        default:
            fatalError("Unknown built-in phrase layer id: \(id)")
        }
    }
}

enum PhraseLayerValueType: String, Codable, CaseIterable, Equatable, Sendable {
    case boolean
    case scalar
    case patternIndex

    var editorKind: PhraseLayerEditorKind {
        switch self {
        case .boolean:
            return .toggleBoolean
        case .scalar:
            return .continuousScalar
        case .patternIndex:
            return .indexedChoice
        }
    }

    func fallbackValue(in range: ClosedRange<Double>) -> PhraseCellValue {
        switch self {
        case .boolean:
            return .bool(false)
        case .scalar:
            return .scalar(range.lowerBound)
        case .patternIndex:
            return .index(Int(range.lowerBound.rounded()))
        }
    }
}

enum PhraseLayerTarget: Codable, Equatable, Sendable {
    case patternIndex
    case mute
    case macroRow(String)
    case blockParam(String, String)
    case voiceRouteOverride(String)
    /// A track-scoped macro binding.
    /// Different from `.macroRow` (global intensity-like knob keyed by name):
    /// this is per-track, per-binding, and routed through `MacroCoordinator`.
    case macroParam(trackID: UUID, bindingID: UUID)
}

struct PhraseCellAssignment: Codable, Equatable, Sendable {
    var trackID: UUID
    var layerID: String
    var cell: PhraseCell
}

enum PhraseCell: Codable, Equatable, Sendable {
    case inheritDefault
    case single(PhraseCellValue)
    case bars([PhraseCellValue])
    case steps([PhraseCellValue])
    case curve([Double])

    var editMode: PhraseCellEditMode {
        switch self {
        case .inheritDefault:
            return .inheritDefault
        case .single:
            return .single
        case .bars:
            return .bars
        case .steps:
            return .steps
        case .curve:
            return .curve
        }
    }

    static func makeDefault(
        mode: PhraseCellEditMode,
        layer: PhraseLayerDefinition,
        defaultValue: PhraseCellValue,
        stepCount: Int,
        barCount: Int
    ) -> PhraseCell {
        let normalizedValue = defaultValue.normalized(for: layer)
        switch mode {
        case .inheritDefault:
            return .inheritDefault
        case .single:
            return .single(normalizedValue)
        case .bars:
            return .bars(Array(repeating: normalizedValue, count: max(1, barCount)))
        case .steps:
            return .steps(Array(repeating: normalizedValue, count: max(1, stepCount)))
        case .curve:
            let base: Double
            switch normalizedValue {
            case let .scalar(value):
                base = value
            case let .index(index):
                base = Double(index)
            case let .bool(isOn):
                base = isOn ? layer.maxValue : layer.minValue
            }
            return .curve([base, base, base, base])
        }
    }
}

enum PhraseCellValue: Codable, Equatable, Hashable, Sendable {
    case bool(Bool)
    case scalar(Double)
    case index(Int)

    func normalized(for layer: PhraseLayerDefinition) -> PhraseCellValue {
        switch layer.valueType {
        case .boolean:
            switch self {
            case let .bool(value):
                return .bool(value)
            case let .scalar(value):
                return .bool(value >= 0.5)
            case let .index(value):
                return .bool(value != 0)
            }
        case .scalar:
            switch self {
            case let .bool(value):
                return .scalar(value ? layer.maxValue : layer.minValue)
            case let .scalar(value):
                return .scalar(min(max(value, layer.minValue), layer.maxValue))
            case let .index(value):
                return .scalar(min(max(Double(value), layer.minValue), layer.maxValue))
            }
        case .patternIndex:
            switch self {
            case let .bool(value):
                return .index(value ? 1 : 0)
            case let .scalar(value):
                return .index(min(max(Int(value.rounded()), 0), TrackPatternBank.slotCount - 1))
            case let .index(value):
                return .index(min(max(value, 0), TrackPatternBank.slotCount - 1))
            }
        }
    }
}

enum PhraseLayerEditorKind: Equatable, Sendable {
    case toggleBoolean
    case continuousScalar
    case indexedChoice

    var availableModes: [PhraseCellEditMode] {
        switch self {
        case .toggleBoolean, .indexedChoice:
            return [.inheritDefault, .single, .bars]
        case .continuousScalar:
            return [.inheritDefault, .single, .bars, .steps, .curve]
        }
    }
}

enum PhraseCellEditMode: String, Codable, CaseIterable, Equatable, Sendable {
    case inheritDefault
    case single
    case bars
    case steps
    case curve

    var label: String {
        switch self {
        case .inheritDefault:
            return "Inherit"
        case .single:
            return "Single"
        case .bars:
            return "Bars"
        case .steps:
            return "Steps"
        case .curve:
            return "Curve"
        }
    }
}

enum PhraseCurveSampler {
    static func sample(
        points: [Double],
        at stepIndex: Int,
        stepCount: Int,
        range: ClosedRange<Double>
    ) -> Double {
        guard !points.isEmpty else {
            return range.lowerBound
        }
        guard points.count > 1 else {
            return min(max(points[0], range.lowerBound), range.upperBound)
        }

        let normalizedPosition = Double(stepIndex) / Double(max(1, stepCount - 1))
        let segmentPosition = normalizedPosition * Double(points.count - 1)
        let lowerIndex = min(max(Int(segmentPosition.rounded(.down)), 0), points.count - 1)
        let upperIndex = min(lowerIndex + 1, points.count - 1)
        let remainder = segmentPosition - Double(lowerIndex)
        let value = points[lowerIndex] + ((points[upperIndex] - points[lowerIndex]) * remainder)
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct TrackPatternBank: Codable, Equatable, Identifiable, Sendable {
    static let slotCount = 16

    var trackID: UUID
    var slots: [TrackPatternSlot]
    var attachedGeneratorID: UUID?

    var id: UUID { trackID }

    private enum CodingKeys: String, CodingKey {
        case trackID
        case slots
        case attachedGeneratorID
    }

    init(trackID: UUID, slots: [TrackPatternSlot], attachedGeneratorID: UUID? = nil) {
        self.trackID = trackID
        self.slots = TrackPatternBank.normalizedSlots(slots)
        self.attachedGeneratorID = attachedGeneratorID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.trackID = try container.decode(UUID.self, forKey: .trackID)
        let decodedSlots = try container.decode([TrackPatternSlot].self, forKey: .slots)
        self.slots = TrackPatternBank.normalizedSlots(decodedSlots)
        self.attachedGeneratorID = try container.decodeIfPresent(UUID.self, forKey: .attachedGeneratorID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(slots, forKey: .slots)
        try container.encodeIfPresent(attachedGeneratorID, forKey: .attachedGeneratorID)
    }

    func slot(at index: Int) -> TrackPatternSlot {
        slots[min(max(index, 0), Self.slotCount - 1)]
    }

    mutating func setSlot(_ slot: TrackPatternSlot, at index: Int) {
        let clampedIndex = min(max(index, 0), Self.slotCount - 1)
        slots[clampedIndex] = slot.normalized(slotIndex: clampedIndex)
        slots = TrackPatternBank.normalizedSlots(slots)
    }

    func synced(
        track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        let fallbackSourceRef = Self.defaultSourceRef(for: track, generatorPool: generatorPool)
        let validatedAttachedID: UUID? = {
            guard let attachedGeneratorID else { return nil }
            let exists = generatorPool.contains(where: { $0.id == attachedGeneratorID && $0.trackType == track.trackType })
            return exists ? attachedGeneratorID : nil
        }()
        return TrackPatternBank(
            trackID: trackID,
            slots: slots.enumerated().map { index, slot in
                slot.normalized(
                    slotIndex: index,
                    trackType: track.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool,
                    fallbackSourceRef: fallbackSourceRef
                )
            },
            attachedGeneratorID: validatedAttachedID
        )
    }

    static func `default`(
        for track: StepSequenceTrack,
        initialClipID: UUID?
    ) -> TrackPatternBank {
        let seededRef = SourceRef(mode: .clip, generatorID: nil, clipID: initialClipID)
        let emptyRef = SourceRef(mode: .clip, generatorID: nil, clipID: nil)
        return TrackPatternBank(
            trackID: track.id,
            slots: (0..<slotCount).map { index in
                TrackPatternSlot(slotIndex: index, sourceRef: index == 0 ? seededRef : emptyRef)
            },
            attachedGeneratorID: nil
        )
    }

    private static func normalizedSlots(_ slots: [TrackPatternSlot]) -> [TrackPatternSlot] {
        (0..<slotCount).map { index in
            slots.first(where: { $0.slotIndex == index })?.normalized(slotIndex: index)
                ?? TrackPatternSlot(slotIndex: index, sourceRef: .generator(nil))
        }
    }

    private static func defaultSourceRef(
        for track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry]
    ) -> SourceRef {
        .generator(generatorPool.first(where: { $0.trackType == track.trackType })?.id)
    }
}

struct TrackPatternSlot: Codable, Equatable, Identifiable, Sendable {
    var slotIndex: Int
    var name: String?
    var sourceRef: SourceRef

    var id: Int { slotIndex }

    init(slotIndex: Int, name: String? = nil, sourceRef: SourceRef) {
        self.slotIndex = slotIndex
        self.name = name
        self.sourceRef = sourceRef
    }

    func normalized(slotIndex: Int) -> TrackPatternSlot {
        TrackPatternSlot(slotIndex: slotIndex, name: normalizedName, sourceRef: sourceRef)
    }

    func normalized(
        slotIndex: Int,
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry],
        fallbackSourceRef: SourceRef
    ) -> TrackPatternSlot {
        let normalizedSourceRef = sourceRef.normalized(
            trackType: trackType,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
        let resolvedSourceRef: SourceRef = {
            switch normalizedSourceRef.mode {
            case .generator:
                return normalizedSourceRef.isEmpty ? fallbackSourceRef : normalizedSourceRef
            case .clip:
                // Empty clip slots are valid in the lazy per-pattern model.
                return normalizedSourceRef
            }
        }()
        return TrackPatternSlot(
            slotIndex: slotIndex,
            name: normalizedName,
            sourceRef: resolvedSourceRef
        )
    }

    private var normalizedName: String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

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
        _ = trackType
        return [.generator, .clip]
    }
}

enum GeneratorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case monoGenerator
    case polyGenerator
    case sliceGenerator

    var label: String {
        switch self {
        case .monoGenerator:
            return "Mono Generator"
        case .polyGenerator:
            return "Poly Generator"
        case .sliceGenerator:
            return "Slice Generator"
        }
    }

    var compatibleWith: Set<TrackType> {
        switch self {
        case .monoGenerator:
            return [.monoMelodic]
        case .polyGenerator:
            return [.polyMelodic]
        case .sliceGenerator:
            return [.slice]
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
                pitches: [.native(.init(
                    algo: .manual(pitches: [60, 64, 67], pickMode: .random),
                    harmonicSidechain: .none
                ))],
                shape: .default
            )
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
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4") ?? UUID(),
            name: "Slice Trigger",
            kind: .sliceGenerator,
            trackType: .slice
        )
    ]
}

struct ClipPoolEntry: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var content: ClipContent
    /// Per-step macro overrides keyed by binding descriptor id.
    /// A missing key means no lane exists for that binding (defer to phrase layer / default).
    /// Legacy docs without this field decode as empty — no migration needed.
    var macroLanes: [UUID: MacroLane]

    init(id: UUID, name: String, trackType: TrackType, content: ClipContent, macroLanes: [UUID: MacroLane] = [:]) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.content = content
        self.macroLanes = macroLanes
    }

    /// Drop lanes for removed bindings and resize remaining lanes to match step count.
    func synced(with macros: [TrackMacroBinding], stepCount: Int) -> ClipPoolEntry {
        let validIDs = Set(macros.map(\.id))
        let syncedLanes = macroLanes
            .filter { validIDs.contains($0.key) }
            .mapValues { $0.synced(stepCount: stepCount) }
        return ClipPoolEntry(id: id, name: name, trackType: trackType, content: content, macroLanes: syncedLanes)
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
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3") ?? UUID(),
            name: "Slice Lane",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: [true, false, false, true, false, false, true, false, true, false, false, true, false, true, false, false],
                sliceIndexes: [0, 2, 4, 5]
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
        // macroLanes is not Hashable (values are [Double?]) — use id as primary hash.
    }
}

extension ClipPoolEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case trackType
        case content
        case macroLanes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackType = try container.decode(TrackType.self, forKey: .trackType)
        content = try container.decode(ClipContent.self, forKey: .content)
        // Legacy docs without macroLanes decode as empty — no migration needed.
        macroLanes = try container.decodeIfPresent([UUID: MacroLane].self, forKey: .macroLanes) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackType, forKey: .trackType)
        try container.encode(content, forKey: .content)
        try container.encode(macroLanes, forKey: .macroLanes)
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
        case let .sliceTriggers(_, sliceIndexes):
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
    var modifierGeneratorID: UUID?
    var modifierBypassed: Bool

    private enum CodingKeys: String, CodingKey {
        case mode
        case generatorID
        case clipID
        case modifierGeneratorID
        case modifierBypassed
    }

    init(
        mode: TrackSourceMode,
        generatorID: UUID? = nil,
        clipID: UUID? = nil,
        modifierGeneratorID: UUID? = nil,
        modifierBypassed: Bool = false
    ) {
        self.mode = mode
        self.generatorID = generatorID
        self.clipID = clipID
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
            $0.id == modifierGeneratorID && $0.trackType == trackType
        })?.id

        switch mode {
        case .generator:
            return SourceRef(
                mode: .generator,
                generatorID: compatibleSourceGeneratorID,
                clipID: clipID,
                modifierGeneratorID: compatibleModifierGeneratorID,
                modifierBypassed: compatibleModifierGeneratorID == nil ? false : modifierBypassed
            )
        case .clip:
            guard let clipID else {
                return SourceRef(
                    mode: .clip,
                    generatorID: compatibleSourceGeneratorID,
                    clipID: nil,
                    modifierGeneratorID: compatibleModifierGeneratorID,
                    modifierBypassed: compatibleModifierGeneratorID == nil ? false : modifierBypassed
                )
            }
            let compatibleID = clipPool.first(where: { $0.id == clipID && $0.trackType == trackType })?.id
            return SourceRef(
                mode: .clip,
                generatorID: compatibleSourceGeneratorID,
                clipID: compatibleID,
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
            modifierGeneratorID: resolvedModifierID,
            modifierBypassed: modifierBypassed
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(generatorID, forKey: .generatorID)
        try container.encodeIfPresent(clipID, forKey: .clipID)
        if let modifierGeneratorID {
            try container.encode(modifierGeneratorID, forKey: .modifierGeneratorID)
        } else {
            try container.encodeNil(forKey: .modifierGeneratorID)
        }
        try container.encode(modifierBypassed, forKey: .modifierBypassed)
    }
}
