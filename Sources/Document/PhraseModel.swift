import Foundation

struct PhraseModel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var lengthBars: Int
    var stepsPerBar: Int
    var abstractRows: [PhraseAbstractRow]
    var trackPipelines: [PhraseTrackPipeline]

    static func `default`(tracks: [StepSequenceTrack]) -> PhraseModel {
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
            trackPipelines: defaultPipelines(for: tracks)
        )
    }

    var stepCount: Int {
        max(1, lengthBars * stepsPerBar)
    }

    func instrumentSource(for trackID: UUID) -> PhraseInstrumentSource {
        trackPipelines.first(where: { $0.trackID == trackID })?.instrumentSource ?? .manualMono
    }

    mutating func setInstrumentSource(_ source: PhraseInstrumentSource, for trackID: UUID) {
        if let existingIndex = trackPipelines.firstIndex(where: { $0.trackID == trackID }) {
            trackPipelines[existingIndex].instrumentSource = source
        } else {
            trackPipelines.append(
                PhraseTrackPipeline(trackID: trackID, instrumentSource: source)
            )
        }
    }

    func cellMode(for kind: PhraseAbstractKind, trackID: UUID) -> PhraseCellEditMode {
        trackPipelines.first(where: { $0.trackID == trackID })?.cellMode(for: kind) ?? .single
    }

    mutating func setCellMode(_ mode: PhraseCellEditMode, for kind: PhraseAbstractKind, trackID: UUID) {
        if let existingIndex = trackPipelines.firstIndex(where: { $0.trackID == trackID }) {
            trackPipelines[existingIndex].setCellMode(mode, for: kind)
        } else {
            var pipeline = PhraseTrackPipeline(trackID: trackID, instrumentSource: .manualMono)
            pipeline.setCellMode(mode, for: kind)
            trackPipelines.append(pipeline)
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

    func synced(with tracks: [StepSequenceTrack]) -> PhraseModel {
        let normalizedStepCount = max(1, lengthBars * stepsPerBar)
        let normalizedRows = PhraseAbstractKind.allCases.map { kind in
            let row = abstractRows.first(where: { $0.kind == kind }) ?? PhraseAbstractRow(kind: kind, values: [])
            return row.normalized(stepCount: normalizedStepCount)
        }

        let trackIDs = Set(tracks.map(\.id))

        var normalizedPipelines = trackPipelines
            .filter { trackIDs.contains($0.trackID) }
            .map(\.normalized)
        let existingIDs = Set(normalizedPipelines.map(\.trackID))
        let missingIDs = trackIDs.subtracting(existingIDs)
        normalizedPipelines.append(
            contentsOf: missingIDs.map {
                PhraseTrackPipeline(trackID: $0, instrumentSource: .manualMono)
            }
        )
        normalizedPipelines.sort { lhs, rhs in
            tracks.firstIndex(where: { $0.id == lhs.trackID }) ?? 0 <
                tracks.firstIndex(where: { $0.id == rhs.trackID }) ?? 0
        }

        return PhraseModel(
            id: id,
            name: name,
            lengthBars: max(1, lengthBars),
            stepsPerBar: max(1, stepsPerBar),
            abstractRows: normalizedRows,
            trackPipelines: normalizedPipelines
        )
    }

    private static func defaultPipelines(for tracks: [StepSequenceTrack]) -> [PhraseTrackPipeline] {
        tracks.map { PhraseTrackPipeline(trackID: $0.id, instrumentSource: .manualMono) }
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

struct PhraseTrackPipeline: Codable, Equatable, Identifiable, Sendable {
    var trackID: UUID
    var instrumentSource: PhraseInstrumentSource
    var layerStates: [PhraseTrackLayerState]
    var showWiring: Bool

    private enum CodingKeys: String, CodingKey {
        case trackID
        case instrumentSource
        case layerStates
        case showWiring
    }

    init(
        trackID: UUID,
        instrumentSource: PhraseInstrumentSource,
        layerStates: [PhraseTrackLayerState] = PhraseTrackLayerState.defaults(),
        showWiring: Bool = false
    ) {
        self.trackID = trackID
        self.instrumentSource = instrumentSource
        self.layerStates = PhraseTrackLayerState.normalized(layerStates)
        self.showWiring = showWiring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try container.decode(UUID.self, forKey: .trackID)
        instrumentSource = try container.decode(PhraseInstrumentSource.self, forKey: .instrumentSource)
        layerStates = PhraseTrackLayerState.normalized(
            try container.decodeIfPresent([PhraseTrackLayerState].self, forKey: .layerStates) ?? []
        )
        showWiring = try container.decodeIfPresent(Bool.self, forKey: .showWiring) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackID, forKey: .trackID)
        try container.encode(instrumentSource, forKey: .instrumentSource)
        try container.encode(layerStates, forKey: .layerStates)
        try container.encode(showWiring, forKey: .showWiring)
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

    var normalized: PhraseTrackPipeline {
        PhraseTrackPipeline(
            trackID: trackID,
            instrumentSource: instrumentSource,
            layerStates: PhraseTrackLayerState.normalized(layerStates),
            showWiring: showWiring
        )
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

enum PhraseInstrumentSource: String, Codable, CaseIterable, Equatable, Sendable {
    case manualMono
    case clipReader
    case template
    case midiIn

    var label: String {
        switch self {
        case .manualMono:
            return "Manual Mono"
        case .clipReader:
            return "Clip Reader"
        case .template:
            return "Template"
        case .midiIn:
            return "MIDI In"
        }
    }

    var shortLabel: String {
        switch self {
        case .manualMono:
            return "Manual"
        case .clipReader:
            return "Clip"
        case .template:
            return "Template"
        case .midiIn:
            return "MIDI In"
        }
    }

    var detail: String {
        switch self {
        case .manualMono:
            return "Live step sequencer and pitch cycle"
        case .clipReader:
            return "Frozen or authored phrase clip"
        case .template:
            return "Template-backed starting point"
        case .midiIn:
            return "External MIDI capture and monitoring"
        }
    }

    var isImplemented: Bool {
        self == .manualMono
    }
}
