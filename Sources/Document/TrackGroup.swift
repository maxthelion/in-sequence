import Foundation

typealias TrackGroupID = UUID

enum DrumTriggerMappingMode: String, Codable, Equatable, Sendable {
    case perNote
    case perChannel
    case individual
}

struct TrackGroup: Codable, Equatable, Identifiable, Sendable {
    var id: TrackGroupID
    var name: String
    var color: String
    var memberIDs: [UUID]
    var sharedDestination: Destination?
    var triggerMappingMode: DrumTriggerMappingMode
    var noteMapping: [UUID: Int]
    var channelMapping: [UUID: UInt8]
    var mute: Bool
    var solo: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case memberIDs
        case sharedDestination
        case triggerMappingMode
        case noteMapping
        case channelMapping
        case mute
        case solo
    }

    init(
        id: TrackGroupID = UUID(),
        name: String,
        color: String = "#8AA",
        memberIDs: [UUID] = [],
        sharedDestination: Destination? = nil,
        triggerMappingMode: DrumTriggerMappingMode = .perNote,
        noteMapping: [UUID: Int] = [:],
        channelMapping: [UUID: UInt8] = [:],
        mute: Bool = false,
        solo: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.memberIDs = memberIDs
        self.sharedDestination = sharedDestination
        self.triggerMappingMode = triggerMappingMode
        self.noteMapping = noteMapping
        self.channelMapping = channelMapping
        self.mute = mute
        self.solo = solo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(TrackGroupID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#8AA"
        memberIDs = try container.decodeIfPresent([UUID].self, forKey: .memberIDs) ?? []
        sharedDestination = try container.decodeIfPresent(Destination.self, forKey: .sharedDestination)
        triggerMappingMode = try container.decodeIfPresent(DrumTriggerMappingMode.self, forKey: .triggerMappingMode) ?? .perNote
        noteMapping = try container.decodeIfPresent([UUID: Int].self, forKey: .noteMapping) ?? [:]
        channelMapping = try container.decodeIfPresent([UUID: UInt8].self, forKey: .channelMapping) ?? [:]
        mute = try container.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo) ?? false
    }
}
