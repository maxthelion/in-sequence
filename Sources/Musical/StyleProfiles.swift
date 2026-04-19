enum StyleProfiles {
    static let table: [StyleProfileID: StyleProfile] = [
        .vocal: StyleProfile(
            id: .vocal,
            name: "Vocal",
            distanceWeights: [0.16, 0.35, 0.24, 0.12, 0.07, 0.035, 0.016, 0.008],
            tailBase: 0.008,
            tailDecay: 0.5,
            ascendBias: 0.92,
            descendBias: 1.12,
            repeatBias: 1.08,
            leapPenalty: 0.42
        ),
        .balanced: StyleProfile(
            id: .balanced,
            name: "Balanced",
            distanceWeights: [0.13, 0.31, 0.25, 0.15, 0.08, 0.045, 0.022, 0.012],
            tailBase: 0.012,
            tailDecay: 0.58,
            ascendBias: 0.94,
            descendBias: 1.08,
            repeatBias: 1.0,
            leapPenalty: 0.55
        ),
        .jazz: StyleProfile(
            id: .jazz,
            name: "Jazz",
            distanceWeights: [0.08, 0.20, 0.21, 0.18, 0.14, 0.09, 0.05, 0.028],
            tailBase: 0.02,
            tailDecay: 0.7,
            ascendBias: 0.99,
            descendBias: 1.02,
            repeatBias: 0.84,
            leapPenalty: 0.78
        ),
    ]
}
