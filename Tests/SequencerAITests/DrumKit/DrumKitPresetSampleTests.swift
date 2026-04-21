// Tests/SequencerAITests/DrumKit/DrumKitPresetSampleTests.swift
import XCTest
@testable import SequencerAI

final class DrumKitPresetSampleTests: XCTestCase {
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

    func test_addDrumKit_populatedLibrary_assignsSamplePerMember() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumKit(.kit808, library: library)

        // Take tracks after the initial empty() baseline — addDrumKit appends.
        let startIndex = project.tracks.count - DrumKitPreset.kit808.members.count
        let drumTracks = Array(project.tracks[startIndex...])
        XCTAssertEqual(drumTracks.count, DrumKitPreset.kit808.members.count)
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

    func test_addDrumKit_emptyCategory_fallsBackToInternalSampler() throws {
        try FileManager.default.removeItem(at: libraryRoot.appendingPathComponent("kick"))
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumKit(.kit808, library: library)

        let kick = project.tracks.first(where: { $0.name == "Kick" })!
        switch kick.destination {
        case .internalSampler: break
        default: XCTFail("expected fallback .internalSampler, got \(kick.destination)")
        }
    }

    func test_addDrumKit_sharedDestinationIsNil() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        var project = Project.empty
        _ = project.addDrumKit(.kit808, library: library)
        XCTAssertNil(project.trackGroups.last?.sharedDestination)
    }

    func test_voiceTagBridge_rejectsUnknownTags() {
        XCTAssertNil(AudioSampleCategory(voiceTag: "martian-voice"))
    }
}
