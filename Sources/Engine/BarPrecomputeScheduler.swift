import Foundation

/// Round-2 Phase-2: the OFF-THREAD next-bar precompute scheduler.
///
/// This is the mechanism the round-2 spec
/// (`docs/plans/2026-07-01-round2-integration-spec.md`, "P2 — generation
/// genuinely off the tick path") requires: "a background scheduler precomputes
/// the next bar's realized notes (per track) into a buffer, published to the
/// tick path via the existing snapshot lock-swap. `prepareTick` reads from that
/// buffer and does zero generation."
///
/// Generation — the fresh per-step RNG construction and the
/// `GeneratedSourceEvaluator` evaluation — runs on `queue` (a background serial
/// queue), NEVER on the tick/prepare path. The tick path only ever calls
/// `consume(...)`, a lock-guarded dictionary read of a published
/// `PrecomputedBar`. That is why the round-2 Rule-2 lint (which forbids the live
/// per-step generator seam on the tick-path files) is satisfied genuinely, not
/// via an annotation: the live seam simply is not reached from a tick when a bar
/// is published.
///
/// # Cross-thread publication (Audio Engine Hard Rule: lock-swap / snapshot)
///
/// Published bars are guarded by `lock` (the established lock-swap pattern — the
/// same class as `TickStateBuffer`'s `NSLock`). The background queue computes into
/// a local `PrecomputedBar`, then swaps it into `publishedByKey` under the lock
/// and signals `ready`. The tick path reads under the same lock. No generation
/// state crosses the boundary un-guarded.
///
/// # Bounded boundary wait (not the steady state)
///
/// The steady state is: while the tick path is consuming bar N, the scheduler is
/// already computing bar N+1 (both are requested every tick), so bar N+1 is
/// published before its boundary and `consume` returns immediately with no wait.
/// The only time `consume` waits is the COLD boundary (first bar after start /
/// snapshot install / invalidation), where the request was only just issued.
/// There the tick path waits on `ready` up to `boundaryWaitSeconds` for the
/// background compute — a bounded wait on the prepare path (the same path that
/// already takes `TickStateBuffer`'s lock), NOT the realtime render callback. If
/// the deadline elapses the tick path falls back to the inline live generator for
/// that step (graceful degradation), which the caller annotates.
final class BarPrecomputeScheduler {

    /// The identity of a precomputed bar: which phrase it belongs to, which output
    /// step it starts at, and the generation-input revision it was computed
    /// against. A published bar only satisfies a consume request with the same key
    /// — a phrase swap, bar re-alignment, or a snapshot edit (revision bump) makes
    /// the stale bar non-matching (invalidation without an explicit call).
    private struct BarKey: Hashable {
        let phraseID: UUID
        let startStep: Int
        let stepCount: Int
        let revision: UInt64
    }

    /// Off-thread home for generation. Serial: at most one bar computes at a time,
    /// in request order.
    private let queue = DispatchQueue(label: "ai.sequencer.bar-precompute", qos: .userInitiated)

    private let lock = NSLock()
    private let ready = NSCondition()

    /// Published bars (background compute finished), keyed by identity. Bounded to
    /// the few most-recent keys so an old revision's bars are evicted (the tick
    /// path only ever asks for the current + next bar of the live revision).
    private var publishedByKey: [BarKey: PrecomputedBar] = [:]
    /// Insertion order of `publishedByKey` for bounded eviction.
    private var publishedOrder: [BarKey] = []
    /// Keys whose background compute has been dispatched and not yet published —
    /// so `consume` knows a bounded wait is worthwhile (vs a never-requested bar).
    private var inFlight: Set<BarKey> = []

    private static let maxPublishedBars = 4

    /// Test seam: number of background precompute evaluations performed. Lets a
    /// unit test assert generation actually ran off-thread. Never read on a
    /// sounding path.
    private let backgroundEvaluationsAtomic = AtomicInt64(0)
    var backgroundEvaluationCount: Int { Int(backgroundEvaluationsAtomic.load()) }

