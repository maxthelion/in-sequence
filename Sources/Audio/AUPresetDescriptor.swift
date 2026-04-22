import AVFoundation
import Foundation

/// A host-side representation of a single AU preset, with a stable synthesized `id`.
///
/// Factory preset ids are `"factory:\(number)"`.
/// User preset ids are `"user:\(name)"`.
/// These strings are stable across readouts as long as the preset exists in the AU.
struct AUPresetDescriptor: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// The underlying preset number. -1 for user presets (which are keyed by name).
    let number: Int
    let kind: Kind

    enum Kind: Sendable, Equatable {
        case factory
        case user
    }

    static func factory(number: Int, name: String) -> AUPresetDescriptor {
        AUPresetDescriptor(
            id: "factory:\(number)",
            name: name,
            number: number,
            kind: .factory
        )
    }

    static func user(name: String) -> AUPresetDescriptor {
        AUPresetDescriptor(
            id: "user:\(name)",
            name: name,
            number: -1,
            kind: .user
        )
    }

    /// Maps an AU's factory + user preset lists into descriptor tuples.
    /// An empty-arrays return is a valid state — the AU simply exposes no presets of that kind.
    static func descriptors(
        factoryPresets: [AUAudioUnitPreset]?,
        userPresets: [AUAudioUnitPreset]
    ) -> (factory: [AUPresetDescriptor], user: [AUPresetDescriptor]) {
        let factory = (factoryPresets ?? []).map { AUPresetDescriptor.factory(number: $0.number, name: $0.name) }
        let user = userPresets.map { AUPresetDescriptor.user(name: $0.name) }
        return (factory: factory, user: user)
    }

    /// Looks up the live `AUAudioUnitPreset` that matches `descriptor`, or `nil` if the
    /// preset has vanished from the AU since the descriptor was captured.
    static func resolve(
        _ descriptor: AUPresetDescriptor,
        factoryPresets: [AUAudioUnitPreset]?,
        userPresets: [AUAudioUnitPreset]
    ) -> AUAudioUnitPreset? {
        switch descriptor.kind {
        case .factory:
            return (factoryPresets ?? []).first { $0.number == descriptor.number }
        case .user:
            return userPresets.first { $0.name == descriptor.name }
        }
    }
}

enum PresetLoadingError: Error, Equatable {
    /// The descriptor's id does not match any currently-live preset in the AU.
    /// The AU may have been updated and the preset removed.
    case presetNotFound
}
