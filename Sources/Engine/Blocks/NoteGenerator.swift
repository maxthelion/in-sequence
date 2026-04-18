final class NoteGenerator: Block {
    static let defaultPitches: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
    static let defaultStepPattern: [Bool] = Array(repeating: true, count: 16)
    static let defaultVelocity: UInt8 = 100
    static let defaultGateLength: UInt16 = 4

    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [
        PortSpec(id: "notes", streamKind: .notes)
    ]

    let id: BlockID

    private var pitches: [UInt8]
    private var stepPattern: [Bool]
    private var velocity: UInt8
    private var gateLength: UInt16

    init(id: BlockID, params: [String: ParamValue] = [:]) {
        self.id = id
        self.pitches = Self.defaultPitches
        self.stepPattern = Self.defaultStepPattern
        self.velocity = Self.defaultVelocity
        self.gateLength = Self.defaultGateLength

        for (key, value) in params {
            apply(paramKey: key, value: value)
        }
    }

    func tick(context: TickContext) -> [PortID: Stream] {
        guard !pitches.isEmpty, !stepPattern.isEmpty else {
            return ["notes": .notes([])]
        }

        let stepIndex = Int(context.tickIndex % UInt64(stepPattern.count))
        guard stepPattern[stepIndex] else {
            return ["notes": .notes([])]
        }

        let pitchIndex = Int(context.tickIndex % UInt64(pitches.count))
        let event = NoteEvent(
            pitch: pitches[pitchIndex],
            velocity: velocity,
            length: gateLength,
            gate: true,
            voiceTag: nil
        )
        return ["notes": .notes([event])]
    }

    func apply(paramKey: String, value: ParamValue) {
        switch (paramKey, value) {
        case let ("pitches", .integers(values)):
            let next = values.compactMap(Self.midiByte(from:))
            guard !next.isEmpty else {
                return
            }
            pitches = next

        case let ("stepPattern", .integers(values)):
            guard !values.isEmpty else {
                return
            }
            stepPattern = values.map { $0 != 0 }

        case let ("velocity", .number(nextVelocity)):
            guard let velocity = Self.midiByte(from: Int(nextVelocity.rounded())) else {
                return
            }
            self.velocity = velocity

        case let ("gateLength", .number(nextGateLength)):
            guard nextGateLength >= 0,
                  nextGateLength <= Double(UInt16.max)
            else {
                return
            }
            gateLength = UInt16(nextGateLength.rounded())

        default:
            return
        }
    }

    private static func midiByte(from value: Int) -> UInt8? {
        guard (0...127).contains(value) else {
            return nil
        }
        return UInt8(value)
    }
}
