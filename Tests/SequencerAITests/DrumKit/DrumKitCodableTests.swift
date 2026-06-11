import Foundation
import XCTest
@testable import SequencerAI

final class DrumKitCodableTests: XCTestCase {
    func test_drumKit_roundTrips_through_codable() throws {
        let kit = DrumKit(
            id: UUID(),
            name: "Custom Kit",
            parts: [
                DrumKit.Part(tag: "kick", trackName: "Kick", sampleID: UUID()),
                DrumKit.Part(tag: "snare", trackName: "Snare", sampleID: nil),
                DrumKit.Part(tag: "tom-mid", trackName: "Mid Tom"),
            ]
        )

        let data = try JSONEncoder().encode(kit)
        let decoded = try JSONDecoder().decode(DrumKit.self, from: data)

        XCTAssertEqual(decoded, kit)
    }

    func test_factory_kits_roundTrip_through_codable() throws {
        for kit in DrumAssetLibrary.factoryKits {
            let data = try JSONEncoder().encode(kit)
            let decoded = try JSONDecoder().decode(DrumKit.self, from: data)
            XCTAssertEqual(decoded, kit, "kit=\(kit.name)")
        }
    }

    func test_patternTemplate_roundTrips_through_codable() throws {
        let template = PatternTemplate(
            id: UUID(),
            name: "Custom Groove",
            patterns: [
                "kick": [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false],
                "shaker": Array(repeating: true, count: 16),
            ]
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(PatternTemplate.self, from: data)

        XCTAssertEqual(decoded, template)
    }

    func test_factory_templates_roundTrip_through_codable() throws {
        for template in DrumAssetLibrary.factoryTemplates {
            let data = try JSONEncoder().encode(template)
            let decoded = try JSONDecoder().decode(PatternTemplate.self, from: data)
            XCTAssertEqual(decoded, template, "template=\(template.name)")
        }
    }

    func test_patternTemplate_decodes_from_plain_json_manifest() throws {
        let json = """
        {
            "id": "1B671A64-40D5-491E-99B0-DA01FF1F3341",
            "name": "Manifest Groove",
            "patterns": {
                "kick": [true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false]
            }
        }
        """

        let decoded = try JSONDecoder().decode(PatternTemplate.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.id, UUID(uuidString: "1B671A64-40D5-491E-99B0-DA01FF1F3341"))
        XCTAssertEqual(decoded.name, "Manifest Groove")
        XCTAssertEqual(decoded.patterns["kick"]?.count, 16)
    }
}
