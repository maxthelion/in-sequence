import Foundation

/// Which global library a pooled reference resolves against.
enum PooledAssetKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    /// `AudioSampleLibrary` asset — breaks, recordings, and per-voice samples.
    case sample
    /// `DrumAssetLibrary` kit.
    case drumKit
    /// `DrumAssetLibrary` pattern template.
    case patternTemplate
    /// Global step-order map manifest.
    case stepOrderMap

    var displayName: String {
        switch self {
        case .sample: return "Samples"
        case .drumKit: return "Drum Kits"
        case .patternTemplate: return "Pattern Templates"
        case .stepOrderMap: return "Step Order Maps"
        }
    }
}

/// A project-pool entry: a stable reference into the global library
/// (reference, not copy — documents stay small; a missing asset renders as a
/// marked missing entry, never a crash).
struct PooledAssetRef: Codable, Equatable, Hashable, Identifiable, Sendable {
    var kind: PooledAssetKind
    var assetID: UUID
    var addedAt: Date

    /// Composite identity: the same asset ID could theoretically appear under
    /// two kinds, and the pool treats those as distinct entries.
    var id: String {
        "\(kind.rawValue):\(assetID.uuidString)"
    }

    init(kind: PooledAssetKind, assetID: UUID, addedAt: Date = Date()) {
        self.kind = kind
        self.assetID = assetID
        // Whole-second precision so a value survives JSON round-trips
        // unchanged (document equality drives flush/undo comparisons).
        self.addedAt = Date(timeIntervalSince1970: addedAt.timeIntervalSince1970.rounded(.down))
    }
}

extension Project {
    /// Add a global asset to the project pool. No-op if already pooled.
    /// - Returns: `true` if the pool changed.
    @discardableResult
    mutating func addToAssetPool(kind: PooledAssetKind, assetID: UUID, addedAt: Date = Date()) -> Bool {
        guard !isInAssetPool(kind: kind, assetID: assetID) else {
            return false
        }
        assetPool.append(PooledAssetRef(kind: kind, assetID: assetID, addedAt: addedAt))
        return true
    }

    /// Remove a pooled reference. Never touches the global asset on disk.
    /// - Returns: `true` if a matching entry was removed.
    @discardableResult
    mutating func removeFromAssetPool(kind: PooledAssetKind, assetID: UUID) -> Bool {
        let countBefore = assetPool.count
        assetPool.removeAll { $0.kind == kind && $0.assetID == assetID }
        return assetPool.count != countBefore
    }

    func isInAssetPool(kind: PooledAssetKind, assetID: UUID) -> Bool {
        assetPool.contains { $0.kind == kind && $0.assetID == assetID }
    }

    func pooledAssetIDs(kind: PooledAssetKind) -> Set<UUID> {
        Set(assetPool.filter { $0.kind == kind }.map(\.assetID))
    }
}
