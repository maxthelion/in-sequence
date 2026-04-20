import Foundation

struct MIDIEndpointName: Codable, Equatable, Hashable, Sendable {
    let displayName: String
    let isVirtual: Bool

    static let sequencerAIOut = MIDIEndpointName(displayName: "SequencerAI Out", isVirtual: true)
}

struct AudioComponentID: Codable, Equatable, Hashable, Sendable {
    let type: String
    let subtype: String
    let manufacturer: String
    let version: UInt32

    var displayKey: String {
        "\(manufacturer).\(type).\(subtype)"
    }
}

enum InternalSamplerBankID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case drumKitDefault
    case sliceDefault
}

enum Destination: Codable, Equatable, Hashable, Sendable {
    // Adding a case? Audit EngineController routing, AudioInstrumentHost loading,
    // TrackDestinationEditor selection/editing, and Mixer/Inspector summaries.
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case internalSampler(bankID: InternalSamplerBankID, preset: String)
    case sample(sampleID: UUID, settings: SamplerSettings)
    case inheritGroup
    case none

    enum Kind: Equatable, Hashable, Sendable {
        case midi
        case auInstrument
        case internalSampler
        case sample
        case inheritGroup
        case none
    }

    var kind: Kind {
        switch self {
        case .midi:
            return .midi
        case .auInstrument:
            return .auInstrument
        case .internalSampler:
            return .internalSampler
        case .sample:
            return .sample
        case .inheritGroup:
            return .inheritGroup
        case .none:
            return .none
        }
    }

    var kindLabel: String {
        switch kind {
        case .midi:
            return "MIDI"
        case .auInstrument:
            return "AU"
        case .internalSampler:
            return "Internal"
        case .sample:
            return "Sampler"
        case .inheritGroup:
            return "Group"
        case .none:
            return "—"
        }
    }

    var withoutTransientState: Destination {
        switch self {
        case let .auInstrument(componentID, _):
            return .auInstrument(componentID: componentID, stateBlob: nil)
        case .midi, .internalSampler, .sample, .inheritGroup, .none:
            return self
        }
    }

    var midiPort: MIDIEndpointName? {
        if case let .midi(port, _, _) = self {
            return port
        }
        return nil
    }

    var midiChannel: UInt8 {
        if case let .midi(_, channel, _) = self {
            return channel
        }
        return 0
    }

    var midiNoteOffset: Int {
        if case let .midi(_, _, noteOffset) = self {
            return noteOffset
        }
        return 0
    }

    func settingMIDIPort(_ port: MIDIEndpointName?) -> Destination {
        .midi(port: port, channel: midiChannel, noteOffset: midiNoteOffset)
    }

    func settingMIDIChannel(_ channel: UInt8) -> Destination {
        .midi(port: midiPort, channel: channel, noteOffset: midiNoteOffset)
    }

    func settingMIDINoteOffset(_ noteOffset: Int) -> Destination {
        .midi(port: midiPort, channel: midiChannel, noteOffset: noteOffset)
    }

    var summary: String {
        switch self {
        case let .midi(port, channel, noteOffset):
            let destinationLabel = port?.displayName ?? "Unassigned MIDI"
            let offsetLabel = noteOffset == 0 ? "" : " • \(noteOffset > 0 ? "+" : "")\(noteOffset)"
            return "\(destinationLabel) • Ch \(Int(channel) + 1)\(offsetLabel)"
        case let .auInstrument(componentID, _):
            return componentID.displayKey
        case let .internalSampler(bankID, preset):
            return "\(bankID.rawValue) • \(preset)"
        case let .sample(sampleID, settings):
            let gainLabel = settings.gain == 0 ? "" : String(format: " • %+.1f dB", settings.gain)
            return "Sample \(sampleID.uuidString.prefix(8))\(gainLabel)"
        case .inheritGroup:
            return "Inherited from group"
        case .none:
            return "No default destination"
        }
    }
}
