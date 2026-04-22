import XCTest
@testable import SequencerAI

final class SamplerFilterSettingsTests: XCTestCase {

    // MARK: - Defaults

    func test_defaults_areBypassTransparent() {
        let s = SamplerFilterSettings()
        XCTAssertEqual(s.type, .lowpass)
        XCTAssertEqual(s.poles, .two)
        XCTAssertEqual(s.cutoffHz, 20_000, accuracy: 0.001)
        XCTAssertEqual(s.resonance, 0, accuracy: 0.001)
        XCTAssertEqual(s.drive, 0, accuracy: 0.001)
    }

    // MARK: - Round-trip coding

    func test_roundTrip_defaultValues() throws {
        let original = SamplerFilterSettings()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_roundTrip_allFilterTypes() throws {
        for filterType in SamplerFilterType.allCases {
            var s = SamplerFilterSettings()
            s.type = filterType
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: data)
            XCTAssertEqual(decoded.type, filterType, "Round-trip failed for type \(filterType)")
        }
    }

    func test_roundTrip_allPolesValues() throws {
        for poles in SamplerFilterPoles.allCases {
            var s = SamplerFilterSettings()
            s.poles = poles
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: data)
            XCTAssertEqual(decoded.poles, poles, "Round-trip failed for poles \(poles)")
        }
    }

    func test_roundTrip_customValues() throws {
        var s = SamplerFilterSettings()
        s.type = .highpass
        s.poles = .four
        s.cutoffHz = 2500
        s.resonance = 0.7
        s.drive = 0.3
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: data)
        XCTAssertEqual(decoded.type, .highpass)
        XCTAssertEqual(decoded.poles, .four)
        XCTAssertEqual(decoded.cutoffHz, 2500, accuracy: 0.001)
        XCTAssertEqual(decoded.resonance, 0.7, accuracy: 0.001)
        XCTAssertEqual(decoded.drive, 0.3, accuracy: 0.001)
    }

    // MARK: - Legacy decode (missing filter key)

    func test_legacyDecode_missingAllKeys_usesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: json)
        XCTAssertEqual(decoded.type, .lowpass)
        XCTAssertEqual(decoded.poles, .two)
        XCTAssertEqual(decoded.cutoffHz, 20_000, accuracy: 0.001)
        XCTAssertEqual(decoded.resonance, 0, accuracy: 0.001)
        XCTAssertEqual(decoded.drive, 0, accuracy: 0.001)
    }

    func test_legacyDecode_partialKeys_appliesDefaults() throws {
        let json = #"{"cutoffHz":1000}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SamplerFilterSettings.self, from: json)
        XCTAssertEqual(decoded.cutoffHz, 1000, accuracy: 0.001)
        XCTAssertEqual(decoded.type, .lowpass)
        XCTAssertEqual(decoded.resonance, 0, accuracy: 0.001)
    }

    // MARK: - clamped()

    func test_clamped_cutoffBelowMin() {
        var s = SamplerFilterSettings()
        s.cutoffHz = -100
        XCTAssertEqual(s.clamped().cutoffHz, 20, accuracy: 0.001)
    }

    func test_clamped_cutoffAboveMax() {
        var s = SamplerFilterSettings()
        s.cutoffHz = 99_999
        XCTAssertEqual(s.clamped().cutoffHz, 20_000, accuracy: 0.001)
    }

    func test_clamped_resonanceBelowMin() {
        var s = SamplerFilterSettings()
        s.resonance = -0.5
        XCTAssertEqual(s.clamped().resonance, 0, accuracy: 0.001)
    }

    func test_clamped_resonanceAboveMax() {
        var s = SamplerFilterSettings()
        s.resonance = 2.0
        XCTAssertEqual(s.clamped().resonance, 1, accuracy: 0.001)
    }

    func test_clamped_driveBelowMin() {
        var s = SamplerFilterSettings()
        s.drive = -1.0
        XCTAssertEqual(s.clamped().drive, 0, accuracy: 0.001)
    }

    func test_clamped_driveAboveMax() {
        var s = SamplerFilterSettings()
        s.drive = 5.0
        XCTAssertEqual(s.clamped().drive, 1, accuracy: 0.001)
    }

    func test_clamped_validValues_unchanged() {
        let s = SamplerFilterSettings(type: .bandpass, poles: .one, cutoffHz: 1000, resonance: 0.5, drive: 0.5)
        let c = s.clamped()
        XCTAssertEqual(c.cutoffHz, 1000, accuracy: 0.001)
        XCTAssertEqual(c.resonance, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.drive, 0.5, accuracy: 0.001)
    }

    // MARK: - SamplerFilterType cases

    func test_filterType_allCasesCount() {
        XCTAssertEqual(SamplerFilterType.allCases.count, 4)
    }

    // MARK: - SamplerFilterPoles cases

    func test_filterPoles_allCasesCount() {
        XCTAssertEqual(SamplerFilterPoles.allCases.count, 3)
    }

    func test_filterPoles_rawValues() {
        XCTAssertEqual(SamplerFilterPoles.one.rawValue, 1)
        XCTAssertEqual(SamplerFilterPoles.two.rawValue, 2)
        XCTAssertEqual(SamplerFilterPoles.four.rawValue, 4)
    }
}
