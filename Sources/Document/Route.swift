import Foundation

struct Route: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var source: RouteSource
    var filter: RouteFilter
    var destination: RouteDestination
    var enabled: Bool

    init(
        id: UUID = UUID(),
        source: RouteSource,
        filter: RouteFilter = .all,
        destination: RouteDestination,
        enabled: Bool = true
    ) {
        self.id = id
        self.source = source
        self.filter = filter
        self.destination = destination
        self.enabled = enabled
    }
}

enum RouteSource: Codable, Equatable, Hashable, Sendable {
    case track(UUID)
    case chordGenerator(UUID)
}

enum RouteFilter: Codable, Equatable, Hashable, Sendable {
    case all
    case voiceTag(VoiceTag)
    case noteRange(lo: UInt8, hi: UInt8)

    func matches(_ event: NoteEvent) -> Bool {
        switch self {
        case .all:
            return true
        case let .voiceTag(tag):
            return event.voiceTag == tag
        case let .noteRange(lo, hi):
            return event.pitch >= lo && event.pitch <= hi
        }
    }
}

enum RouteDestination: Codable, Equatable, Hashable, Sendable {
    case voicing(UUID)
    case trackInput(UUID, tag: VoiceTag?)
    case midi(port: MIDIEndpointName, channel: UInt8, noteOffset: Int)
    case chordContext(broadcastTag: String?)

    var targetTrackID: UUID? {
        switch self {
        case let .voicing(trackID), let .trackInput(trackID, _):
            return trackID
        case .midi, .chordContext:
            return nil
        }
    }
}

extension Route {
    func description(trackLookup: (UUID) -> StepSequenceTrack?) -> String {
        let sourceDescription: String
        switch source {
        case let .track(trackID):
            sourceDescription = "\(trackLookup(trackID)?.name ?? "Track") notes"
        case let .chordGenerator(trackID):
            sourceDescription = "\(trackLookup(trackID)?.name ?? "Track") chord lane"
        }

        let filterDescription: String
        switch filter {
        case .all:
            filterDescription = "all events"
        case let .voiceTag(tag):
            filterDescription = "voice tag \(tag)"
        case let .noteRange(lo, hi):
            filterDescription = "notes \(lo)-\(hi)"
        }

        return "\(sourceDescription) • \(filterDescription)"
    }
}

extension RouteDestination {
    func title(trackLookup: (UUID) -> StepSequenceTrack?) -> String {
        switch self {
        case let .voicing(trackID):
            return "\(trackLookup(trackID)?.name ?? "Track") default destination"
        case let .trackInput(trackID, tag):
            if let tag, !tag.isEmpty {
                return "\(trackLookup(trackID)?.name ?? "Track") input • \(tag)"
            }
            return "\(trackLookup(trackID)?.name ?? "Track") input"
        case let .midi(port, channel, noteOffset):
            let offsetLabel = noteOffset == 0 ? "" : " • \(noteOffset > 0 ? "+" : "")\(noteOffset)"
            return "\(port.displayName) • Ch \(Int(channel) + 1)\(offsetLabel)"
        case let .chordContext(tag):
            return tag.map { "Chord lane • \($0)" } ?? "Default chord lane"
        }
    }
}
