import Foundation

typealias StepOrderMapID = UUID

enum StepOrderMapValidationIssue: Equatable, Hashable, Sendable {
    case wrongLength(actual: Int)
    case outOfRange(values: [UInt8])
}

enum StepOrderMapDeletionBlockReason: Equatable, Hashable, Sendable {
    case assignedToPhrases(count: Int)
}

struct StepOrderMapDeletionStatus: Equatable, Hashable, Sendable {
    var mapID: StepOrderMapID
    var assignedPhraseIDs: [UUID]

    var assignmentCount: Int {
        assignedPhraseIDs.count
    }

    var canDelete: Bool {
        assignedPhraseIDs.isEmpty
    }

    var blockedReason: StepOrderMapDeletionBlockReason? {
        guard !canDelete else {
            return nil
        }
        return .assignedToPhrases(count: assignmentCount)
    }
}

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
        self.values = values
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedValues = try container.decode([Int].self, forKey: .values)
        self.init(
            id: try container.decode(StepOrderMapID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            values: Self.quarantinedDecodedValues(decodedValues)
        )
    }

    func renamed(_ name: String) -> StepOrderMap {
        StepOrderMap(id: id, name: name, values: values)
    }

    func withValues(_ values: [UInt8]) -> StepOrderMap {
        StepOrderMap(id: id, name: name, values: values)
    }

    var validationIssue: StepOrderMapValidationIssue? {
        guard values.count == Self.stepCount else {
            return .wrongLength(actual: values.count)
        }

        let invalidValues = values.filter { $0 >= UInt8(Self.stepCount) }
        guard invalidValues.isEmpty else {
            return .outOfRange(values: invalidValues)
        }

        return nil
    }

    var isValid: Bool {
        validationIssue == nil
    }

    var validatedCompiledValues: [UInt8]? {
        isValid ? values : nil
    }

    static func isValidValues(_ values: [UInt8]) -> Bool {
        values.count == stepCount && values.allSatisfy { $0 < UInt8(stepCount) }
    }

    private static func quarantinedDecodedValues(_ values: [Int]) -> [UInt8] {
        guard values.allSatisfy({ (0...Int(UInt8.max)).contains($0) }) else {
            return []
        }
        return values.map(UInt8.init)
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
