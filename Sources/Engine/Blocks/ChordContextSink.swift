final class ChordContextSink: Block {
    static let inputs: [PortSpec] = [
        PortSpec(id: "chord", streamKind: .chord)
    ]
    static let outputs: [PortSpec] = []

    let id: BlockID

    private let publish: (Chord) -> Void

    init(id: BlockID, publish: @escaping (Chord) -> Void) {
        self.id = id
        self.publish = publish
    }

    func tick(context: TickContext) -> [PortID: Stream] {
        if case let .chord(chord)? = context.inputs["chord"] {
            publish(chord)
        }
        return [:]
    }

    func apply(paramKey: String, value: ParamValue) {
        _ = paramKey
        _ = value
    }
}
