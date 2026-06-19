import Foundation

/// A single insert effect in a track's per-track FX chain.
///
/// This is the new model concept introduced by the track-view-IA work: FX
/// previously lived only on buses / master / scenes. Each track now owns an
/// ordered chain of inserts, each one bypassable independently.
///
/// The effect reference mirrors `MasterBusInsertKind` (the representation
/// already used for bus/master/scene inserts) so the existing AU-effect engine
/// host path can be reused when the chain is wired into the audio graph.
struct TrackFXInsert: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var bypassed: Bool
    var kind: MasterBusInsertKind

    init(
        id: UUID = UUID(),
        name: String,
        bypassed: Bool = false,
        kind: MasterBusInsertKind
    ) {
        self.id = id
        self.name = name
        self.bypassed = bypassed
        self.kind = kind
    }

    static func filter() -> TrackFXInsert {
        TrackFXInsert(name: "Filter", kind: .nativeFilter(.default))
    }

    static func bitcrusher() -> TrackFXInsert {
        TrackFXInsert(name: "Bitcrusher", kind: .nativeBitcrusher(.default))
    }

    static func auEffect(_ choice: AudioEffectChoice) -> TrackFXInsert {
        TrackFXInsert(
            name: choice.displayName,
            kind: .auEffect(componentID: choice.audioComponentID, stateBlob: nil)
        )
    }

    /// Short type/parameter descriptor shown as the row subtitle.
    var subtitle: String {
        kind.summary
    }

    func normalized() -> TrackFXInsert {
        var copy = self
        let trimmed = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = trimmed.isEmpty ? copy.kind.defaultName : trimmed
        copy.kind = copy.kind.normalized()
        return copy
    }

    static func normalizedChain(_ inserts: [TrackFXInsert]) -> [TrackFXInsert] {
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
