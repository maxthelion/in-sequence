import XCTest
@testable import SequencerAI

final class DrumAssetLibraryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("kits"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("templates"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Factory content

    func test_factory_kits_match_removed_preset_parts() {
        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.kits.map(\.name), ["808", "Acoustic", "Techno"])
        XCTAssertEqual(
            lib.kits.first(where: { $0.name == "808" })?.parts.map(\.tag),
            ["kick", "snare", "hat-closed", "clap"]
        )
        XCTAssertEqual(
            lib.kits.first(where: { $0.name == "Acoustic" })?.parts.map(\.tag),
            ["kick", "snare", "hat-closed"]
        )
        XCTAssertEqual(
            lib.kits.first(where: { $0.name == "Techno" })?.parts.map(\.tag),
            ["kick", "snare", "hat-closed", "ride"]
        )
        XCTAssertEqual(
            lib.kits.first(where: { $0.name == "808" })?.parts.map(\.trackName),
            ["Kick", "Snare", "Hat", "Clap"]
        )
        XCTAssertTrue(lib.kits.allSatisfy { kit in kit.parts.allSatisfy { $0.sampleID == nil } },
                      "factory kits resolve sounds via category, not pinned samples")
    }

    func test_factory_templates_match_removed_preset_seed_patterns() {
        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.templates.map(\.name), ["808", "Acoustic", "Techno"])

        let kit808 = lib.templates.first(where: { $0.name == "808" })
        XCTAssertEqual(kit808?.patterns["kick"], [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false])
        XCTAssertEqual(kit808?.patterns["snare"], [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false])
        XCTAssertEqual(kit808?.patterns["hat-closed"], [true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false])
        XCTAssertEqual(kit808?.patterns["clap"], [false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false])

        let acoustic = lib.templates.first(where: { $0.name == "Acoustic" })
        XCTAssertEqual(acoustic?.patterns["kick"], [true, false, false, false, false, false, true, false, true, false, false, false, false, false, true, false])
        XCTAssertEqual(acoustic?.patterns["snare"], [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false])
        XCTAssertEqual(acoustic?.patterns["hat-closed"], Array(repeating: true, count: 16))

        let techno = lib.templates.first(where: { $0.name == "Techno" })
        XCTAssertEqual(techno?.patterns["kick"], [true, false, false, false, true, false, false, false, true, false, false, false, true, false, true, false])
        XCTAssertEqual(techno?.patterns["snare"], [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false])
        XCTAssertEqual(techno?.patterns["hat-closed"], [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true])
        XCTAssertEqual(techno?.patterns["ride"], [false, false, false, true, false, false, false, true, false, false, false, true, false, false, false, true])
    }

    func test_factory_templates_are_sixteen_steps() {
        for template in DrumAssetLibrary.factoryTemplates {
            for (tag, pattern) in template.patterns {
                XCTAssertEqual(pattern.count, PatternTemplate.stepCount, "template=\(template.name) tag=\(tag)")
            }
        }
    }

    func test_factory_ids_are_stable_across_instances() {
        let lib1 = DrumAssetLibrary(libraryRoot: tempRoot)
        let lib2 = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib1.kits.map(\.id), lib2.kits.map(\.id))
        XCTAssertEqual(lib1.templates.map(\.id), lib2.templates.map(\.id))
        XCTAssertEqual(Set(lib1.kits.map(\.id)).count, lib1.kits.count, "factory kit IDs must be unique")
        XCTAssertEqual(Set(lib1.templates.map(\.id)).count, lib1.templates.count, "factory template IDs must be unique")
    }

    func test_factory_content_present_with_missing_root() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("definitely-missing-\(UUID())")
        let lib = DrumAssetLibrary(libraryRoot: missing)

        XCTAssertEqual(lib.kits.count, 3)
        XCTAssertEqual(lib.templates.count, 3)
        XCTAssertTrue(lib.userKits.isEmpty)
        XCTAssertTrue(lib.userTemplates.isEmpty)
    }

    // MARK: - User manifests

    func test_user_kit_manifests_load_after_factory_kits() throws {
        let userKit = DrumKit(
            id: UUID(),
            name: "My Breaks",
            parts: [DrumKit.Part(tag: "kick", trackName: "Boom", sampleID: UUID())]
        )
        try JSONEncoder().encode(userKit).write(to: tempRoot.appendingPathComponent("kits/my-breaks.json"))

        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.kits.count, 4)
        XCTAssertEqual(lib.kits.last, userKit)
        XCTAssertEqual(lib.kit(id: userKit.id), userKit)
    }

    func test_user_template_manifests_load_after_factory_templates() throws {
        let userTemplate = PatternTemplate(
            id: UUID(),
            name: "Half-Time",
            patterns: ["snare": (0..<16).map { $0 == 8 }]
        )
        try JSONEncoder().encode(userTemplate).write(to: tempRoot.appendingPathComponent("templates/half-time.json"))

        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.templates.count, 4)
        XCTAssertEqual(lib.templates.last, userTemplate)
        XCTAssertEqual(lib.template(id: userTemplate.id), userTemplate)
    }

    func test_unreadable_manifest_is_skipped() throws {
        try Data("not json".utf8).write(to: tempRoot.appendingPathComponent("kits/broken.json"))

        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.kits.count, 3, "broken manifest must not break factory content")
    }

    func test_reload_picksUp_new_manifest() throws {
        let lib = DrumAssetLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.kits.count, 3)

        let userKit = DrumKit(id: UUID(), name: "Late Kit", parts: [])
        try JSONEncoder().encode(userKit).write(to: tempRoot.appendingPathComponent("kits/late.json"))
        lib.reload()

        XCTAssertEqual(lib.kits.count, 4)
    }

    func test_user_manifests_sorted_by_filename() throws {
        let kitB = DrumKit(id: UUID(), name: "B Kit", parts: [])
        let kitA = DrumKit(id: UUID(), name: "A Kit", parts: [])
        try JSONEncoder().encode(kitB).write(to: tempRoot.appendingPathComponent("kits/b.json"))
        try JSONEncoder().encode(kitA).write(to: tempRoot.appendingPathComponent("kits/a.json"))

        let lib = DrumAssetLibrary(libraryRoot: tempRoot)

        XCTAssertEqual(lib.userKits.map(\.name), ["A Kit", "B Kit"])
    }
}
