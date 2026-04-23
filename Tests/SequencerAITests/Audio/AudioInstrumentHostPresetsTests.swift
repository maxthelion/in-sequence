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

    // MARK: – Host no-AU edge cases

    func test_host_presetReadout_returns_nil_when_no_AU_loaded() {
        let host = makeHost()
        XCTAssertNil(host.presetReadout(),
                     "Freshly-created host has no live instrument — readout must be nil")
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
