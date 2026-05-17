import Foundation

enum SendBusID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case sendA = "send-a"
    case sendB = "send-b"

    var displayName: String {
        switch self {
        case .sendA: return "Send A"
        case .sendB: return "Send B"
        }
    }
}

struct SendBusState: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let sendA = SendBusState(id: .sendA)
    static let sendB = SendBusState(id: .sendB)

    var id: SendBusID
    var name: String
    var inserts: [SendBusInsert]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case inserts
    }

    init(id: SendBusID, inserts: [SendBusInsert] = []) {
        self.id = id
        self.name = id.displayName
        self.inserts = Self.normalizedInserts(inserts)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(SendBusID.self, forKey: .id),
            inserts: try container.decodeIfPresent([SendBusInsert].self, forKey: .inserts) ?? []
        )
    }

    func normalized(expectedID: SendBusID? = nil) -> SendBusState {
        SendBusState(id: expectedID ?? id, inserts: inserts)
    }

    private static func normalizedInserts(_ inserts: [SendBusInsert]) -> [SendBusInsert] {
        var seenIDs = Set<UUID>()
        return inserts.map { insert in
            var normalized = insert.normalized()
            if seenIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            seenIDs.insert(normalized.id)
            return normalized
        }
    }
}
