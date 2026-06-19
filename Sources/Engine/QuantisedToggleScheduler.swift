import Foundation

/// Identity of an armed quantised toggle: one slot per (kind, track). A
/// second arm of an occupied key CANCELS the armed change (tap-while-armed
/// = cancel, the Rytm mute-preselect grammar).
struct QuantisedToggleKey: Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Sendable {
        case mute
        case fillCue
    }

    let kind: Kind
    let trackID: UUID
}

/// One quantised perform change. Mute carries its target value and the basis
/// phrase captured at arm time (the same capture-at-arm shape as the
/// step-order toggle's enabledMapValues) so the main-side mirror can stage
/// the document record after the engine applies at the boundary. A fill cue
/// is engine-runtime only: it plays the cued bar and auto-expires (Rytm
/// "cue for one cycle" — fill's third gesture).
enum QuantisedToggleChange: Equatable, Hashable, Sendable {
    case mute(trackID: UUID, muted: Bool, basisPhraseID: UUID)
    case lengthLimitedMute(trackID: UUID, muted: Bool, basisPhraseID: UUID, lengthBars: Int, startTick: UInt64?)
    case fillFlag(trackID: UUID, enabled: Bool, basisPhraseID: UUID, lengthBars: Int?, startTick: UInt64?)
    case fillCue(trackID: UUID)

    var trackID: UUID {
        switch self {
        case let .mute(trackID, _, _):
            return trackID
        case let .lengthLimitedMute(trackID, _, _, _, _):
            return trackID
        case let .fillFlag(trackID, _, _, _, _):
            return trackID
        case let .fillCue(trackID):
            return trackID
        }
    }

    var key: QuantisedToggleKey {
        switch self {
        case let .mute(trackID, _, _):
            return QuantisedToggleKey(kind: .mute, trackID: trackID)
        case let .lengthLimitedMute(trackID, _, _, _, _):
            return QuantisedToggleKey(kind: .mute, trackID: trackID)
        case let .fillFlag(trackID, _, _, _, _):
            return QuantisedToggleKey(kind: .fillCue, trackID: trackID)
        case let .fillCue(trackID):
            return QuantisedToggleKey(kind: .fillCue, trackID: trackID)
        }
    }
}

enum QuantisedToggleArmResult: Equatable {
    /// The change is armed and will commit at the next bar boundary.
    case armed
    /// A change with the same key was already armed; the tap cancelled it.
    case cancelled
    /// The transport is not running; the caller should apply immediately.
    case rejected
}

