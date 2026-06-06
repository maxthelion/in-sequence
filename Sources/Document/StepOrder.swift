import Foundation

typealias StepOrderMapID = UUID

struct StepOrderMap: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let stepCount = 16
    static let identityValues: [UInt8] = Array(0..<UInt8(stepCount))

    var id: StepOrderMapID
    var name: String
    var values: [UInt8]

    init(
        id: StepOrderMapID = UUID(),
        name: String,
        values: [UInt8] = StepOrderMap.identityValues
    ) {
        self.id = id
        self.name = name
        self.values = Self.fixedLengthValues(values)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(StepOrderMapID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            values: try container.decode([UInt8].self, forKey: .values)
        )
    }

    func renamed(_ name: String) -> StepOrderMap {
        StepOrderMap(id: id, name: name, values: values)
    }

    func withValues(_ values: [UInt8]) -> StepOrderMap {
        StepOrderMap(id: id, name: name, values: values)
    }

    private static func fixedLengthValues(_ values: [UInt8]) -> [UInt8] {
        var fixed = Array(values.prefix(stepCount))
        if fixed.count < stepCount {
            fixed.append(contentsOf: identityValues.dropFirst(fixed.count))
        }
        return fixed
    }
}

struct StepOrderAssignment: Codable, Equatable, Hashable, Sendable {
    var mapID: StepOrderMapID
    var isEnabled: Bool

    init(mapID: StepOrderMapID, isEnabled: Bool) {
        self.mapID = mapID
        self.isEnabled = isEnabled
    }
}
