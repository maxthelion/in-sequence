// Tests/SequencerAITests/Document/AudioSampleCategoryTests.swift
import XCTest
@testable import SequencerAI

final class AudioSampleCategoryTests: XCTestCase {
    func test_isDrumVoice_trueForDrumCases() {
        let drumCases = AudioSampleCategory.allCases.filter { $0.isDrumVoice }
        XCTAssertFalse(drumCases.isEmpty)
        for c in drumCases {
            XCTAssertTrue(c.isDrumVoice, "\(c) should be drum voice")
        }
    }

    func test_isDrumVoice_falseForUnknown() {
        XCTAssertFalse(AudioSampleCategory.unknown.isDrumVoice)
    }

    func test_voiceTagBridge_knownTags() {
        let mapping: [(String, AudioSampleCategory)] = [
            ("kick", .kick),
            ("snare", .snare),
            ("hat-closed", .hatClosed),
            ("hat-open", .hatOpen),
            ("hat-pedal", .hatPedal),
            ("clap", .clap),
            ("ride", .ride),
            ("crash", .crash),
            ("tom-low", .tomLow),
            ("tom-mid", .tomMid),
            ("tom-hi", .tomHi),
            ("sidestick", .sidestick),
            ("rim", .sidestick),
            ("cowbell", .cowbell),
            ("tambourine", .tambourine),
            ("shaker", .shaker),
        ]
        for (tag, expected) in mapping {
            XCTAssertEqual(AudioSampleCategory(voiceTag: tag), expected, "tag \"\(tag)\" should map to \(expected)")
        }
    }

    func test_voiceTagBridge_unknownTagReturnsNil() {
        XCTAssertNil(AudioSampleCategory(voiceTag: "nonsense"))
        XCTAssertNil(AudioSampleCategory(voiceTag: ""))
    }

    func test_codable_roundTrip() throws {
        for c in AudioSampleCategory.allCases {
            let encoded = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(AudioSampleCategory.self, from: encoded)
            XCTAssertEqual(decoded, c, "round-trip failed for \(c)")
        }
    }
}
