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
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case internalSampler(bankID: InternalSamplerBankID, preset: String)
    case none

    var kindLabel: String {
        switch self {
        case .midi:
            return "MIDI"
        case .auInstrument:
            return "AU"
        case .internalSampler:
            return "Internal"
        case .none:
            return "—"
        }
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
        case .none:
            return "No default destination"
        }
    }
}
