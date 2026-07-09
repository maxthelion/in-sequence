import AVFoundation
import XCTest
@testable import SequencerAI

/// Tests for the preset readout / load surface on `AudioInstrumentHost` + the pure
/// descriptor-mapping helpers on `AUPresetDescriptor`.
///
/// Readout/load behaviour against a _live_ AU is covered by manual smoke (sheet open on
/// Pigments etc.); the AVAudioUnitMIDIInstrument lifecycle is unstable under xcodebuild's
/// macOS test host (see `AudioInstrumentHostTests`), so we test at two narrower seams:
///
/// 1. The pure `AUPresetDescriptor.descriptors` / `.resolve` helpers — this is where the
///    id synthesis and preset lookup live.
/// 2. The no-live-AU paths on the host directly: readout returns `nil`, load throws
///    `presetNotFound`.
@MainActor
final class AudioInstrumentHostPresetsTests: XCTestCase {

    // MARK: – Descriptor mapping (pure)

    func test_descriptors_empty_lists_return_empty_arrays_not_nil() {
        let result = AUPresetDescriptor.descriptors(factoryPresets: [], userPresets: [])
        XCTAssertEqual(result.factory, [])
        XCTAssertEqual(result.user, [])
    }

    func test_descriptors_nil_factoryPresets_returns_empty_factory_array() {
        let result = AUPresetDescriptor.descriptors(factoryPresets: nil, userPresets: [])
        XCTAssertEqual(result.factory, [])
        XCTAssertEqual(result.user, [])
    }

    func test_descriptors_maps_factory_presets_with_factory_id_prefix() {
        let presets = [
            makePreset(number: 0, name: "Init"),
            makePreset(number: 3, name: "Analog Keys"),
            makePreset(number: 42, name: "Mega Bass")
        ]
        let result = AUPresetDescriptor.descriptors(factoryPresets: presets, userPresets: [])

        XCTAssertEqual(result.factory.count, 3)
        XCTAssertEqual(result.factory[0], .factory(number: 0, name: "Init"))
        XCTAssertEqual(result.factory[1], .factory(number: 3, name: "Analog Keys"))
        XCTAssertEqual(result.factory[2], .factory(number: 42, name: "Mega Bass"))
        XCTAssertTrue(result.factory.allSatisfy { $0.id.hasPrefix("factory:") })
        XCTAssertEqual(result.factory[1].id, "factory:3")
    }

    func test_descriptors_maps_user_presets_with_user_id_prefix() {
        let presets = [
            makePreset(number: -1, name: "My Pad"),
            makePreset(number: -3, name: "Session Bass")
        ]
        let result = AUPresetDescriptor.descriptors(factoryPresets: nil, userPresets: presets)

        XCTAssertEqual(result.user.count, 2)
        XCTAssertEqual(result.user[0], .user(number: -1, name: "My Pad"))
        XCTAssertEqual(result.user[1], .user(number: -3, name: "Session Bass"))
        XCTAssertTrue(result.user.allSatisfy { $0.id.hasPrefix("user:") })
        XCTAssertEqual(result.user[0].id, "user:-1:My Pad")
    }

    func test_descriptors_user_presets_preserve_au_preset_number() {
        let presets = [makePreset(number: -1, name: "X"), makePreset(number: -7, name: "Y")]
        let result = AUPresetDescriptor.descriptors(factoryPresets: nil, userPresets: presets)

        XCTAssertEqual(result.user[0].number, -1)
        XCTAssertEqual(result.user[1].number, -7,
                       "User descriptor number must reflect the AU's actual negative preset number for disambiguation")
    }

    // MARK: – Current id synthesis

    func test_id_forCurrent_returns_nil_when_no_preset() {
        XCTAssertNil(AUPresetDescriptor.id(forCurrent: nil))
    }

    func test_id_forCurrent_factory_uses_number_convention() {
        let preset = makePreset(number: 7, name: "Lead")
        XCTAssertEqual(AUPresetDescriptor.id(forCurrent: preset), "factory:7")
    }

    func test_id_forCurrent_user_uses_number_and_name_convention() {
        let preset = makePreset(number: -3, name: "My Pad")
        XCTAssertEqual(AUPresetDescriptor.id(forCurrent: preset), "user:-3:My Pad")
    }

    // MARK: – Resolve (pure)

    func test_resolve_returns_matching_factory_preset_by_number() {
        let a = makePreset(number: 0, name: "Init")
        let b = makePreset(number: 3, name: "Analog Keys")
        let c = makePreset(number: 42, name: "Mega Bass")

        let resolved = AUPresetDescriptor.resolve(
            .factory(number: 3, name: "stale-name-ignored"),
            factoryPresets: [a, b, c],
            userPresets: []
        )
        XCTAssertIdentical(resolved, b)
    }

