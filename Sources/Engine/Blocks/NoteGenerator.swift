final class NoteGenerator: Block {
    static let defaultPitches: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
    static let defaultStepPattern: [Bool] = Array(repeating: true, count: 16)
    static let defaultAccentPattern: [Bool] = Array(repeating: false, count: 16)
    static let defaultVelocity: UInt8 = 100
    static let defaultGateLength: UInt16 = 4
    static let accentBoost: UInt8 = 20

    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [
        PortSpec(id: "notes", streamKind: .notes)
    ]

    let id: BlockID

    private var pitches: [UInt8]
    private var stepPattern: [Bool]
    private var accentPattern: [Bool]
    private var velocity: UInt8
    private var gateLength: UInt16

    init(id: BlockID, params: [String: ParamValue] = [:]) {
        self.id = id
        self.pitches = Self.defaultPitches
        self.stepPattern = Self.defaultStepPattern
        self.accentPattern = Self.defaultAccentPattern
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
        let stepVelocity = accentPattern[stepIndex] ? velocity.midiClampedAdd(Self.accentBoost) : velocity
        let event = NoteEvent(
            pitch: pitches[pitchIndex],
            velocity: stepVelocity,
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
            accentPattern = Self.normalizedPattern(accentPattern, stepCount: stepPattern.count)

        case let ("accentPattern", .integers(values)):
            guard !values.isEmpty else {
                return
            }
            accentPattern = Self.normalizedPattern(values.map { $0 != 0 }, stepCount: stepPattern.count)

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

    private static func normalizedPattern(_ pattern: [Bool], stepCount: Int) -> [Bool] {
        Array(pattern.prefix(stepCount)) + Array(repeating: false, count: max(0, stepCount - pattern.count))
    }
}

private extension UInt8 {
    func midiClampedAdd(_ other: UInt8) -> UInt8 {
        UInt8(Swift.min(Int(self) + Int(other), 127))
    }
}
