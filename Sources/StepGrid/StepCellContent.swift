enum StepCellContent: Equatable, Sendable {
    case toggle
    case valueBar(fraction: Double)
    case sliceLabel(index: Int, label: String)
    case chordLabel(name: String)
    case optionLabel(text: String)
}