    func test_resolve_factory_returns_nil_when_number_vanished() {
        let a = makePreset(number: 0, name: "Init")

        let resolved = AUPresetDescriptor.resolve(
            .factory(number: 99, name: "Gone"),
            factoryPresets: [a],
            userPresets: []
        )
        XCTAssertNil(resolved, "Vanished factory number must not resolve")
    }

    func test_resolve_user_returns_matching_preset_by_number() {
        let a = makePreset(number: -1, name: "My Pad")
        let b = makePreset(number: -2, name: "Session Bass")

        let resolved = AUPresetDescriptor.resolve(
            .user(number: -2, name: "Session Bass"),
            factoryPresets: nil,
            userPresets: [a, b]
        )
        XCTAssertIdentical(resolved, b)
    }

    func test_resolve_user_returns_nil_when_number_vanished() {
        let a = makePreset(number: -1, name: "My Pad")

        let resolved = AUPresetDescriptor.resolve(
            .user(number: -99, name: "My Pad"),
            factoryPresets: nil,
            userPresets: [a]
        )
        XCTAssertNil(resolved, "Vanished user preset number must not resolve")
    }

    func test_resolve_factory_with_nil_factoryPresets_returns_nil() {
        let resolved = AUPresetDescriptor.resolve(
            .factory(number: 0, name: "Init"),
            factoryPresets: nil,
            userPresets: []
        )
        XCTAssertNil(resolved)
    }

    // MARK: – Duplicate-name user-preset disambiguation

    func test_resolve_user_by_number_disambiguates_duplicate_names() {
        // Two user presets with the same display name but different AU-assigned numbers.
        let lead1 = makePreset(number: -1, name: "Lead")
        let lead2 = makePreset(number: -3, name: "Lead")

        let result = AUPresetDescriptor.descriptors(factoryPresets: nil, userPresets: [lead1, lead2])

        // ids must be distinct even though names are identical
        XCTAssertNotEqual(result.user[0].id, result.user[1].id,
                          "Two user presets with the same name must produce distinct ids")
        XCTAssertEqual(result.user[0].id, "user:-1:Lead")
        XCTAssertEqual(result.user[1].id, "user:-3:Lead")

        // resolve for each must return the right underlying preset
        let resolvedFirst = AUPresetDescriptor.resolve(
            result.user[0],
            factoryPresets: nil,
            userPresets: [lead1, lead2]
        )
        XCTAssertIdentical(resolvedFirst, lead1)

        let resolvedSecond = AUPresetDescriptor.resolve(
            result.user[1],
            factoryPresets: nil,
            userPresets: [lead1, lead2]
        )
        XCTAssertIdentical(resolvedSecond, lead2)
    }

    // MARK: – Program-change bytes (the immediate-switch fix)

    // A few AUs (Arturia Analog Lab V et al.) vend factory presets that are really
    // MIDI program-change SLOTS named literally "ProgramChangeN"; those only switch
    // their live patch on a real MIDI Program Change, not on a bare `currentPreset =`.
    // `loadPreset` sends these bytes via the AU's `scheduleMIDIEventBlock` so such a
    // selection switches the patch immediately. The byte layout is the load-bearing
    // part of that fix.

    func test_programChangeBytes_uses_status_C0_on_channel_0() {
        let bytes = AudioInstrumentHost.programChangeBytes(programNumber: 0)
        XCTAssertEqual(bytes.count, 2, "Program Change is a 2-byte MIDI message")
        XCTAssertEqual(bytes[0], 0xC0, "Status nibble must be Program Change (0xC0) on channel 0")
    }

    func test_programChangeBytes_carries_the_program_number() {
        XCTAssertEqual(AudioInstrumentHost.programChangeBytes(programNumber: 11), [0xC0, 11])
        XCTAssertEqual(AudioInstrumentHost.programChangeBytes(programNumber: 42), [0xC0, 42])
    }

    // MARK: – All-Notes-Off on preset switch (hung-note clear, 20260629-101847)

    func test_allNotesOffBytes_is_CC123_value_0_on_channel_0() {
        let bytes = AudioInstrumentHost.allNotesOffBytes()
        XCTAssertEqual(bytes.count, 3, "All-Notes-Off is a 3-byte Control Change message")
        XCTAssertEqual(bytes[0], 0xB0, "Status nibble must be Control Change (0xB0) on channel 0")
        XCTAssertEqual(bytes[1], 0x7B, "Controller must be All-Notes-Off (123 / 0x7B)")
        XCTAssertEqual(bytes[2], 0x00, "All-Notes-Off carries a 0 value")
    }

