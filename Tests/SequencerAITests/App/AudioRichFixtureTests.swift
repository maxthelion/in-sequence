import XCTest
@testable import SequencerAI

final class AudioRichFixtureTests: XCTestCase {
    /// Encodes exactly as the app saves a `.seqai` document
    /// (see SeqAIDocument.fileWrapper(snapshot:configuration:)).
    private func encodeAsDocument(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    func test_fixture_round_trips_and_writes_artifact() throws {
        let project = AudioRichFixture.makeProject()

        // (b) Encode the same way the app saves.
        let data = try encodeAsDocument(project)

        // (c) Round-trip: decode back and assert key invariants.
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        // The decoded project must be semantically equal to the source. (We
        // deliberately do NOT assert byte-for-byte re-encode stability — the
        // model carries UUID-keyed dictionaries, e.g. TrackGroup.noteMapping,
        // which Swift encodes as unordered key/value arrays whose order varies
        // per process. Project: Equatable compares those semantically.)
        XCTAssertEqual(decoded, project, "round-trip must preserve the project")

        // -- Mono melodic track with Analog Lab V AU instrument.
        let auTrack = try XCTUnwrap(
            decoded.tracks.first { track in
                if case let .auInstrument(componentID, _) = track.destination {
                    return componentID == AudioRichFixture.analogLabComponentID
                }
                return false
            },
            "expected a track routed to Analog Lab V"
        )
        XCTAssertEqual(auTrack.trackType, .monoMelodic)
        XCTAssertEqual(auTrack.name, "Analog Lab Lead")
        if case let .auInstrument(componentID, _) = auTrack.destination {
            XCTAssertEqual(componentID.type, "aumu")
            XCTAssertEqual(componentID.subtype, "Alav")
            XCTAssertEqual(componentID.manufacturer, "Artu")
        } else {
            XCTFail("AU destination lost on round-trip")
        }
        XCTAssertGreaterThan(auTrack.mix.sendA, 0, "AU track should drive Send A")

        // -- Slice track with a populated slice set.
        let sliceTrack = try XCTUnwrap(
            decoded.tracks.first { $0.trackType == .slice },
            "expected a slice track"
        )
        guard case let .slicer(sliceSetID, _) = sliceTrack.destination else {
            return XCTFail("slice track lost its slicer destination")
        }
        let sliceSet = try XCTUnwrap(
            decoded.sliceSet(id: sliceSetID),
            "slice set should be present in the pool"
        )
        XCTAssertEqual(sliceSet.sampleID, AudioRichFixture.slicerSampleID)
        XCTAssertGreaterThan(sliceSet.userSliceCount, 0, "slice set should have interior slices")
        XCTAssertTrue(
            decoded.isInAssetPool(kind: .sample, assetID: AudioRichFixture.slicerSampleID),
            "generated sample should be pooled"
        )

        // -- Drum group with each part on a generated `.sample(...)` one-shot
        //    (the working render path — the internal sampler is silent).
        let drumGroup = try XCTUnwrap(
            decoded.trackGroups.first { $0.name == "Audio Rich Kit" },
            "expected the drum group"
        )
        XCTAssertGreaterThanOrEqual(drumGroup.memberIDs.count, 4)
        let expectedDrumSampleIDs = Set(AudioRichFixture.drumHits.map(\.sampleID))
        var observedDrumSampleIDs = Set<UUID>()
        for memberID in drumGroup.memberIDs {
            let part = try XCTUnwrap(decoded.tracks.first { $0.id == memberID })
            guard case let .sample(sampleID, _) = part.destination else {
                return XCTFail("drum part \(part.name) is not on a `.sample` destination")
            }
            if case .internalSampler = part.destination {
                XCTFail("drum part \(part.name) must not use the silent internal sampler")
            }
            observedDrumSampleIDs.insert(sampleID)
            // Each drum sample must be pooled like the app does.
            XCTAssertTrue(
                decoded.isInAssetPool(kind: .sample, assetID: sampleID),
                "drum sample \(sampleID) should be pooled"
            )
        }
        XCTAssertEqual(
            observedDrumSampleIDs,
            expectedDrumSampleIDs,
            "drum parts should be wired to the four generated drum samples"
        )

        // -- Send buses each have one insert.
        XCTAssertEqual(decoded.sendBus(id: .sendA).inserts.count, 1)
        XCTAssertEqual(decoded.sendBus(id: .sendB).inserts.count, 1)
        if case .nativeFilter = decoded.sendBus(id: .sendA).inserts.first?.kind {} else {
            XCTFail("Send A insert should be a native filter")
        }

        // -- At least one mixer bus, with a track routed to it.
        XCTAssertGreaterThanOrEqual(decoded.buses.count, 1)
        let fxBus = try XCTUnwrap(decoded.buses.first { $0.name == "FX Bus" })
        XCTAssertFalse(decoded.trackIDsRouted(to: fxBus.id).isEmpty, "a track should be routed to the mixer bus")

        // (d) Write the artifact.
        //
        // The test runs inside the app sandbox, which cannot write into the
        // repo tree. So we always write to a sandbox-allowed temp path (and
        // sanity-decode it there), then attempt the repo write too. When the
        // repo write is blocked by the sandbox, the harness copies the temp
        // artifact into docs/fixtures/ afterwards.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-rich-routing.seqai")
        try data.write(to: tempURL)
        let reloaded = try JSONDecoder().decode(Project.self, from: Data(contentsOf: tempURL))
        XCTAssertEqual(reloaded, decoded)
        XCTAssertGreaterThan(data.count, 0)
        print("[AudioRichFixtureTests] wrote \(data.count) bytes to TEMP \(tempURL.path)")

        let fixtureURL = Self.fixtureURL()
        do {
            try FileManager.default.createDirectory(
                at: fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fixtureURL)
            print("[AudioRichFixtureTests] wrote \(data.count) bytes to REPO \(fixtureURL.path)")
        } catch {
            // Expected under the app sandbox; the temp artifact above is the
            // source of truth the harness copies into the repo.
            print("[AudioRichFixtureTests] repo write skipped (sandbox): \(error.localizedDescription)")
        }
    }

    /// SAMPLE-ONLY variant: round-trips and writes the unattended-automation
    /// fixture, asserting it carries NO `.auInstrument` destination anywhere (so
    /// a headless/wired launch never triggers the macOS AU permission modal).
    func test_sampleOnly_fixture_round_trips_has_no_au_and_writes_artifact() throws {
        let project = AudioRichFixture.makeSampleOnlyProject()

        let data = try encodeAsDocument(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded, project, "round-trip must preserve the project")

        // -- The headline invariant: NOT A SINGLE .auInstrument destination.
        for track in decoded.tracks {
            if case .auInstrument = track.destination {
                XCTFail("sample-only fixture must not contain any .auInstrument destination (track \(track.name))")
            }
        }

        // -- Mono melodic lead is now on a generated `.sample(...)`, driving Send A.
        let leadTrack = try XCTUnwrap(
            decoded.tracks.first { $0.name == "Sample Lead" },
            "expected a sample-backed lead track"
        )
        XCTAssertEqual(leadTrack.trackType, .monoMelodic)
        guard case let .sample(sampleID, _) = leadTrack.destination else {
            return XCTFail("lead track should be on a .sample destination")
        }
        XCTAssertEqual(sampleID, AudioRichFixture.melodicSampleID)
        XCTAssertGreaterThan(leadTrack.mix.sendA, 0, "lead track should drive Send A")
        XCTAssertTrue(
            decoded.isInAssetPool(kind: .sample, assetID: AudioRichFixture.melodicSampleID),
            "generated lead sample should be pooled"
        )

        // -- Slice track with a populated slice set (unchanged from makeProject()).
        let sliceTrack = try XCTUnwrap(
            decoded.tracks.first { $0.trackType == .slice },
            "expected a slice track"
        )
        guard case let .slicer(sliceSetID, _) = sliceTrack.destination else {
            return XCTFail("slice track lost its slicer destination")
        }
        let sliceSet = try XCTUnwrap(decoded.sliceSet(id: sliceSetID))
        XCTAssertGreaterThan(sliceSet.userSliceCount, 0)

        // -- Drum group with each part on a generated `.sample(...)` one-shot.
        let drumGroup = try XCTUnwrap(
            decoded.trackGroups.first { $0.name == "Audio Rich Kit" }
        )
        XCTAssertGreaterThanOrEqual(drumGroup.memberIDs.count, 4)
        for memberID in drumGroup.memberIDs {
            let part = try XCTUnwrap(decoded.tracks.first { $0.id == memberID })
            guard case .sample = part.destination else {
                return XCTFail("drum part \(part.name) is not on a `.sample` destination")
            }
        }

        // -- Continuously-sustaining drone: the LAST track, on a generated
        //    `.sample(...)`, on master (no sends), triggering on every step so
        //    the master path always has audio (makes the SILENCE metric honest).
        let droneTrack = try XCTUnwrap(
            decoded.tracks.last { $0.name == "Sustain Drone" },
            "expected a sustained drone track"
        )
        XCTAssertEqual(decoded.tracks.last?.id, droneTrack.id, "drone must be the LAST track so routing-stress ops never touch it")
        guard case let .sample(droneSampleID, _) = droneTrack.destination else {
            return XCTFail("drone track should be on a .sample destination")
        }
        XCTAssertEqual(droneSampleID, AudioRichFixture.droneSampleID)
        XCTAssertEqual(droneTrack.mix.sendA, 0, "drone must stay on master (no Send A)")
        XCTAssertEqual(droneTrack.mix.sendB, 0, "drone must stay on master (no Send B)")
        XCTAssertTrue(droneTrack.stepPattern.allSatisfy { $0 }, "drone must trigger on every step")
        XCTAssertTrue(
            decoded.isInAssetPool(kind: .sample, assetID: AudioRichFixture.droneSampleID),
            "generated drone sample should be pooled"
        )

        // -- Send buses + mixer bus routing (unchanged).
        XCTAssertEqual(decoded.sendBus(id: .sendA).inserts.count, 1)
        XCTAssertEqual(decoded.sendBus(id: .sendB).inserts.count, 1)
        if case .nativeFilter = decoded.sendBus(id: .sendA).inserts.first?.kind {} else {
            XCTFail("Send A insert should be a native filter")
        }
        let fxBus = try XCTUnwrap(decoded.buses.first { $0.name == "FX Bus" })
        XCTAssertFalse(decoded.trackIDsRouted(to: fxBus.id).isEmpty)

        // -- Write the artifact (temp first for sandbox, then attempt repo).
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-rich-routing-sampleonly.seqai")
        try data.write(to: tempURL)
        let reloaded = try JSONDecoder().decode(Project.self, from: Data(contentsOf: tempURL))
        XCTAssertEqual(reloaded, decoded)
        print("[AudioRichFixtureTests] wrote \(data.count) bytes to TEMP \(tempURL.path)")

        let fixtureURL = Self.sampleOnlyFixtureURL()
        do {
            try FileManager.default.createDirectory(
                at: fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fixtureURL)
            print("[AudioRichFixtureTests] wrote \(data.count) bytes to REPO \(fixtureURL.path)")
        } catch {
            print("[AudioRichFixtureTests] repo write skipped (sandbox): \(error.localizedDescription)")
        }
    }

    /// Resolves `docs/fixtures/audio-rich-routing.seqai` relative to the repo
    /// root by walking up from this source file.
    private static func fixtureURL() -> URL {
        repoRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("audio-rich-routing.seqai")
    }

    private static func sampleOnlyFixtureURL() -> URL {
        repoRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("audio-rich-routing-sampleonly.seqai")
    }

    private static func repoRoot() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../in-sequence/Tests/SequencerAITests/App/AudioRichFixtureTests.swift
        return thisFile
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // SequencerAITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // in-sequence
    }
}