/// Engine-side pending-change scheduler for quantised perform toggles
/// (perform/setup split slice 2). Generalises the engine's established
/// pending-at-boundary idiom (audio-input `pendingLoopStartTick`, step-order
/// pendingOn/pendingOff at the phrase boundary):
///
/// - Changes ARM from the main thread and COMMIT on the tick that crosses
///   the next bar boundary (`prepareTick` of the bar-start tick), so the
///   first step of the new bar already plays the new state.
/// - All changes armed in the same window land on the same boundary
///   together — atomic group commit (Rytm mute-preselect semantics).
/// - Arming an already-armed key cancels it (tap-while-armed = cancel).
/// - Committed mute changes stay live as overrides until the main-side
///   document staging reinstalls a snapshot that encodes them
///   (`confirmMuteApplied`), so the boundary tick is never prepared with
///   stale mute state while main catches up.
/// - Committed fill cues are active for exactly one bar and expire at the
///   following boundary.
///
/// Every method is lock-protected and safe from main or the tick queue;
/// nothing here waits on main (TickPathMainSyncGuard-safe by construction).
final class QuantisedToggleScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var armedByKey: [QuantisedToggleKey: QuantisedToggleChange] = [:]
    /// Commit order matches arm order, so handlers observe a stable sequence.
    private var armedKeyOrder: [QuantisedToggleKey] = []
    private var muteOverridesByTrackID: [UUID: Bool] = [:]
    private var fillFlagOverridesByTrackID: [UUID: Bool] = [:]
    private var fillCueExpiryTickByTrackID: [UUID: UInt64] = [:]

    // MARK: - Main-side arming

    @discardableResult
    func armOrCancel(_ change: QuantisedToggleChange) -> QuantisedToggleArmResult {
        lock.lock()
        defer { lock.unlock() }
        let key = change.key
        if armedByKey.removeValue(forKey: key) != nil {
            armedKeyOrder.removeAll { $0 == key }
            return .cancelled
        }
        armedByKey[key] = change
        armedKeyOrder.append(key)
        return .armed
    }

    func isArmed(_ key: QuantisedToggleKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return armedByKey[key] != nil
    }

    func armedChanges() -> [QuantisedToggleChange] {
        lock.lock()
        defer { lock.unlock() }
        return armedKeyOrder.compactMap { armedByKey[$0] }
    }

    func cancelAllArmed() {
        lock.lock()
        defer { lock.unlock() }
        armedByKey.removeAll()
        armedKeyOrder.removeAll()
    }

    /// Main confirms the committed mute changes are encoded in an installed
    /// playback snapshot; the live overrides retire.
    func confirmMuteApplied(trackIDs: [UUID]) {
        lock.lock()
        defer { lock.unlock() }
        for trackID in trackIDs {
            muteOverridesByTrackID.removeValue(forKey: trackID)
        }
    }

    /// Main confirms committed fill-flag changes are encoded in an installed
    /// playback snapshot; the live override can retire.
    func confirmFillFlagApplied(trackIDs: [UUID]) {
        lock.lock()
        defer { lock.unlock() }
        for trackID in trackIDs {
            fillFlagOverridesByTrackID.removeValue(forKey: trackID)
        }
    }

    /// Full reset for transport stop / document replacement: armed changes
    /// can no longer reach a boundary, overrides have no snapshot to retire
    /// against, and cues lose their timeline.
    func resetRuntime() {
        lock.lock()
        defer { lock.unlock() }
        armedByKey.removeAll()
        armedKeyOrder.removeAll()
        muteOverridesByTrackID.removeAll()
        fillFlagOverridesByTrackID.removeAll()
        fillCueExpiryTickByTrackID.removeAll()
    }

    // MARK: - Tick-path application

    /// Called from `prepareTick` with the upcoming transport tick. On a bar
    /// boundary it drains every armed change into live state (group commit)
    /// and returns the committed changes; off-boundary ticks return [].
    /// Expired fill cues are cleaned up on the same call.
    func commitAtBarBoundary(upcomingTick: UInt64, ticksPerBar: Int) -> [QuantisedToggleChange] {
        let barLength = UInt64(max(1, ticksPerBar))
        lock.lock()
        defer { lock.unlock() }

        fillCueExpiryTickByTrackID = fillCueExpiryTickByTrackID.filter { $0.value > upcomingTick }

        guard upcomingTick % barLength == 0, !armedKeyOrder.isEmpty else {
            return []
        }

        let armed = armedKeyOrder.compactMap { armedByKey[$0] }
        armedByKey.removeAll()
        armedKeyOrder.removeAll()

        var committed: [QuantisedToggleChange] = []
        for change in armed {
            switch change {
            case let .mute(trackID, muted, _):
                muteOverridesByTrackID[trackID] = muted
                committed.append(change)
            case let .lengthLimitedMute(trackID, muted, basisPhraseID, lengthBars, _):
                muteOverridesByTrackID[trackID] = muted
                committed.append(.lengthLimitedMute(
                    trackID: trackID,
                    muted: muted,
                    basisPhraseID: basisPhraseID,
                    lengthBars: max(1, lengthBars),
                    startTick: upcomingTick
                ))
            case let .fillFlag(trackID, enabled, basisPhraseID, lengthBars, _):
                fillFlagOverridesByTrackID[trackID] = enabled
                committed.append(.fillFlag(
                    trackID: trackID,
                    enabled: enabled,
                    basisPhraseID: basisPhraseID,
                    lengthBars: lengthBars.map { max(1, $0) },
                    startTick: upcomingTick
                ))
            case let .fillCue(trackID):
                fillCueExpiryTickByTrackID[trackID] = upcomingTick &+ barLength
                committed.append(change)
            }
        }
        return committed
    }

    /// Mute values the tick path must hear instead of the layer snapshot's,
    /// until main confirms the staged document record.
    func activeMuteOverrides() -> [UUID: Bool] {
        lock.lock()
        defer { lock.unlock() }
        return muteOverridesByTrackID
    }

    /// Fill-flag values the tick path must hear instead of the layer snapshot's,
    /// until main confirms the staged document record.
    func activeFillFlagOverrides() -> [UUID: Bool] {
        lock.lock()
        defer { lock.unlock() }
        return fillFlagOverridesByTrackID
    }

    /// Tracks whose cued fill bar covers `tick`.
    func activeFillCueTrackIDs(atTick tick: UInt64) -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        return Set(fillCueExpiryTickByTrackID.filter { $0.value > tick }.keys)
    }
}
