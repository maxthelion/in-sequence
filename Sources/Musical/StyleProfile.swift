struct StyleProfile: Equatable, Sendable {
    let id: StyleProfileID
    let name: String
    let distanceWeights: [Double]
    let tailBase: Double
    let tailDecay: Double
    let ascendBias: Double
    let descendBias: Double
    let repeatBias: Double
    let leapPenalty: Double

    static func `for`(id: StyleProfileID) -> StyleProfile? {
        StyleProfiles.table[id]
    }
}
