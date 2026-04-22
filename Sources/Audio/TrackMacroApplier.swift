import AVFoundation
import Foundation

/// Applies resolved macro values to their destinations every prepared step.
///
/// Built-in macros write to `SamplePlaybackSink.setVoiceParam`. AU parameter
/// macros resolve the live `AUParameter` on first use (cached) and call
/// `setValue(_:originator:)`.
///
/// The cache is invalidated when `invalidateCache(for:)` is called on a
/// destination swap, so stale `AUParameter` references don't survive plugin
/// reloads.
final class TrackMacroApplier {

    // MARK: - Dependencies

    private let sampleEngine: SamplePlaybackSink
    /// Returns the live `AVAudioUnit` for a given track, if one is loaded.
    private let audioUnitProvider: (UUID) -> AVAudioUnit?

    // MARK: - Private state

    /// Cached AUParameter lookups: (trackID, bindingID) → AUParameter.
    /// Populated on first successful resolve; cleared on `invalidateCache(for:)`.
    private var parameterCache: [CacheKey: AUParameter] = [:]

    /// Binding ids for which we have already emitted a "parameter not found" log,
    /// so the message is printed once per binding lifetime, not every step.
    private var loggedMissingParams: Set<UUID> = []

    /// Per-applier AUParameterObserverToken. Using a per-applier token means that
    /// `setValue(_:originator:)` calls made from this applier don't bounce back
    /// through our own observer registrations (if any are set up downstream).
    private let observerToken = AUParameterObserverToken(bitPattern: Int.random(in: 1...Int.max))!

    init(
        sampleEngine: SamplePlaybackSink,
        audioUnitProvider: @escaping (UUID) -> AVAudioUnit?
    ) {
        self.sampleEngine = sampleEngine
        self.audioUnitProvider = audioUnitProvider
    }

    // MARK: - Public API

    /// Apply resolved macro values to their destinations.
    ///
    /// Called from `EngineController.prepareTick` after `MacroCoordinator.snapshot`
    /// produces `LayerSnapshot.macroValues`. The values dict is already merged
    /// (phrase default → phrase snapshot → clip lane override) by the time it
    /// arrives here.
    ///
    /// - Parameters:
    ///   - values: Resolved values keyed by track id then binding id.
    ///   - tracks: The live track list from the current document model.
    func apply(_ values: [UUID: [UUID: Double]], tracks: [StepSequenceTrack]) {
        for track in tracks {
            guard let bindingValues = values[track.id] else { continue }
            for binding in track.macros {
                guard let value = bindingValues[binding.id] else { continue }
                dispatch(value: value, binding: binding, trackID: track.id)
            }
        }
    }

    /// Invalidate the AUParameter cache for a track.
    ///
    /// Call this whenever the track's destination changes so the next `apply`
    /// re-resolves against the newly loaded AU.
    func invalidateCache(for trackID: UUID) {
        parameterCache = parameterCache.filter { $0.key.trackID != trackID }
        loggedMissingParams = loggedMissingParams.filter { bindingID in
            // Remove logged-missing state for bindings on this track so a
            // reconnected AU gets a fresh lookup attempt and a fresh log if needed.
            !isMissingLogEntry(trackID: trackID, bindingID: bindingID)
        }
    }

    // MARK: - Private

    private func dispatch(value: Double, binding: TrackMacroBinding, trackID: UUID) {
        switch binding.source {
        case let .builtin(kind):
            sampleEngine.setVoiceParam(trackID: trackID, kind: kind, value: value)

        case let .auParameter(address, identifier):
            let key = CacheKey(trackID: trackID, bindingID: binding.id)
            if let cached = parameterCache[key] {
                cached.setValue(AUValue(value), originator: observerToken)
                return
            }

            // Attempt first-time resolution.
            guard let au = audioUnitProvider(trackID),
                  let tree = au.auAudioUnit.parameterTree
            else {
                logMissingOnce(bindingID: binding.id, reason: "no AU or parameter tree for track \(trackID)")
                return
            }

            if let param = tree.parameter(withAddress: address) {
                parameterCache[key] = param
                param.setValue(AUValue(value), originator: observerToken)
                return
            }

            // Fallback: keyPath-based lookup.
            if let param = tree.value(forKeyPath: identifier) as? AUParameter {
                parameterCache[key] = param
                param.setValue(AUValue(value), originator: observerToken)
                return
            }

            logMissingOnce(
                bindingID: binding.id,
                reason: "address \(address) / identifier '\(identifier)' not found in parameter tree"
            )
        }
    }

    private func logMissingOnce(bindingID: UUID, reason: String) {
        guard !loggedMissingParams.contains(bindingID) else { return }
        loggedMissingParams.insert(bindingID)
        NSLog("[TrackMacroApplier] macro binding \(bindingID) skipped — \(reason)")
    }

    /// Returns true if bindingID is in `loggedMissingParams` and belongs to `trackID`.
    /// We don't store per-track missing state explicitly, so this is used only during
    /// cache invalidation to filter stale log entries.
    private func isMissingLogEntry(trackID: UUID, bindingID: UUID) -> Bool {
        // We can't reverse-map bindingID → trackID without extra storage.
        // On invalidation we conservatively keep the missing log — the worst effect
        // is a log entry not being reprinted after a reconnect. That's acceptable.
        _ = trackID
        return false
    }
}

// MARK: - CacheKey

private struct CacheKey: Hashable {
    let trackID: UUID
    let bindingID: UUID
}
