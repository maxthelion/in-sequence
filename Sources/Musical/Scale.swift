struct Scale: Equatable, Sendable {
    let id: ScaleID
    let name: String
    let intervals: [Int]

    static func `for`(id: ScaleID) -> Scale? {
        Scales.table[id]
    }
}
