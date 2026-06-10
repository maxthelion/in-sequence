import XCTest
@testable import SequencerAI

final class TrackTypeTests: XCTestCase {
    func test_track_type_has_four_cases() {
        XCTAssertEqual(TrackType.allCases.count, 4)
        XCTAssertEqual(Set(TrackType.allCases), [.monoMelodic, .polyMelodic, .slice, .audioInput])
    }

    func test_values_round_trip() throws {
        for trackType in TrackType.allCases {
            let data = try JSONEncoder().encode(trackType)
            let decoded = try JSONDecoder().decode(TrackType.self, from: data)
            XCTAssertEqual(decoded, trackType)
        }
    }

    func test_unknown_value_throws() {
        XCTAssertThrowsError(try decode("\"wat\""))
    }

    private func decode(_ json: String) throws -> TrackType {
        try JSONDecoder().decode(TrackType.self, from: Data(json.utf8))
    }
}

final class AudioInputChannelTests: XCTestCase {
    func test_values_round_trip() throws {
        let channels: [AudioInputChannel] = [
            .mono(channel: 0), .mono(channel: 7), .stereo(firstChannel: 0), .stereo(firstChannel: 12),
        ]
        for channel in channels {
            let data = try JSONEncoder().encode(channel)
            let decoded = try JSONDecoder().decode(AudioInputChannel.self, from: data)
            XCTAssertEqual(decoded, channel)
        }
    }

    func test_legacy_string_values_decode() throws {
        func decode(_ raw: String) throws -> AudioInputChannel {
            try JSONDecoder().decode(AudioInputChannel.self, from: Data("\"\(raw)\"".utf8))
        }
        XCTAssertEqual(try decode("mono1"), .mono(channel: 0))
        XCTAssertEqual(try decode("mono2"), .mono(channel: 1))
        XCTAssertEqual(try decode("stereo"), .stereo(firstChannel: 0))
        // Unknown values fall back to the stereo default instead of failing
        // the whole track decode.
        XCTAssertEqual(try decode("wat"), .stereo(firstChannel: 0))
    }

    func test_options_follow_device_channel_count() {
        XCTAssertEqual(AudioInputChannel.monoOptions(channelCount: 0), [])
        XCTAssertEqual(AudioInputChannel.monoOptions(channelCount: 3).count, 3)
        XCTAssertEqual(AudioInputChannel.stereoOptions(channelCount: 1), [])
        XCTAssertEqual(
            AudioInputChannel.stereoOptions(channelCount: 8),
            [.stereo(firstChannel: 0), .stereo(firstChannel: 2), .stereo(firstChannel: 4), .stereo(firstChannel: 6)]
        )
        XCTAssertEqual(AudioInputChannel.stereo(firstChannel: 3).normalized, .stereo(firstChannel: 2))
        XCTAssertEqual(AudioInputChannel.mono(channel: 5).requiredChannelCount, 6)
        XCTAssertEqual(AudioInputChannel.stereo(firstChannel: 6).requiredChannelCount, 8)
    }
}
