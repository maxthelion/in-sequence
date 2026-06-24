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

        // -- Drum group with parts on the Apple internal sampler.
        let drumGroup = try XCTUnwrap(
            decoded.trackGroups.first { $0.name == "Audio Rich Kit" },
            "expected the drum group"
        )
        XCTAssertGreaterThanOrEqual(drumGroup.memberIDs.count, 4)
        for memberID in drumGroup.memberIDs {
            let part = try XCTUnwrap(decoded.tracks.first { $0.id == memberID })
            guard case let .internalSampler(bankID, _) = part.destination else {
                return XCTFail("drum part \(part.name) is not on the internal sampler")
            }
            XCTAssertEqual(bankID, .drumKitDefault)
        }

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

    /// Resolves `docs/fixtures/audio-rich-routing.seqai` relative to the repo
    /// root by walking up from this source file.
    private static func fixtureURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../in-sequence/Tests/SequencerAITests/App/AudioRichFixtureTests.swift
        let repoRoot = thisFile
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // SequencerAITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // in-sequence
        return repoRoot
            .appendingPathComponent("docs")
            .appendingPathComponent("fixtures")
            .appendingPathComponent("audio-rich-routing.seqai")
    }
}