    /// Request the background precompute of one bar. Idempotent for an identical
    /// key that is already published or in flight. Runs generation on `queue` and
    /// publishes the result under `lock`.
    ///
    /// The per-step RNG seed is generated OFF the tick path (inside the `queue`
    /// closure, in this file) with a fresh `SystemRandomNumberGenerator` — mirror
    /// of the former live per-(track, step) fresh-RNG on the tick path, only now
    /// off-thread. Callers on the tick-path files never construct an RNG (that is
    /// what the round-2 Rule-2 lint forbids there); the RNG lives here.
    func request(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackIDs: [UUID],
        blockIDForTrack: @escaping (UUID) -> BlockID,
        startStep: Int,
        stepCount: Int,
        chordContext: Chord?,
        revision: UInt64
    ) {
        let key = BarKey(phraseID: phraseID, startStep: startStep, stepCount: stepCount, revision: revision)
        lock.lock()
        if publishedByKey[key] != nil || inFlight.contains(key) {
            lock.unlock()
            return
        }
        inFlight.insert(key)
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            // Fresh per-step RNG seeds, generated off-thread on the background
            // queue (never the tick path). One seed per step drawn from a fresh
            // system RNG, matching the former inline `SystemRandomNumberGenerator()`
            // per-step behaviour — just moved off the realtime tick path.
            var rng = SystemRandomNumberGenerator()
            var seedByStep: [Int: UInt64] = [:]
            for step in startStep..<(startStep + stepCount) {
                seedByStep[step] = rng.next()
            }
            let bar = BarPrecomputeEvaluator.precompute(
                snapshot: snapshot,
                phraseID: phraseID,
                trackIDs: trackIDs,
                blockIDForTrack: blockIDForTrack,
                startStep: startStep,
                stepCount: stepCount,
                chordContext: chordContext,
                seedForStep: { seedByStep[$0] ?? 0 }
            )
            self.backgroundEvaluationsAtomic.increment()
            self.ready.lock()
            self.lock.lock()
            self.inFlight.remove(key)
            self.publishedByKey[key] = bar
            self.publishedOrder.append(key)
            while self.publishedOrder.count > Self.maxPublishedBars {
                let evicted = self.publishedOrder.removeFirst()
                self.publishedByKey.removeValue(forKey: evicted)
            }
            self.lock.unlock()
            self.ready.broadcast()
            self.ready.unlock()
        }
    }

    /// Consume the precomputed bar for the given key.
    ///
    /// Returns the published bar immediately if present. Otherwise, if that bar is
    /// in flight (was requested), waits up to `boundaryWaitSeconds` on the prepare
    /// path for the background compute to publish it (the cold-boundary case).
    /// Returns `nil` if the bar is not published within the deadline — the caller
    /// then falls back to the inline live generator for the step (graceful
    /// degradation; not the steady state).
    func consume(
        phraseID: UUID,
        startStep: Int,
        stepCount: Int,
        revision: UInt64,
        boundaryWaitSeconds: TimeInterval
    ) -> PrecomputedBar? {
        let key = BarKey(phraseID: phraseID, startStep: startStep, stepCount: stepCount, revision: revision)

        lock.lock()
        if let bar = publishedByKey[key] {
            lock.unlock()
            return bar
        }
        let isInFlight = inFlight.contains(key)
        lock.unlock()

        guard isInFlight, boundaryWaitSeconds > 0 else { return nil }

        let deadline = Date().addingTimeInterval(boundaryWaitSeconds)
        ready.lock()
        while true {
            lock.lock()
            if let bar = publishedByKey[key] {
                lock.unlock()
                ready.unlock()
                return bar
            }
            let stillInFlight = inFlight.contains(key)
            lock.unlock()
            if !stillInFlight { break }
            if !ready.wait(until: deadline) { break }
        }
        ready.unlock()
        return nil
    }

    /// Cold-boundary / live-override GRACEFUL FALLBACK: evaluate one (track, step)
    /// live when the off-thread bar is not yet published or a live per-step control
    /// is active. This is the "inline fallback to today's path only if the buffer
    /// is not ready at the boundary" the round-2 spec sanctions — NOT the steady
    /// state (the steady tick consumes `consume(...)` above).
    ///
    /// The live per-step generator seam lives in `BarPrecompute.swift`; this
    /// wrapper keeps that call OFF the tick-path files, so the round-2 Rule-2 lint
    /// stays satisfied by the genuinely-off-thread steady path, not by annotating a
    /// live call on the tick-path files. The fallback still records into
    /// `LiveTickGeneratorProbe` (it IS a live evaluation) — the rail asserts the
    /// steady tick never reaches here.
    func resolveStepFallback(
        trackID: UUID,
        in snapshot: PlaybackSnapshot,
        phraseID: UUID,
        stepInPhrase: Int,
        chordContext: Chord?,
        trackFillPreview: TrackFillPreviewPlaybackSnapshot,
        quantisedFillFlagOverrides: [UUID: Bool],
        quantisedPatternSlotOverrides: [UUID: Int],
        quantisedFillCueTrackIDs: Set<UUID>,
        auditionOverride: PseudoClipState?,
        trackType: TrackType,
        state: inout GeneratedSourceEvaluationState
    ) -> [GeneratedNote] {
        BarPrecomputeEvaluator.resolveStep(
            trackID: trackID,
            in: snapshot,
            phraseID: phraseID,
            stepInPhrase: stepInPhrase,
            chordContext: chordContext,
            trackFillPreview: trackFillPreview,
            quantisedFillFlagOverrides: quantisedFillFlagOverrides,
            quantisedPatternSlotOverrides: quantisedPatternSlotOverrides,
            quantisedFillCueTrackIDs: quantisedFillCueTrackIDs,
            auditionOverride: auditionOverride,
            trackType: trackType,
            state: &state
        )
    }

    /// Drop all published/in-flight bars so the next `consume` misses (used when a
    /// generation input changes and the caller wants an explicit reset; the
    /// per-key revision already invalidates stale bars implicitly).
    func invalidate() {
        lock.lock()
        publishedByKey.removeAll()
        publishedOrder.removeAll()
        inFlight.removeAll()
        lock.unlock()
    }
}
