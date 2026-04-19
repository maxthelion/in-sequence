import XCTest
@testable import SequencerAI

final class MIDIRouterTests: XCTestCase {
    func test_empty_routes_emit_nothing() {
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([])
        router.tick([RouterTickInput(sourceTrack: UUID(), notes: [note(pitch: 60)], chordContext: nil)])

        XCTAssertTrue(dispatcher.events.isEmpty)
    }

    func test_track_route_emits_note_for_matching_source() {
        let sourceID = UUID()
        let targetID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(source: .track(sourceID), destination: .trackInput(targetID, tag: nil))
        ])
        router.tick([RouterTickInput(sourceTrack: sourceID, notes: [note(pitch: 60)], chordContext: nil)])

        XCTAssertEqual(
            dispatcher.events,
            [.note(to: .trackInput(targetID, tag: nil), event: note(pitch: 60))]
        )
    }

    func test_fan_out_emits_once_per_matching_route() {
        let sourceID = UUID()
        let targetID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(source: .track(sourceID), destination: .voicing(targetID)),
            Route(source: .track(sourceID), destination: .midi(port: .sequencerAIOut, channel: 2, noteOffset: 0))
        ])
        router.tick([RouterTickInput(sourceTrack: sourceID, notes: [note(pitch: 64)], chordContext: nil)])

        XCTAssertEqual(dispatcher.events.count, 2)
    }

    func test_voice_tag_filter_only_matches_tagged_events() {
        let sourceID = UUID()
        let targetID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(source: .track(sourceID), filter: .voiceTag("kick"), destination: .trackInput(targetID, tag: "kick"))
        ])
        router.tick([
            RouterTickInput(
                sourceTrack: sourceID,
                notes: [
                    note(pitch: 36, tag: "kick"),
                    note(pitch: 38, tag: "snare")
                ],
                chordContext: nil
            )
        ])

        XCTAssertEqual(
            dispatcher.events,
            [.note(to: .trackInput(targetID, tag: "kick"), event: note(pitch: 36, tag: "kick"))]
        )
    }

    func test_note_range_filter_limits_pitch_matches() {
        let sourceID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(
                source: .track(sourceID),
                filter: .noteRange(lo: 60, hi: 72),
                destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
            )
        ])
        router.tick([
            RouterTickInput(
                sourceTrack: sourceID,
                notes: [note(pitch: 55), note(pitch: 60), note(pitch: 72), note(pitch: 73)],
                chordContext: nil
            )
        ])

        XCTAssertEqual(dispatcher.events.count, 2)
    }

    func test_disabled_routes_do_not_emit() {
        let sourceID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(source: .track(sourceID), destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0), enabled: false)
        ])
        router.tick([RouterTickInput(sourceTrack: sourceID, notes: [note(pitch: 60)], chordContext: nil)])

        XCTAssertTrue(dispatcher.events.isEmpty)
    }

    func test_chord_generator_route_emits_chord_event_when_present() {
        let sourceID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)
        let chord = Chord(root: 60, chordType: "maj7", scale: "ionian")

        router.applyRoutesSnapshot([
            Route(source: .chordGenerator(sourceID), destination: .chordContext(broadcastTag: "hook"))
        ])
        router.tick([RouterTickInput(sourceTrack: sourceID, notes: [], chordContext: chord)])

        XCTAssertEqual(dispatcher.events, [.chord(to: .chordContext(broadcastTag: "hook"), chord: chord, lane: "hook")])
    }

    func test_replacing_route_snapshot_stops_emitting_old_routes() {
        let sourceID = UUID()
        let dispatcher = CapturingRouterDispatcher()
        let router = MIDIRouter(dispatcher: dispatcher)

        router.applyRoutesSnapshot([
            Route(source: .track(sourceID), destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
        ])
        router.applyRoutesSnapshot([])
        router.tick([RouterTickInput(sourceTrack: sourceID, notes: [note(pitch: 60)], chordContext: nil)])

        XCTAssertTrue(dispatcher.events.isEmpty)
    }

    private func note(pitch: UInt8, tag: VoiceTag? = nil) -> NoteEvent {
        NoteEvent(pitch: pitch, velocity: 100, length: 4, gate: true, voiceTag: tag)
    }
}

private final class CapturingRouterDispatcher: RouterDispatcher {
    private(set) var events: [RouterEvent] = []

    func dispatch(_ event: RouterEvent) {
        events.append(event)
    }
}
