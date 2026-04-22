import struct Foundation.TimeInterval

typealias BlockID = String
typealias PortID = String

struct PortSpec: Equatable, Sendable {
    let id: PortID
    let streamKind: StreamKind
    let required: Bool

    init(id: PortID, streamKind: StreamKind, required: Bool = true) {
        self.id = id
        self.streamKind = streamKind
        self.required = required
    }
}

enum StreamKind: String, Equatable, Sendable {
    case notes
    case scalar
    case chord
    case event
    case gate
    case stepIndex
}

enum ParamValue: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case integers([Int])
}

enum Command: Equatable, Sendable {
    case setParam(blockID: BlockID, paramKey: String, value: ParamValue)
    case setBPM(Double)
}

struct TickContext: Equatable, Sendable {
    let tickIndex: UInt64
    let bpm: Double
    let inputs: [PortID: Stream]
    let now: TimeInterval
    let preparedNotesByBlockID: [BlockID: [NoteEvent]]

    init(
        tickIndex: UInt64,
        bpm: Double,
        inputs: [PortID: Stream],
        now: TimeInterval,
        preparedNotesByBlockID: [BlockID: [NoteEvent]] = [:]
    ) {
        self.tickIndex = tickIndex
        self.bpm = bpm
        self.inputs = inputs
        self.now = now
        self.preparedNotesByBlockID = preparedNotesByBlockID
    }
}

protocol Block: AnyObject {
    var id: BlockID { get }
    static var inputs: [PortSpec] { get }
    static var outputs: [PortSpec] { get }

    func tick(context: TickContext) -> [PortID: Stream]
    func apply(paramKey: String, value: ParamValue)
}
