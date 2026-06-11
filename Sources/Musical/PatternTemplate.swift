import Foundation

/// A global library asset: step patterns keyed by part tag, applicable to any
/// drum group by tag matching. Templates store plain step patterns, not
/// clip-pool references — application materializes fresh clips per document.
struct PatternTemplate: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// v1 templates are 16-step on/off patterns.
    static let stepCount = 16

    let id: UUID
    var name: String
    /// Step patterns keyed by part tag. 16 steps in v1.
    var patterns: [VoiceTag: [Bool]]

    // Explicit keyed coding so the step representation can grow later
    // (e.g. swapping [Bool] for a richer step struct) without breaking decode.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case patterns
    }

    init(id: UUID, name: String, patterns: [VoiceTag: [Bool]]) {
        self.id = id
        self.name = name
        self.patterns = patterns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        patterns = try container.decode([VoiceTag: [Bool]].self, forKey: .patterns)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(patterns, forKey: .patterns)
    }
}
