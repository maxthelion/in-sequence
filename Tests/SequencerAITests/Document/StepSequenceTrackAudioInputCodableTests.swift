import XCTest
@testable import SequencerAI

final class StepSequenceTrackAudioInputCodableTests: XCTestCase {
    func test_noteRepeatIntervalsExposeOnlyAcceptedV1Values() {
        XCTAssertEqual(NoteRepeatInterval.allCases.map(\.rawValue), ["1/16", "1/32", "1/64"])
    }

    func test_noteRepeatInterval_roundTripsAllAcceptedValues() throws {
        for interval in NoteRepeatInterval.allCases {
            var track = StepSequenceTrack.default
            track.noteRepeatInterval = interval

            let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: JSONEncoder().encode(track))

            XCTAssertEqual(decoded.noteRepeatInterval, interval)
        }
    }

    func test_legacyTrackWithoutNoteRepeatInterval_decodesWithDefault() throws {
        let legacyData = try encodedTrackData(removingKeys: ["noteRepeatInterval"])

        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: legacyData)

        XCTAssertEqual(decoded.noteRepeatInterval, .oneSixteenth)
    }

    func test_invalidNoteRepeatInterval_decodesWithDefault() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(StepSequenceTrack.default)) as? [String: Any]
        )
        object["noteRepeatInterval"] = "1/128"
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: data)

        XCTAssertEqual(decoded.noteRepeatInterval, .oneSixteenth)
    }

    func test_legacyTrackWithoutAudioInputFields_decodesWithDefaults() throws {
        let legacyData = try encodedTrackData(removingKeys: ["recordBarLength", "inputChannel"])

        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: legacyData)

        XCTAssertEqual(decoded.recordBarLength, 2)
        XCTAssertEqual(decoded.inputChannel, .stereo(firstChannel: 0))
    }

    func test_recordBarLength_isConstrainedToAllowedBarCounts() throws {
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(1), 1)
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(2), 2)
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(4), 4)
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(8), 8)
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(3), 2)
        XCTAssertEqual(StepSequenceTrack.normalizedRecordBarLength(0), 2)
    }

    func test_audioInputTrack_roundTripsAuthoredFieldsThroughProjectDocument() throws {
        let track = StepSequenceTrack(
            id: UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!,
            name: "Input Loop",
            trackType: .audioInput,
            pitches: [60],
            stepPattern: Array(repeating: false, count: 16),
            destination: Destination.none,
            velocity: 100,
            gateLength: 4,
            recordBarLength: 4,
            inputChannel: .mono(channel: 1)
        )
        let project = Project(
            version: 1,
            tracks: [track],
            selectedTrackID: track.id,
            phrases: [],
            selectedPhraseID: UUID()
        )

        let data = try JSONEncoder().encode(project)
        let encodedJSON = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        let decodedTrack = try XCTUnwrap(decoded.tracks.first)

        XCTAssertEqual(decodedTrack.trackType, .audioInput)
        XCTAssertEqual(decodedTrack.recordBarLength, 4)
        XCTAssertEqual(decodedTrack.inputChannel, .mono(channel: 1))
        XCTAssertTrue(encodedJSON.contains("recordBarLength"))
        XCTAssertTrue(encodedJSON.contains("inputChannel"))
        XCTAssertFalse(encodedJSON.contains("captureBuffer"))
        XCTAssertFalse(encodedJSON.contains("recordedPCM"))
        XCTAssertFalse(encodedJSON.contains("armState"))
        XCTAssertFalse(encodedJSON.contains("monitorMode"))
        XCTAssertFalse(encodedJSON.contains("waveform"))
        XCTAssertFalse(encodedJSON.contains("pendingTick"))
    }

    func test_nonAudioInputTrack_doesNotEncodeAudioInputFields() throws {
        let data = try JSONEncoder().encode(StepSequenceTrack.default)
        let encodedJSON = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(encodedJSON.contains("recordBarLength"))
        XCTAssertFalse(encodedJSON.contains("inputChannel"))
    }

    func test_audioInputTracksDoNotExposeSequencerSourceModes() {
        XCTAssertEqual(TrackSourceMode.available(for: .audioInput), [])
    }

    private func encodedTrackData(removingKeys keys: [String]) throws -> Data {
        let data = try JSONEncoder().encode(StepSequenceTrack.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        keys.forEach { object.removeValue(forKey: $0) }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
