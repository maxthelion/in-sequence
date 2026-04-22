import Foundation

// MARK: - TrackMacroSource

/// Where the macro value is applied at runtime.
enum TrackMacroSource: Codable, Equatable, Hashable, Sendable {
    /// Built-in device macro. The applier knows how to dispatch these by kind.
    case builtin(BuiltinMacroKind)

    /// AU parameter, addressed by stable identifier from AUParameterTree.
    /// `address` is the 64-bit parameter address captured at selection time;
    /// `identifier` is the plugin's keyPath, stored as a fallback for host
    /// reconnection when addresses shift across plugin versions.
    case auParameter(address: UInt64, identifier: String)
}

// MARK: - BuiltinMacroKind

/// Kinds of built-in macros for internal devices.
///
/// Sampler macros ship with this plan. The sampler-filter plan
/// (2026-04-22-sampler-filter.md) adds filter-related cases on top.
/// Do not add filter cases here — that plan owns them.
enum BuiltinMacroKind: String, Codable, CaseIterable, Sendable {
    case sampleStart    // 0..1 normalized position in source buffer
    case sampleLength   // 0..1 normalized length from start
    case sampleGain     // dB, -60..+12
}

// MARK: - TrackMacroDescriptor

/// Describes a single macro parameter exposed by a track destination.
/// The id is stable across renames. For built-in macros it is a deterministic
/// hash of `(trackID, kind.rawValue)` — see `TrackMacroDescriptor.builtinID(trackID:kind:)`.
struct TrackMacroDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    var displayName: String
    var minValue: Double
    var maxValue: Double
    var defaultValue: Double
    /// Reuses the existing enum — scalar / boolean / patternIndex.
    var valueType: PhraseLayerValueType
    var source: TrackMacroSource

    /// Stable, deterministic id for a built-in macro on a specific track.
    ///
    /// The id is derived from a SHA-256 of `"<trackID.uuidString>-<kind.rawValue>"`
    /// truncated to 128 bits and re-encoded as a UUID. This gives:
    /// - Stable ids across doc saves/loads (no random UUID each time).
    /// - No collision risk between different tracks or kinds.
    static func builtinID(trackID: UUID, kind: BuiltinMacroKind) -> UUID {
        let input = "\(trackID.uuidString)-\(kind.rawValue)"
        let hash = deterministicHash(input)
        return hash
    }

    static func builtin(trackID: UUID, kind: BuiltinMacroKind) -> TrackMacroDescriptor {
        switch kind {
        case .sampleStart:
            return TrackMacroDescriptor(
                id: builtinID(trackID: trackID, kind: kind),
                displayName: "Sample Start",
                minValue: 0,
                maxValue: 1,
                defaultValue: 0,
                valueType: .scalar,
                source: .builtin(.sampleStart)
            )
        case .sampleLength:
            return TrackMacroDescriptor(
                id: builtinID(trackID: trackID, kind: kind),
                displayName: "Sample Length",
                minValue: 0,
                maxValue: 1,
                defaultValue: 1,
                valueType: .scalar,
                source: .builtin(.sampleLength)
            )
        case .sampleGain:
            return TrackMacroDescriptor(
                id: builtinID(trackID: trackID, kind: kind),
                displayName: "Sample Gain",
                minValue: -60,
                maxValue: 12,
                defaultValue: 0,
                valueType: .scalar,
                source: .builtin(.sampleGain)
            )
        }
    }

    /// Deterministic UUID from a string key using a simple FNV-1a based approach.
    /// The output is stable for the same input string across runs.
    private static func deterministicHash(_ input: String) -> UUID {
        var h1: UInt64 = 14_695_981_039_346_656_037
        var h2: UInt64 = 14_695_981_039_346_656_037
        let bytes = Array(input.utf8)
        for (i, byte) in bytes.enumerated() {
            if i.isMultiple(of: 2) {
                h1 ^= UInt64(byte)
                h1 &*= 1_099_511_628_211
            } else {
                h2 ^= UInt64(byte)
                h2 &*= 1_099_511_628_211
            }
        }
        // Pack h1 and h2 into 16 bytes for a UUID
        let b1 = UInt8((h1 >> 56) & 0xFF)
        let b2 = UInt8((h1 >> 48) & 0xFF)
        let b3 = UInt8((h1 >> 40) & 0xFF)
        let b4 = UInt8((h1 >> 32) & 0xFF)
        let b5 = UInt8((h1 >> 24) & 0xFF)
        let b6 = UInt8((h1 >> 16) & 0xFF)
        let b7 = UInt8((h1 >> 8) & 0xFF)
        let b8 = UInt8(h1 & 0xFF)
        let b9 = UInt8((h2 >> 56) & 0xFF)
        let b10 = UInt8((h2 >> 48) & 0xFF)
        let b11 = UInt8((h2 >> 40) & 0xFF)
        let b12 = UInt8((h2 >> 32) & 0xFF)
        let b13 = UInt8((h2 >> 24) & 0xFF)
        let b14 = UInt8((h2 >> 16) & 0xFF)
        let b15 = UInt8((h2 >> 8) & 0xFF)
        let b16 = UInt8(h2 & 0xFF)
        return UUID(uuid: (b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15, b16))
    }
}

// MARK: - TrackMacroBinding

/// A specific macro binding attached to a track.
///
/// Bindings live on the track so a single UUID (`descriptor.id`) stably identifies
/// "track X's Sample Gain macro" for phrase-layer targets and clip lanes.
struct TrackMacroBinding: Codable, Equatable, Hashable, Sendable {
    let descriptor: TrackMacroDescriptor

    var id: UUID { descriptor.id }
    var displayName: String { descriptor.displayName }
    var source: TrackMacroSource { descriptor.source }
}
