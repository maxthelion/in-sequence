import AVFoundation
import Foundation

/// A small, reusable gain-ramp primitive for an `AVAudioMixerNode`'s
/// `outputVolume`.
///
/// `AVAudioMixerNode.outputVolume` has no built-in sample-accurate ramp, so a
/// hard write produces a click when it jumps (e.g. mute → 0). This primitive
/// performs a short stepped linear ramp (~12 ms) on a dedicated serial
/// background queue.
///
/// Safety contract (matches the realtime / leaf-lock invariants):
/// - It ONLY writes `outputVolume` — a node-parameter update, never a graph
///   mutation (`attach`/`detach`/`connect`/`disconnect`). It is therefore safe
///   to kick from any thread, including the tick path, and it never needs
///   `SamplePlaybackEngine.lifecycleLock`.
/// - It holds no lock across the writes; per-node ramps are coalesced via a
///   generation token so a newer target supersedes an in-flight ramp.
///
/// Reusable: the same primitive backs track-mute gain and is intended to be
/// reused by the routing ramp-to-silence work (ramps task).
final class MixerGainRamp: @unchecked Sendable {
    /// Shared instance — one ramp engine, one background queue, coalescing per
    /// node identity.
    static let shared = MixerGainRamp()

    /// Total ramp duration. ~12 ms is long enough to remove the zipper/click of
    /// a hard volume jump while staying perceptually instant for mute/unmute.
    private let rampDuration: TimeInterval
    /// Number of discrete steps across the ramp. 24 steps over 12 ms ≈ 0.5 ms
    /// per step — fine-grained enough to be click-free.
    private let stepCount: Int

    private let queue = DispatchQueue(label: "ai.sequencer.MixerGainRamp", qos: .userInteractive)

    private let lock = NSLock()
    /// Per-node ramp generation. A new request bumps the generation so any
    /// older in-flight ramp for the same node bails out at its next step.
    private var generationByNode: [ObjectIdentifier: UInt64] = [:]

    init(rampDuration: TimeInterval = 0.012, stepCount: Int = 24) {
        self.rampDuration = max(0, rampDuration)
        self.stepCount = max(1, stepCount)
    }

    /// Ramp `node.outputVolume` from its current value to `target` over the
    /// configured duration. Coalesces with any in-flight ramp for the same
    /// node. If the change is negligible the target is applied immediately.
    func ramp(_ node: AVAudioMixerNode, to target: Float) {
        let nodeID = ObjectIdentifier(node)
        let generation: UInt64 = lock.withLock {
            let next = (generationByNode[nodeID] ?? 0) &+ 1
            generationByNode[nodeID] = next
            return next
        }

        let clampedTarget = min(max(target, 0), 1)
        queue.async { [weak self, weak node] in
            guard let self, let node else { return }
            self.run(node: node, nodeID: nodeID, target: clampedTarget, generation: generation)
        }
    }

    /// Snap `node.outputVolume` to `target` immediately, cancelling any
    /// in-flight ramp. Used where a ramp is not wanted (e.g. setup/teardown).
    func setImmediate(_ node: AVAudioMixerNode, to target: Float) {
        let nodeID = ObjectIdentifier(node)
        lock.withLock {
            generationByNode[nodeID] = (generationByNode[nodeID] ?? 0) &+ 1
        }
        node.outputVolume = min(max(target, 0), 1)
    }

    private func run(node: AVAudioMixerNode, nodeID: ObjectIdentifier, target: Float, generation: UInt64) {
        func isCurrent() -> Bool {
            lock.withLock { generationByNode[nodeID] == generation }
        }

        let start = node.outputVolume
        let delta = target - start
        if abs(delta) < 0.0005 || rampDuration <= 0 {
            if isCurrent() { node.outputVolume = target }
            return
        }

        let stepInterval = rampDuration / TimeInterval(stepCount)
        for step in 1...stepCount {
            guard isCurrent() else { return }
            let fraction = Float(step) / Float(stepCount)
            node.outputVolume = start + delta * fraction
            if step < stepCount {
                Thread.sleep(forTimeInterval: stepInterval)
            }
        }
        if isCurrent() { node.outputVolume = target }
    }
}
