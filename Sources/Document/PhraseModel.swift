import Foundation

struct PhraseModel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var lengthBars: Int
    var stepsPerBar: Int
    var abstractRows: [PhraseAbstractRow]
    var trackPatternIndexes: [UUID: Int]
    var trackLayerStates: [PhraseTrackLayerStateGroup]

    var legacySourceRefs: [PhraseTrackSourceAssignment]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case lengthBars
        case stepsPerBar
        case abstractRows
        case trackPatternIndexes
        case sourceRefs
        case trackLayerStates
    }

    init(
        id: UUID,
        name: String,
        lengthBars: Int,
        stepsPerBar: Int,
        abstractRows: [PhraseAbstractRow],
        trackPatternIndexes: [UUID: Int],
        trackLayerStates: [PhraseTrackLayerStateGroup],
        legacySourceRefs: [PhraseTrackSourceAssignment] = []
    ) {
        self.id = id
        self.name = name
        self.lengthBars = lengthBars
        self.stepsPerBar = stepsPerBar
        self.abstractRows = abstractRows
        self.trackPatternIndexes = trackPatternIndexes
        self.trackLayerStates = trackLayerStates
        self.legacySourceRefs = legacySourceRefs
    }

    static func == (lhs: PhraseModel, rhs: PhraseModel) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.lengthBars == rhs.lengthBars &&
            lhs.stepsPerBar == rhs.stepsPerBar &&
            lhs.abstractRows == rhs.abstractRows &&
            lhs.trackPatternIndexes == rhs.trackPatternIndexes &&
            lhs.trackLayerStates == rhs.trackLayerStates
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
            trackPatternIndexes: defaultPatternIndexes(for: tracks),
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
        let decodedPatternIndexes = try container.decodeIfPresent([String: Int].self, forKey: .trackPatternIndexes) ?? [:]
        trackPatternIndexes = Dictionary(
            uniqueKeysWithValues: decodedPatternIndexes.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            }
        )
        legacySourceRefs = try container.decodeIfPresent([PhraseTrackSourceAssignment].self, forKey: .sourceRefs) ?? []
        trackLayerStates = try container.decodeIfPresent([PhraseTrackLayerStateGroup].self, forKey: .trackLayerStates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lengthBars, forKey: .lengthBars)
        try container.encode(stepsPerBar, forKey: .stepsPerBar)
        try container.encode(abstractRows, forKey: .abstractRows)
        let encodedPatternIndexes = Dictionary(
            uniqueKeysWithValues: trackPatternIndexes.map { ($0.key.uuidString, $0.value) }
        )
        try container.encode(encodedPatternIndexes, forKey: .trackPatternIndexes)
        try container.encode(trackLayerStates, forKey: .trackLayerStates)
    }

    func patternIndex(for trackID: UUID) -> Int {
        min(max(trackPatternIndexes[trackID] ?? 0, 0), TrackPatternBank.slotCount - 1)
    }

    mutating func setPatternIndex(_ index: Int, for trackID: UUID) {
        trackPatternIndexes[trackID] = min(max(index, 0), TrackPatternBank.slotCount - 1)
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

    mutating func setAbstractValue(for kind: PhraseAbstractKind, at index: Int, value: Double) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }),
              abstractRows[rowIndex].values.indices.contains(index)
        else {
            return
        }
        abstractRows[rowIndex].values[index] = min(max(value, 0), 1)
    }

    mutating func setAbstractUniformValue(for kind: PhraseAbstractKind, value: Double) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        let normalized = min(max(value, 0), 1)
        abstractRows[rowIndex].values = Array(repeating: normalized, count: abstractRows[rowIndex].values.count)
    }

    mutating func setAbstractBarValue(
        for kind: PhraseAbstractKind,
        barIndex: Int,
        value: Double
    ) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }

        let start = max(0, barIndex) * stepsPerBar
        let end = min(abstractRows[rowIndex].values.count, start + stepsPerBar)
        guard start < end else {
            return
        }

        let normalized = min(max(value, 0), 1)
        for index in start..<end {
            abstractRows[rowIndex].values[index] = normalized
        }
    }

    mutating func setAbstractValues(for kind: PhraseAbstractKind, values: [Double]) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }

        let stepCount = abstractRows[rowIndex].values.count
        let normalized = Array(values.prefix(stepCount)).map { min(max($0, 0), 1) }
        abstractRows[rowIndex].values = normalized + Array(repeating: 0, count: max(0, stepCount - normalized.count))
    }

    mutating func setAbstractRowSourceMode(_ mode: PhraseRowSourceMode, for kind: PhraseAbstractKind) {
        guard let rowIndex = abstractRows.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        abstractRows[rowIndex].sourceMode = mode
    }

    func synced(with tracks: [StepSequenceTrack]) -> PhraseModel {
        let normalizedStepCount = max(1, lengthBars * stepsPerBar)
        let normalizedRows = PhraseAbstractKind.allCases.map { kind in
            let row = abstractRows.first(where: { $0.kind == kind }) ?? PhraseAbstractRow(kind: kind, values: [])
            return row.normalized(stepCount: normalizedStepCount)
        }

        let trackIDs = Set(tracks.map(\.id))
        var normalizedPatternIndexes = trackPatternIndexes
            .filter { trackIDs.contains($0.key) }
            .mapValues { min(max($0, 0), TrackPatternBank.slotCount - 1) }

        for track in tracks where normalizedPatternIndexes[track.id] == nil {
            normalizedPatternIndexes[track.id] = 0
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

        let normalizedLegacySourceRefs = legacySourceRefs
            .filter { trackIDs.contains($0.trackID) }
            .sorted { lhs, rhs in
                tracks.firstIndex(where: { $0.id == lhs.trackID }) ?? 0 <
                    tracks.firstIndex(where: { $0.id == rhs.trackID }) ?? 0
            }

        return PhraseModel(
            id: id,
            name: name,
            lengthBars: max(1, lengthBars),
            stepsPerBar: max(1, stepsPerBar),
            abstractRows: normalizedRows,
            trackPatternIndexes: normalizedPatternIndexes,
            trackLayerStates: normalizedLayerStates,
            legacySourceRefs: normalizedLegacySourceRefs
        )
    }

    private static func defaultPatternIndexes(for tracks: [StepSequenceTrack]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, 0) })
    }

    private static func defaultLayerStateGroups(for tracks: [StepSequenceTrack]) -> [PhraseTrackLayerStateGroup] {
        tracks.map { PhraseTrackLayerStateGroup(trackID: $0.id) }
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

    init(trackID: UUID, sourceRef: SourceRef) {
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

struct TrackPatternBank: Codable, Equatable, Identifiable, Sendable {
    static let slotCount = 16

    var trackID: UUID
    var slots: [TrackPatternSlot]

    var id: UUID { trackID }

    init(trackID: UUID, slots: [TrackPatternSlot]) {
        self.trackID = trackID
        self.slots = TrackPatternBank.normalizedSlots(slots)
    }

    func slot(at index: Int) -> TrackPatternSlot {
        let clampedIndex = min(max(index, 0), Self.slotCount - 1)
        return slots[clampedIndex]
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
        TrackPatternBank(
            trackID: trackID,
            slots: slots.enumerated().map { index, slot in
                slot.normalized(
                    slotIndex: index,
                    trackType: track.trackType,
                    generatorPool: generatorPool,
                    clipPool: clipPool,
                    fallbackSourceRef: Self.defaultSourceRef(for: track, generatorPool: generatorPool)
                )
            }
        )
    }

    static func `default`(
        for track: StepSequenceTrack,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> TrackPatternBank {
        let defaultSourceRef = defaultSourceRef(for: track, generatorPool: generatorPool)
        return TrackPatternBank(
            trackID: track.id,
            slots: (0..<slotCount).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: defaultSourceRef)
            }
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
        TrackPatternSlot(
            slotIndex: slotIndex,
            name: normalizedName,
            sourceRef: sourceRef
        )
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
        return TrackPatternSlot(
            slotIndex: slotIndex,
            name: normalizedName,
            sourceRef: normalizedSourceRef.isEmpty ? fallbackSourceRef : normalizedSourceRef
        )
    }

    private var normalizedName: String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
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

    var editorKind: PhraseLayerEditorKind {
        switch self {
        case .intensity, .density, .register, .tension, .variance, .brightness:
            return .continuousScalar
        }
    }

    var availableCellModes: [PhraseCellEditMode] {
        editorKind.availableModes
    }
}

enum PhraseLayerEditorKind: Equatable, Sendable {
    case toggleBoolean
    case continuousScalar
    case indexedChoice

    var label: String {
        switch self {
        case .toggleBoolean:
            return "Toggle"
        case .continuousScalar:
            return "Scalar"
        case .indexedChoice:
            return "Indexed"
        }
    }

    var availableModes: [PhraseCellEditMode] {
        switch self {
        case .toggleBoolean:
            return [.single, .perBar]
        case .continuousScalar:
            return [.single, .rampUp, .perBar, .drawn]
        case .indexedChoice:
            return [.single, .perBar]
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

    var detail: String {
        switch self {
        case .generator:
            return "Pattern points at a project-scoped generator instance."
        case .clip:
            return "Pattern points at a stored clip in the shared clip pool."
        }
    }

    var isImplemented: Bool {
        self == .generator
    }

    static func available(for trackType: TrackType) -> [TrackSourceMode] {
        _ = trackType
        return [.generator, .clip]
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

struct SourceRef: Codable, Equatable, Hashable, Sendable {
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

    var isEmpty: Bool {
        switch mode {
        case .generator:
            return generatorID == nil
        case .clip:
            return false
        }
    }

    func normalized(
        trackType: TrackType,
        generatorPool: [GeneratorPoolEntry],
        clipPool: [ClipPoolEntry]
    ) -> SourceRef {
        switch mode {
        case .generator:
            let compatibleID = generatorPool.first(where: { $0.id == generatorID && $0.trackType == trackType })?.id
                ?? generatorPool.first(where: { $0.trackType == trackType })?.id
            return .generator(compatibleID)
        case .clip:
            let compatibleID = clipPool.first(where: { $0.id == clipID && $0.trackType == trackType })?.id
                ?? clipPool.first(where: { $0.trackType == trackType })?.id
            return .clip(compatibleID)
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
        case .manualMono, .generator, .template, .midiIn:
            return .generator
        case .clipReader, .clip:
            return .clip
        }
    }
}
