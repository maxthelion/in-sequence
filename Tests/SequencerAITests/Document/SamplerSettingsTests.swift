// Tests/SequencerAITests/Document/SamplerSettingsTests.swift
import XCTest
@testable import SequencerAI

final class SamplerSettingsTests: XCTestCase {
    func test_default_isZeroed() {
        let s = SamplerSettings.default
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.length, 1)
        XCTAssertEqual(s.gain, 0)
        XCTAssertEqual(s.transpose, 0)
        XCTAssertEqual(s.attackMs, 0)
        XCTAssertEqual(s.releaseMs, 0)
    }

    func test_codable_roundTrip() throws {
        let s = SamplerSettings(start: 0.2, length: 0.7, gain: -6, transpose: 7, attackMs: 15, releaseMs: 200)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(SamplerSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func test_clamped_clampsAllFields() {
        let s = SamplerSettings(start: -1, length: 99, gain: 999, transpose: 99, attackMs: 99999, releaseMs: -5)
        let c = s.clamped()
        XCTAssertEqual(c.start, 0)
        XCTAssertEqual(c.length, 1)
        XCTAssertEqual(c.gain, 12)
        XCTAssertEqual(c.transpose, 48)
        XCTAssertEqual(c.attackMs, 2000)
        XCTAssertEqual(c.releaseMs, 0)
    }

    func test_clamped_negativeGain() {
        XCTAssertEqual(SamplerSettings(gain: -9999).clamped().gain, -60)
    }

    func test_decode_legacyDocument_usesDefaults() throws {
        // Simulates an older document that wrote only `gain`.
        let json = #"{"gain": -3}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SamplerSettings.self, from: json)
        XCTAssertEqual(decoded.start, 0)
        XCTAssertEqual(decoded.length, 1)
        XCTAssertEqual(decoded.gain, -3)
        XCTAssertEqual(decoded.transpose, 0)
        XCTAssertEqual(decoded.attackMs, 0)
        XCTAssertEqual(decoded.releaseMs, 0)
    }
}