    func test_noteVoiceAllocation_keepsSamePitchNoteOffsOnDistinctChannels() {
        let first = AudioInstrumentHost.midiVoiceChannel(forAllocation: 0)
        let second = AudioInstrumentHost.midiVoiceChannel(forAllocation: 1)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(AudioInstrumentHost.noteOnBytes(pitch: 60, velocity: 100, channel: first), [0x90, 60, 100])
        XCTAssertEqual(AudioInstrumentHost.noteOffBytes(pitch: 60, channel: first), [0x80, 60, 0])
        XCTAssertEqual(AudioInstrumentHost.noteOnBytes(pitch: 60, velocity: 100, channel: second), [0x91, 60, 100])
        XCTAssertEqual(AudioInstrumentHost.noteOffBytes(pitch: 60, channel: second), [0x81, 60, 0])
        XCTAssertFalse(AudioInstrumentHost.midiVoiceChannels.contains(9))
    }

    func test_programChangeBytes_clamps_into_legal_0_127_data_range() {
        XCTAssertEqual(AudioInstrumentHost.programChangeBytes(programNumber: 127), [0xC0, 127])
        XCTAssertEqual(AudioInstrumentHost.programChangeBytes(programNumber: 200), [0xC0, 127],
                       "Program number above 127 must clamp to the MIDI data ceiling")
        XCTAssertEqual(AudioInstrumentHost.programChangeBytes(programNumber: -3), [0xC0, 0],
                       "Negative program numbers must clamp to 0")
    }

    // MARK: – ProgramChange name parser / gate decision (the regression guard)

    // The fix is SAFE-BY-CONSTRUCTION: a Program Change is sent ONLY when the
    // factory preset's NAME matches "ProgramChangeN", and the program number is
    // derived from N in the name (the AU's declared program), not from the array
    // index. These tests pin BOTH halves: that quirk slots ARE recognised (with
    // the name-derived number) and — the key regression guard — that NORMAL AU
    // factory preset names are NOT, so a normal AU is never program-changed.

    func test_programNumberFromPresetName_parses_trailing_integer() {
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("ProgramChange7"), 7)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("ProgramChange0"), 0)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("ProgramChange128"), 128,
                       "Parser returns the raw declared number; clamping is programChangeBytes' job")
    }

    func test_programNumberFromPresetName_is_case_insensitive() {
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("programchange7"), 7)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("PROGRAMCHANGE7"), 7)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("ProGramChAnge7"), 7)
    }

    func test_programNumberFromPresetName_tolerates_whitespace() {
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("  ProgramChange7  "), 7)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("ProgramChange 7"), 7)
        XCTAssertEqual(AudioInstrumentHost.programNumberFromPresetName("\tProgramChange\t12\t"), 12)
    }

    func test_programNumberFromPresetName_returns_nil_for_normal_preset_names() {
        // The key regression guard: a normal AU's factory presets must NOT match,
        // so no Program Change is sent and `currentPreset =` stays authoritative.
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Warm Pad"))
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Bright Lead"))
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Bass 3"))
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Init"))
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Mega Bass"))
    }

    func test_programNumberFromPresetName_returns_nil_for_near_miss_names() {
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("Program Bank"),
                     "Must be the literal token 'ProgramChange', not just 'Program'")
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("ProgramChange"),
                     "No trailing number means no derivable program — must not match")
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("ProgramChange7a"),
                     "Trailing non-digit must not match (anchored regex)")
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName("MyProgramChange7"),
                     "Leading text must not match (anchored regex)")
        XCTAssertNil(AudioInstrumentHost.programNumberFromPresetName(""))
    }

    // MARK: – Host no-AU edge cases

    func test_host_presetReadout_returns_nil_when_no_AU_loaded() {
        let host = makeHost()
        XCTAssertNil(host.presetReadout(),
                     "Freshly-created host has no live instrument — readout must be nil")
    }

    func test_host_preparePresetBrowser_without_live_AU_is_noop() {
        let host = makeHost()

        host.preparePresetBrowser()

        XCTAssertNil(host.presetReadout())
    }

    func test_host_loadPreset_throws_presetNotFound_when_no_AU_loaded() {
        let host = makeHost()
        XCTAssertThrowsError(try host.loadPreset(.factory(number: 0, name: "Init"))) { error in
            XCTAssertEqual(error as? PresetLoadingError, .presetNotFound)
        }
    }

    func test_host_loadPreset_throws_presetNotFound_for_user_descriptor_when_no_AU_loaded() {
        let host = makeHost()
        XCTAssertThrowsError(try host.loadPreset(.user(number: -1, name: "My Pad"))) { error in
            XCTAssertEqual(error as? PresetLoadingError, .presetNotFound)
        }
    }

    // MARK: – Helpers

    private func makeHost() -> AudioInstrumentHost {
        AudioInstrumentHost(
            instrumentChoices: [.builtInSynth],
            initialInstrument: .builtInSynth,
            autoStartEngine: false,
            instantiateAudioUnit: { _, completion in
                // Never completes — the test must never call `startIfNeeded()`.
                _ = completion
            }
        )
    }

    private func makePreset(number: Int, name: String) -> AUAudioUnitPreset {
        let preset = AUAudioUnitPreset()
        preset.number = number
        preset.name = name
        return preset
    }
}
