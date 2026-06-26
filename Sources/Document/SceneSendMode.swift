import Foundation

/// The per-track scene-send selector (R4): which scene side(s) a track feeds.
///
/// This is a pure *view* over the two persisted send gains
/// (`TrackMixSettings.sendA` / `.sendB`) — it is NOT a new persisted field. The
/// mode is derived from the gains, and each mode maps back to a preset gain
/// pair. Because R0 made the send nodes permanent, switching mode is pure gain
/// on the fixed graph (no topology change), so a track set to `.a` contributes
/// nothing to scene B by construction, and vice-versa.
///
/// - `.a`   → `(sendA: 1, sendB: 0)` — feeds scene A only.
/// - `.ab`  → `(sendA: 1, sendB: 1)` — feeds both scenes.
/// - `.b`   → `(sendA: 0, sendB: 1)` — feeds scene B only.
///
/// Any other gain combination is "Custom" (no mode) — `sceneSendMode` returns
/// `nil` and a UI selector should show no selection.
enum SceneSendMode: String, CaseIterable, Codable, Sendable {
    case a
    case ab
    case b

    /// The preset send gains for this mode.
    var sendGains: (sendA: Double, sendB: Double) {
        switch self {
        case .a: return (1, 0)
        case .ab: return (1, 1)
        case .b: return (0, 1)
        }
    }

    /// Derive the mode from a send-gain pair. Returns the matching mode only when
    /// the gains equal a preset exactly; otherwise `nil` (Custom).
    init?(sendA: Double, sendB: Double) {
        switch (sendA, sendB) {
        case (1, 0): self = .a
        case (1, 1): self = .ab
        case (0, 1): self = .b
        default: return nil
        }
    }
}

extension TrackMixSettings {
    /// The scene-send mode derived from this track's send gains, or `nil` when
    /// the gains don't match a preset exactly (Custom).
    var sceneSendMode: SceneSendMode? {
        SceneSendMode(sendA: sendA, sendB: sendB)
    }
}
