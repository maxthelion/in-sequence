// Tests/SequencerAITests/DrumKit/DrumKitSampleResolutionTests.swift
import XCTest
@testable import SequencerAI

final class DrumKitSampleResolutionTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for category in ["kick", "snare", "hatClosed", "clap"] {
            let dir = libraryRoot.appendingPathComponent(category)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: dir.appendingPathComponent("\(category)-default.wav"))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private var kit808: DrumKit {
        DrumKitFixtures.factoryKit(named: "808")
    }

    func test_addDrumGroup_populatedLibrary_assignsSamplePerMember() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumGroup(plan: .from(kit: kit808), library: library)

        // Take tracks after the initial empty() baseline — addDrumGroup appends.
        let startIndex = project.tracks.count - kit808.parts.count
        let drumTracks = Array(project.tracks[startIndex...])
        XCTAssertEqual(drumTracks.count, kit808.parts.count)
        for track in drumTracks {
            if case .sample(_, _) = track.destination { continue }
            // internalSampler is the fallback for voices without a matching category
            if case .internalSampler(_, _) = track.destination { continue }
            XCTFail("track \(track.name) should have .sample or .internalSampler destination, got \(track.destination)")
        }

        let kick = drumTracks.first(where: { $0.name == "Kick" })!
        if case let .sample(sampleID, _) = kick.destination {
            XCTAssertEqual(sampleID, library.firstSample(in: .kick)?.id)
        } else {
            XCTFail("Kick track expected .sample destination, got \(kick.destination)")
        }
    }

    func test_addDrumGroup_resolvablePartSampleID_isPreferredOverFirstInCategory() throws {
        try Data().write(to: libraryRoot.appendingPathComponent("kick/kick-z-alternate.wav"))
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let alternateKick = try XCTUnwrap(library.samples(in: .kick).last)
        XCTAssertNotEqual(alternateKick.id, library.firstSample(in: .kick)?.id)

        var kit = kit808
        kit.parts[0].sampleID = alternateKick.id

        var project = Project.empty
        _ = project.addDrumGroup(plan: .from(kit: kit), library: library)

        let kick = project.tracks.first(where: { $0.name == "Kick" })!
        guard case let .sample(sampleID, _) = kick.destination else {
            return XCTFail("Kick track expected .sample destination, got \(kick.destination)")
        }
        XCTAssertEqual(sampleID, alternateKick.id)
    }

    func test_addDrumGroup_danglingPartSampleID_fallsBackToFirstInCategory() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)

        var kit = kit808
        kit.parts[0].sampleID = UUID() // dangling — not in the library

        var project = Project.empty
        _ = project.addDrumGroup(plan: .from(kit: kit), library: library)

        let kick = project.tracks.first(where: { $0.name == "Kick" })!
        guard case let .sample(sampleID, _) = kick.destination else {
            return XCTFail("Kick track expected .sample destination, got \(kick.destination)")
        }
        XCTAssertEqual(sampleID, library.firstSample(in: .kick)?.id)
    }

    func test_addDrumGroup_emptyCategory_fallsBackToInternalSampler() throws {
        try FileManager.default.removeItem(at: libraryRoot.appendingPathComponent("kick"))
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumGroup(plan: .from(kit: kit808), library: library)

        let kick = project.tracks.first(where: { $0.name == "Kick" })!
        switch kick.destination {
        case .internalSampler: break
        default: XCTFail("expected fallback .internalSampler, got \(kick.destination)")
        }
    }

    func test_addDrumGroup_sharedDestinationIsNil() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumGroup(plan: .from(kit: kit808), library: library)
        XCTAssertNil(project.trackGroups.last?.sharedDestination)
    }

    func test_voiceTagBridge_rejectsUnknownTags() {
        XCTAssertNil(AudioSampleCategory(voiceTag: "martian-voice"))
    }
}
