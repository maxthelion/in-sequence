import AVFoundation
import Foundation

/// Diff-detection shape for an insert's kind, shared across the insert-chain
/// hosts (`MixerBusHost`, `SendBusHost`, `TrackInsertChainHost`).
///
/// This is graph-shape metadata only: it mirrors `MasterBusInsertKind` so the
/// hosts can compare an installed chain against a desired chain without holding
/// onto live document state. `MasterBusHost` intentionally keeps its own
/// `MasterBusInsertKindShape` (a structurally identical but separate type);
/// unifying the two is a deliberate future change, not part of this dedup.
enum InsertKindShape: Equatable {
    case nativeFilter
    case nativeBitcrusher
    case auEffect(componentID: AudioComponentID, stateBlob: Data?)

    /// Maps a document insert kind to its diff-detection shape. Pure mapping —
    /// no allocation beyond the enum case, never called on a render callback.
    static func make(for kind: MasterBusInsertKind) -> InsertKindShape {
        switch kind {
        case .nativeFilter:
            return .nativeFilter
        case .nativeBitcrusher:
            return .nativeBitcrusher
        case let .auEffect(componentID, stateBlob):
            return .auEffect(componentID: componentID, stateBlob: stateBlob)
        }
    }
}
