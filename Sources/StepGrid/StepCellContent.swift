enum StepCellContent: Equatable, Sendable {
    case toggle
    case valueBar(fraction: Double)
    case pitchLabel(degree: String, octaveBand: Int, badge: String?)
    case sliceLabel(index: Int, label: String)
    case chordLabel(name: String)
    case optionLabel(text: String)
}
