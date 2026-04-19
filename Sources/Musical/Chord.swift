struct ChordDefinition: Equatable, Sendable {
    let id: ChordID
    let name: String
    let intervals: [Int]

    static func `for`(id: ChordID) -> ChordDefinition? {
        Chords.table[id]
    }
}
