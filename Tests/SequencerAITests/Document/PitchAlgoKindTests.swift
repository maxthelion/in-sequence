import XCTest
@testable import SequencerAI

final class PitchAlgoKindTests: XCTestCase {
    func test_pitch_algo_kind_projection_matches_cases() {
        XCTAssertEqual(PitchAlgo.manual(pitches: [60], pickMode: .sequential).kind, .manual)
        XCTAssertEqual(PitchAlgo.randomInScale(root: 60, scale: .major, spread: 12).kind, .randomInScale)
        XCTAssertEqual(PitchAlgo.randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12).kind, .randomInChord)
        XCTAssertEqual(PitchAlgo.intervalProb(root: 60, scale: .major, degreeWeights: [1, 0, 0, 0, 0, 0, 0]).kind, .intervalProb)
        XCTAssertEqual(PitchAlgo.markov(root: 60, scale: .major, styleID: .balanced, leap: 0.2, color: 0.4).kind, .markov)
        XCTAssertEqual(PitchAlgo.fromClipPitches(clipID: UUID(), pickMode: .random).kind, .fromClipPitches)
        XCTAssertEqual(PitchAlgo.external(port: "Port", channel: 0, holdMode: .pool).kind, .external)
    }

    func test_default_algo_round_trips_to_same_kind() {
        let clipChoices = [ClipPoolEntry.defaultPool[0]]
        let current = PitchAlgo.manual(pitches: [60], pickMode: .sequential)

        for kind in PitchAlgoKind.allCases {
            XCTAssertEqual(kind.defaultAlgo(clipChoices: clipChoices, current: current).kind, kind)
        }
    }
}
