import Foundation

typealias TrackGroupID = UUID

struct BusRef: Codable, Equatable, Hashable, Sendable {
    var id: String

    init(id: String) {
        self.id = id
    }
}

struct TrackGroup: Codable, Equatable, Identifiable, Sendable {
    var id: TrackGroupID
    var name: String
    var color: String
    var memberIDs: [UUID]
    var sharedDestination: Destination?
    var noteMapping: [UUID: Int]
    var mute: Bool
    var solo: Bool
    var busSink: BusRef?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case memberIDs
        case sharedDestination
        case noteMapping
        case mute
        case solo
        case busSink
    }

    init(
        id: TrackGroupID = UUID(),
        name: String,
        color: String = "#8AA",
        memberIDs: [UUID] = [],
        sharedDestination: Destination? = nil,
        noteMapping: [UUID: Int] = [:],
        mute: Bool = false,
        solo: Bool = false,
        busSink: BusRef? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.memberIDs = memberIDs
        self.sharedDestination = sharedDestination
        self.noteMapping = noteMapping
        self.mute = mute
        self.solo = solo
        self.busSink = busSink
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(TrackGroupID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#8AA"
        memberIDs = try container.decodeIfPresent([UUID].self, forKey: .memberIDs) ?? []
        sharedDestination = try container.decodeIfPresent(Destination.self, forKey: .sharedDestination)
        noteMapping = try container.decodeIfPresent([UUID: Int].self, forKey: .noteMapping) ?? [:]
        mute = try container.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        busSink = try container.decodeIfPresent(BusRef.self, forKey: .busSink)
    }
}
