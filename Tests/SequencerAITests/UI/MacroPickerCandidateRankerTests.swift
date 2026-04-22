import XCTest
@testable import SequencerAI

final class MacroPickerCandidateRankerTests: XCTestCase {

    // MARK: - Helpers

    private func param(
        displayName: String,
        group: [String] = [],
        address: UInt64? = nil
    ) -> AUParameterDescriptor {
        AUParameterDescriptor(
            address: address ?? UInt64(displayName.hashValue & 0xFFFF_FFFF),
            identifier: displayName.lowercased().replacingOccurrences(of: " ", with: "."),
            displayName: displayName,
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            unit: nil,
            group: group,
            isWritable: true
        )
    }

    /// Build a canned fixture of ~40 real-world-style parameter names.
    private func fixtureParams() -> [AUParameterDescriptor] {
        [
            // AU candidates — displayName matches
            param(displayName: "Cutoff", group: ["Filter"]),
            param(displayName: "Resonance", group: ["Filter"]),
            param(displayName: "Filter Drive"),
            param(displayName: "Attack", group: ["ENV 1"]),
            param(displayName: "Decay", group: ["ENV 1"]),
            param(displayName: "Sustain", group: ["ENV 1"]),
            param(displayName: "Release", group: ["ENV 1"]),
            param(displayName: "LFO Rate", group: ["LFO 1"]),
            param(displayName: "LFO Depth", group: ["LFO 1"]),
            param(displayName: "Chorus Mix", group: ["FX"]),
            param(displayName: "Reverb Wet", group: ["FX"]),
            param(displayName: "Delay Time", group: ["FX"]),
            param(displayName: "Fine Tune", group: ["Oscillator 1"]),
            param(displayName: "Detune", group: ["Oscillator 2"]),
            param(displayName: "Macro 1"),
            param(displayName: "Macro 2"),
            // AU candidates — group matches only
            param(displayName: "Slope", group: ["Filter Section"]),
            param(displayName: "Keytrack", group: ["Filter Section"]),
            param(displayName: "Speed", group: ["LFO 2"]),
            param(displayName: "Bipolar", group: ["Envelope"]),
            // Non-candidates
            param(displayName: "Polyphony"),
            param(displayName: "Voice Stealing"),
            param(displayName: "Portamento Time"),
            param(displayName: "Output Level"),
            param(displayName: "Pan"),
            param(displayName: "Unison Voices"),
            param(displayName: "Unison Spread"),
            param(displayName: "Oscillator Type", group: ["Oscillator 1"]),
            param(displayName: "Pitch Bend Range"),
            param(displayName: "Aftertouch Sensitivity"),
            param(displayName: "Vintage Noise"),
            param(displayName: "Glide Mode"),
            param(displayName: "Keyboard Split"),
            param(displayName: "MIDI Learn"),
            param(displayName: "Arp Mode"),
            param(displayName: "Arp Rate"),
            param(displayName: "Arp Gate"),
            param(displayName: "Randomise"),
            param(displayName: "Stereo Width"),
            param(displayName: "Bit Crush"),
        ]
    }

    // MARK: - Basic partition

    func test_candidatesPlusRestEqualInput() {
        let input = fixtureParams()
        let (candidates, rest) = MacroPickerCandidateRanker.rank(input)

        let combined = Set(candidates.map(\.address)).union(Set(rest.map(\.address)))
        XCTAssertEqual(combined.count, input.count, "candidates + rest must cover all input params exactly once")
        XCTAssertEqual(candidates.count + rest.count, input.count)
    }

    func test_knownKeywordParams_areCandidates() {
        let input = fixtureParams()
        let (candidates, _) = MacroPickerCandidateRanker.rank(input)
        let candidateNames = Set(candidates.map(\.displayName))

        for name in ["Cutoff", "Resonance", "Attack", "Decay", "LFO Rate", "Reverb Wet", "Macro 1"] {
            XCTAssertTrue(candidateNames.contains(name), "\(name) should be a candidate")
        }
    }

    func test_nonKeywordParams_areInRest() {
        let input = fixtureParams()
        let (_, rest) = MacroPickerCandidateRanker.rank(input)
        let restNames = Set(rest.map(\.displayName))

        for name in ["Polyphony", "Output Level", "Vintage Noise", "MIDI Learn"] {
            XCTAssertTrue(restNames.contains(name), "\(name) should be in rest (not a candidate)")
        }
    }

    // MARK: - Ranking order

    func test_displayNameMatch_ranksAboveGroupMatch() {
        // "Cutoff" matches displayName; "Slope" only matches via group "Filter Section".
        let input = [
            param(displayName: "Slope", group: ["Filter Section"]),
            param(displayName: "Cutoff", group: ["Filter"])
        ]
        let (candidates, _) = MacroPickerCandidateRanker.rank(input)
        XCTAssertEqual(candidates.first?.displayName, "Cutoff",
            "displayName match should come before group match")
    }

    func test_shorterDisplayName_ranksFirstWithinSameTier() {
        // Both match displayName tier ("Filter" is a keyword).
        let short = param(displayName: "Filter")
        let medium = param(displayName: "Filter Cutoff")
        let long = param(displayName: "Filter Resonance X")
        let input = [long, medium, short]
        let (candidates, _) = MacroPickerCandidateRanker.rank(input)
        XCTAssertEqual(candidates.first?.displayName, "Filter")
        XCTAssertEqual(candidates[safe: 1]?.displayName, "Filter Cutoff")
        XCTAssertEqual(candidates[safe: 2]?.displayName, "Filter Resonance X")
    }

    func test_alphabeticalTieBreak_withinSameTierAndLength() {
        // "Decay" and "Pitch" both match displayName tier and have same length (5 chars).
        let decay = param(displayName: "Decay")
        let pitch = param(displayName: "Pitch")
        let input = [pitch, decay]
        let (candidates, _) = MacroPickerCandidateRanker.rank(input)
        XCTAssertEqual(candidates.map(\.displayName), ["Decay", "Pitch"])
    }

    func test_rest_isSortedAlphabetically() {
        let input = [
            param(displayName: "Vintage Noise"),
            param(displayName: "Arp Gate"),
            param(displayName: "Bit Crush"),
            param(displayName: "Pan"),
        ]
        let (_, rest) = MacroPickerCandidateRanker.rank(input)
        let names = rest.map(\.displayName)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - Edge cases

    func test_emptyInput_returnsEmptyOutput() {
        let (candidates, rest) = MacroPickerCandidateRanker.rank([])
        XCTAssertTrue(candidates.isEmpty)
        XCTAssertTrue(rest.isEmpty)
    }

    func test_allNonCandidates_returnedInRest() {
        let input = [param(displayName: "Pan"), param(displayName: "Volume")]
        let (candidates, rest) = MacroPickerCandidateRanker.rank(input)
        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(rest.count, 2)
    }

    func test_caseInsensitiveMatch() {
        // "CUTOFF" all-caps should still be a candidate.
        let input = [param(displayName: "CUTOFF")]
        let (candidates, _) = MacroPickerCandidateRanker.rank(input)
        XCTAssertEqual(candidates.count, 1)
    }

    func test_keywordsListIsNotEmpty() {
        XCTAssertFalse(MacroPickerCandidateRanker.candidateKeywords.isEmpty)
        XCTAssertTrue(MacroPickerCandidateRanker.candidateKeywords.contains("cutoff"))
    }
}

// MARK: - Collection helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
