import Foundation

struct PhraseModel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var lengthBars: Int
    var stepsPerBar: Int
    var abstractRows: [PhraseAbstractRow]
    var sourceRefs: [PhraseTrackSourceAssignment]
    var trackLayerStates: [PhraseTrackLayerStateGroup]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case lengthBars
        case stepsPerBar
        case abstractRows
        case sourceRefs
        case trackLayerStates
    }

    init(
        id: UUID,
        name: String,
        lengthBars: Int,
        stepsPerBar: Int,
        abstractRows: [PhraseAbstractRow],
        sourceRefs: [PhraseTrackSourceAssignment],
        trackLayerStates: [PhraseTrackLayerStateGroup]
    ) {
        self.id = id
        self.name = name
        self.lengthBars = lengthBars
        self.stepsPerBar = stepsPerBar
        self.abstractRows = abstractRows
        self.sourceRefs = sourceRefs
        self.trackLayerStates = trackLayerStates
    }

    static func `default`(
        tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = []
    ) -> PhraseModel {
        let defaultBars = 8
        let defaultStepsPerBar = 16
        let stepCount = defaultBars * defaultStepsPerBar

        return PhraseModel(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            name: "Phrase A",
            lengthBars: defaultBars,
            stepsPerBar: defaultStepsPerBar,
            abstractRows: PhraseAbstractKind.allCases.map {
                PhraseAbstractRow(kind: $0, values: Array(repeating: 0, count: stepCount))
            },
            sourceRefs: defaultSourceAssignments(for: tracks, generatorPool: generatorPool, clipPool: clipPool),
            trackLayerStates: defaultLayerStateGroups(for: tracks)
        )
    }

    var stepCount: Int {
        max(1, lengthBars * stepsPerBar)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lengthBars = try container.decode(Int.self, forKey: .lengthBars)
        stepsPerBar = try container.decode(Int.self, forKey: .stepsPerBar)
        abstractRows = try container.decode([PhraseAbstractRow].self, forKey: .abstractRows)
        sourceRefs = try container.decodeIfPresent([PhraseTrackSourceAssignment].self, forKey: .sourceRefs) ?? []
        trackLayerStates = try container.decodeIfPresent([PhraseTrackLayerStateGroup].self, forKey: .trackLayerStates) ?? []
    }

    func sourceRef(for trackID: UUID) -> SourceRef {
        sourceRefs.first(where: { $0.trackID == trackID })?.sourceRef ?? .generator(nil as UUID?)
    }

    func sourceMode(for trackID: UUID) -> TrackSourceMode {
        sourceRef(for: trackID).mode
    }

    mutating func setSourceRef(_ sourceRef: SourceRef, for trackID: UUID) {
        if let existingIndex = sourceRefs.firstIndex(where: { $0.trackID == trackID }) {
            sourceRefs[existingIndex].sourceRef = sourceRef
        } else {
            sourceRefs.append(
                PhraseTrackSourceAssignment(trackID: trackID, sourceRef: sourceRef)
            )
        }
    }

    mutating func setSourceMode(
        _ mode: TrackSourceMode,
        for trackID: UUID,
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) {
        setSourceRef(
            Self.defaultSourceRef(
                for: mode,
                trackType: trackType,
                generatorPool: generatorPool,
                clipPool: clipPool
            ),
            for: trackID
        )
    }

    func instrumentSource(for trackID: UUID) -> TrackSourceMode {
        sourceMode(for: trackID)
    }

    mutating func setInstrumentSource(
        _ source: TrackSourceMode,
        for trackID: UUID,
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) {
        setSourceMode(
            source,
            for: trackID,
            trackType: trackType,
            generatorPool: generatorPool,
            clipPool: clipPool
        )
    }

    func cellMode(for kind: PhraseAbstractKind, trackID: UUID) -> PhraseCellEditMode {
        trackLayerStates.first(where: { $0.trackID == trackID })?.cellMode(for: kind) ?? .single
    }

    mutating func setCellMode(_ mode: PhraseCellEditMode, for kind: PhraseAbstractKind, trackID: UUID) {
        if let existingIndex = trackLayerStates.firstIndex(where: { $0.trackID == trackID }) {
            trackLayerStates[existingIndex].setCellMode(mode, for: kind)
        } else {
            var group = PhraseTrackLayerStateGroup(trackID: trackID)
            group.setCellMode(mode, for: kind)
            trackLayerStates.append(group)
        }
    }

    mutating func cycleAbstractValue(for kind: PhraseAbstractKind, at index: Int) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        abstractRows[rowIndex].cycleValue(at: index)
    }

    mutating func setAbstractRowSourceMode(_ mode: PhraseRowSourceMode, for kind: PhraseAbstractKind) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        abstractRows[rowIndex].sourceMode = mode
    }

    func synced(
        with tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = []
    ) -> PhraseModel {
        let normalizedStepCount = max(1, lengthBars * stepsPerBar)
        let normalizedRows = PhraseAbstractKind.allCases.map { kind in
            let row = abstractRows.first(where: { $0.kind == kind }) ?? PhraseAbstractRow(kind: kind, values: [])
            return row.normalized(stepCount: normalizedStepCount)
        }

        let trackIDs = Set(tracks.map(\.id))

        var normalizedSourceRefs = sourceRefs
            .filter { trackIDs.contains($0.trackID) }
        let existingIDs = Set(normalizedSourceRefs.map(\.trackID))
        let missingIDs = trackIDs.subtracting(existingIDs)
        normalizedSourceRefs.append(
            contentsOf: missingIDs.compactMap { trackID in
                guard let track = tracks.first(where: { $0.id == trackID }) else {
                    return nil
                }
                return PhraseTrackSourceAssignment(
                    trackID: trackID,
                    sourceRef: Self.defaultSourceRef(
                        for: .generator,
                        trackType: track.trackType,
                        generatorPool: generatorPool,
                        clipPool: clipPool
                    )
                )
            }
        )
        normalizedSourceRefs = normalizedSourceRefs.map { assignment in
            guard let track = tracks.first(where: { $0.id == assignment.trackID }) else {
                return assignment
            }
            return assignment.normalized(
                trackType: track.trackType,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
        }
        normalizedSourceRefs.sort { lhs, rhs in
            tracks.firstIndex(where: { $0.id == lhs.trackID }) ?? 0 <
                tracks.firstIndex(where: { $0.id == rhs.trackID }) ?? 0
        }

        var normalizedLayerStates = trackLayerStates
            .filter { trackIDs.contains($0.trackID) }
            .map(\.normalized)
        let existingLayerIDs = Set(normalizedLayerStates.map(\.trackID))
        let missingLayerIDs = trackIDs.subtracting(existingLayerIDs)
        normalizedLayerStates.append(contentsOf: missingLayerIDs.map { PhraseTrackLayerStateGroup(trackID: $0) })
        normalizedLayerStates.sort { lhs, rhs in
            tracks.firstIndex(where: { $0.id == lhs.trackID }) ?? 0 <
                tracks.firstIndex(where: { $0.id == rhs.trackID }) ?? 0
        }

        return PhraseModel(
            id: id,
            name: name,
            lengthBars: max(1, lengthBars),
            stepsPerBar: max(1, stepsPerBar),
            abstractRows: normalizedRows,
            sourceRefs: normalizedSourceRefs,
            trackLayerStates: normalizedLayerStates
        )
    }

    private static func defaultSourceAssignments(
        for tracks: [StepSequenceTrack],
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> [PhraseTrackSourceAssignment] {
        tracks.map {
            PhraseTrackSourceAssignment(
                trackID: $0.id,
                sourceRef: defaultSourceRef(
                    for: .generator,
                    trackType: $0.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool
                )
            )
        }
    }

    private static func defaultLayerStateGroups(for tracks: [StepSequenceTrack]) -> [PhraseTrackLayerStateGroup] {
        tracks.map { PhraseTrackLayerStateGroup(trackID: $0.id) }
    }

    private static func defaultSourceRef(
        for mode: TrackSourceMode,
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> SourceRef {
        switch mode {
        case .generator:
            let generatorID = generatorPool.first(where: { $0.trackType == trackType })?.id
            return .generator(generatorID)
        case .clip:
            let clipID = clipPool.first(where: { $0.trackType == trackType })?.id
            return .clip(clipID)
        case .template:
            return .template
        case .midiIn:
            return .midiIn
        }
    }
}

struct PhraseAbstractRow: Codable, Equatable, Sendable {
    var kind: PhraseAbstractKind
    var sourceMode: PhraseRowSourceMode
    var values: [Double]

    init(kind: PhraseAbstractKind, sourceMode: PhraseRowSourceMode = .authored, values: [Double]) {
        self.kind = kind
        self.sourceMode = sourceMode
        self.values = values.map { min(max($0, 0), 1) }
    }

    mutating func cycleValue(at index: Int) {
        guard values.indices.contains(index) else {
            return
        }

        let nextValue: Double
        switch values[index] {
        case ..<0.25:
            nextValue = 0.33
        case ..<0.5:
            nextValue = 0.66
        case ..<0.83:
            nextValue = 1.0
        default:
            nextValue = 0.0
        }

        values[index] = nextValue
    }

    func normalized(stepCount: Int) -> PhraseAbstractRow {
        let clampedValues = values.map { min(max($0, 0), 1) }
        if clampedValues.count == stepCount {
            return PhraseAbstractRow(kind: kind, sourceMode: sourceMode, values: clampedValues)
        }

        let resized = Array(clampedValues.prefix(stepCount)) + Array(repeating: 0, count: max(0, stepCount - clampedValues.count))
        return PhraseAbstractRow(kind: kind, sourceMode: sourceMode, values: resized)
    }
}

struct PhraseTrackSourceAssignment: Codable, Equatable, Identifiable, Sendable {
    var trackID: UUID
    var sourceRef: SourceRef

    private enum CodingKeys: String, CodingKey {
        case trackID
        case sourceRef
        case instrumentSource
    }

    init(
        trackID: UUID,
        sourceRef: SourceRef
    ) {
        self.trackID = trackID
        self.sourceRef = sourceRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decode(UUID.self, forKey: .trackID)
        if let decodedSourceRef = try container.decodeIfPresent(SourceRef.self, forKey: .sourceRef) {
            sourceRef = decodedSourceRef
        } else {
            let legacySource = try container.decodeIfPresent(LegacyPhraseSource.self, forKey: .instrumentSource) ?? .generator
            sourceRef = SourceRef(mode: legacySource.trackSourceMode)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(sourceRef, forKey: .sourceRef)
    }

    var id: UUID { trackID }

    func normalized(
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> PhraseTrackSourceAssignment {
        PhraseTrackSourceAssignment(
            trackID: trackID,
            sourceRef: sourceRef.normalized(
                trackType: trackType,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
        )
    }
}

struct PhraseTrackLayerStateGroup: Codable, Equatable, Identifiable, Sendable {
    var trackID: UUID
    var layerStates: [PhraseTrackLayerState]

    init(trackID: UUID, layerStates: [PhraseTrackLayerState] = PhraseTrackLayerState.defaults()) {
        self.trackID = trackID
        self.layerStates = PhraseTrackLayerState.normalized(layerStates)
    }

    var id: UUID { trackID }

    func cellMode(for kind: PhraseAbstractKind) -> PhraseCellEditMode {
        layerStates.first(where: { $0.kind == kind })?.cellMode ?? .single
    }

    mutating func setCellMode(_ mode: PhraseCellEditMode, for kind: PhraseAbstractKind) {
        if let index = layerStates.firstIndex(where: { $0.kind == kind }) {
            layerStates[index].cellMode = mode
        } else {
            layerStates.append(PhraseTrackLayerState(kind: kind, cellMode: mode))
        }
        layerStates = PhraseTrackLayerState.normalized(layerStates)
    }

    var normalized: PhraseTrackLayerStateGroup {
        PhraseTrackLayerStateGroup(trackID: trackID, layerStates: PhraseTrackLayerState.normalized(layerStates))
    }
}

struct PhraseTrackLayerState: Codable, Equatable, Identifiable, Sendable {
    var kind: PhraseAbstractKind
    var cellMode: PhraseCellEditMode

    var id: PhraseAbstractKind { kind }

    static func defaults() -> [PhraseTrackLayerState] {
        PhraseAbstractKind.allCases.map {
            PhraseTrackLayerState(kind: $0, cellMode: .single)
        }
    }

    static func normalized(_ states: [PhraseTrackLayerState]) -> [PhraseTrackLayerState] {
        PhraseAbstractKind.allCases.map { kind in
            states.first(where: { $0.kind == kind }) ?? PhraseTrackLayerState(kind: kind, cellMode: .single)
        }
    }
}

enum PhraseAbstractKind: String, Codable, CaseIterable, Equatable, Sendable {
    case intensity
    case density
    case register
    case tension
    case variance
    case brightness

    var label: String {
        rawValue.capitalized
    }

    var accentName: String {
        switch self {
        case .intensity, .density:
            return "cyan"
        case .register, .brightness:
            return "violet"
        case .tension, .variance:
            return "amber"
        }
    }
}

enum PhraseCellEditMode: String, Codable, CaseIterable, Equatable, Sendable {
    case single
    case perBar
    case rampUp
    case drawn

    var label: String {
        switch self {
        case .single:
            return "Single"
        case .perBar:
            return "Per Bar"
        case .rampUp:
            return "Ramp Up"
        case .drawn:
            return "Drawn"
        }
    }

    var shortLabel: String {
        switch self {
        case .single:
            return "Single"
        case .perBar:
            return "Bars"
        case .rampUp:
            return "Ramp"
        case .drawn:
            return "Drawn"
        }
    }

    var detail: String {
        switch self {
        case .single:
            return "One phrase-wide value, with later rows inheriting when left empty."
        case .perBar:
            return "Per-bar steps for phrase-length variation without freehand drawing."
        case .rampUp:
            return "A shaped rise across the phrase, useful for tension or density lifts."
        case .drawn:
            return "A freely authored lane for the eventual curve and event editor."
        }
    }
}

enum PhraseRowSourceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case authored
    case generated

    var label: String {
        switch self {
        case .authored:
            return "Authored"
        case .generated:
            return "Generated"
        }
    }
}

enum TrackSourceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case generator
    case clip
    case template
    case midiIn

    var label: String {
        switch self {
        case .generator:
            return "Generator"
        case .clip:
            return "Clip"
        case .template:
            return "Template"
        case .midiIn:
            return "MIDI In"
        }
    }

    var shortLabel: String {
        switch self {
        case .generator:
            return "Gen"
        case .clip:
            return "Clip"
        case .template:
            return "Template"
        case .midiIn:
            return "MIDI In"
        }
    }

    var detail: String {
        switch self {
        case .generator:
            return "Phrase points at a project-scoped generator instance."
        case .clip:
            return "Frozen or authored phrase clip"
        case .template:
            return "Template-backed starting point"
        case .midiIn:
            return "External MIDI capture and monitoring"
        }
    }

    var isImplemented: Bool {
        self == .generator
    }

    static func available(for trackType: TrackType) -> [TrackSourceMode] {
        switch trackType {
        case .instrument:
            return [.generator, .clip, .template, .midiIn]
        case .drumRack:
            return [.generator, .clip, .template]
        case .sliceLoop:
            return [.generator, .clip]
        }
    }
}

enum GeneratorKind: String, Codable, CaseIterable, Equatable, Sendable {
    case manualMono
    case drumPattern
    case sliceTrigger

    var label: String {
        switch self {
        case .manualMono:
            return "Manual Mono"
        case .drumPattern:
            return "Drum Pattern"
        case .sliceTrigger:
            return "Slice Trigger"
        }
    }
}

struct GeneratorPoolEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var kind: GeneratorKind

    static let defaultPool: [GeneratorPoolEntry] = [
        GeneratorPoolEntry(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1") ?? UUID(),
            name: "Manual Mono",
            trackType: .instrument,
            kind: .manualMono
        ),
        GeneratorPoolEntry(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2") ?? UUID(),
            name: "Drum Pattern",
            trackType: .drumRack,
            kind: .drumPattern
        ),
        GeneratorPoolEntry(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3") ?? UUID(),
            name: "Slice Trigger",
            trackType: .sliceLoop,
            kind: .sliceTrigger
        )
    ]
}

struct ClipPoolEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trackType: TrackType
}

struct SourceRef: Codable, Equatable, Sendable {
    var mode: TrackSourceMode
    var generatorID: UUID?
    var clipID: UUID?

    init(mode: TrackSourceMode, generatorID: UUID? = nil, clipID: UUID? = nil) {
        self.mode = mode
        self.generatorID = generatorID
        self.clipID = clipID
    }

    static func generator(_ id: UUID?) -> SourceRef {
        SourceRef(mode: .generator, generatorID: id)
    }

    static func clip(_ id: UUID?) -> SourceRef {
        SourceRef(mode: .clip, clipID: id)
    }

    static let template = SourceRef(mode: .template)
    static let midiIn = SourceRef(mode: .midiIn)

    func normalized(
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> SourceRef {
        switch mode {
        case .generator:
            let compatibleID = generatorPool.first(where: { $0.id == generatorID && $0.trackType == trackType })?.id
                ?? generatorPool.first(where: { $0.trackType == trackType })?.id
            return .generator(compatibleID as UUID?)
        case .clip:
            let compatibleID = clipPool.first(where: { $0.id == clipID && $0.trackType == trackType })?.id
                ?? clipPool.first(where: { $0.trackType == trackType })?.id
            return .clip(compatibleID as UUID?)
        case .template:
            return .template
        case .midiIn:
            let fallbackGeneratorID = generatorPool.first(where: { $0.trackType == trackType })?.id
            return trackType == .instrument ? .midiIn : .generator(fallbackGeneratorID as UUID?)
        }
    }
}

private enum LegacyPhraseSource: String, Codable {
    case manualMono
    case clipReader
    case template
    case midiIn
    case generator
    case clip

    var trackSourceMode: TrackSourceMode {
        switch self {
        case .manualMono, .generator:
            return .generator
        case .clipReader, .clip:
            return .clip
        case .template:
            return .template
        case .midiIn:
            return .midiIn
        }
    }
}
