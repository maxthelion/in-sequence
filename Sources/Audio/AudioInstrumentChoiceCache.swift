import AVFoundation
import AudioToolbox
import Foundation

/// Process-global cache for the AU instrument component list.
///
/// `AVAudioUnitComponentManager.shared().components(matching:)` validates every installed
/// third-party AU plug-in (sandbox entitlements, code-signing, licence state) on the first
/// call. On machines with many or slow-validating AUs, this blocks the calling thread for
/// many seconds. Because the scan result is stable for the lifetime of the process (new plug-in
/// installs require relaunching the app), a single warm is sufficient.
///
/// Usage:
///
///     // At app launch — fires the scan on a background queue and returns immediately.
///     AudioInstrumentChoiceCache.shared.beginWarmingIfNeeded()
///
///     // At any later point — blocks the caller until the scan is done (fast if already cached).
///     let choices = AudioInstrumentChoiceCache.shared.cachedChoices
///
/// Thread safety:
/// - `beginWarmingIfNeeded()` may be called from any thread; it submits work to a private
///   serial background queue and returns without blocking.
/// - `cachedChoices` may be called from any thread; if the background scan has not finished
///   it blocks the caller via a semaphore rather than launching a duplicate scan.
class AudioInstrumentChoiceCache {
    static let shared = AudioInstrumentChoiceCache()

    private let lock = NSLock()
    /// One token per waiter.  After the result is stored we signal `maxWaiters` times so all
    /// concurrent `cachedChoices` calls are unblocked.
    private let semaphore = DispatchSemaphore(value: 0)
    private let maxWaiters = 64
    private var cacheState: CacheState = .idle

    private enum CacheState {
        case idle
        case warming
        case ready([AudioInstrumentChoice])
    }

    init() {}

    /// Start warming the cache on a background queue.  Safe to call multiple times — only
    /// the first call launches the background scan; subsequent calls are no-ops.
    func beginWarmingIfNeeded() {
        lock.lock()
        guard case .idle = cacheState else {
            lock.unlock()
            return
        }
        cacheState = .warming
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let choices = self.performScan()
            self.lock.lock()
            self.cacheState = .ready(choices)
            self.lock.unlock()
            // Unblock all waiters in cachedChoices.
            for _ in 0..<self.maxWaiters {
                self.semaphore.signal()
            }
        }
    }

    /// The cached AU instrument choices.  Blocks the caller once (until the background scan
    /// finishes) and returns instantly on every subsequent call.
    var cachedChoices: [AudioInstrumentChoice] {
        lock.lock()
        if case let .ready(choices) = cacheState {
            lock.unlock()
            return choices
        }

        let wasIdle: Bool
        if case .idle = cacheState {
            wasIdle = true
            cacheState = .warming
        } else {
            wasIdle = false
        }
        lock.unlock()

        if wasIdle {
            // No warm has been requested yet — do it synchronously on the caller thread.
            let choices = performScan()
            lock.lock()
            cacheState = .ready(choices)
            lock.unlock()
            // Unblock any concurrent waiters.
            for _ in 0..<maxWaiters { semaphore.signal() }
            return choices
        }

        // A background warm is in progress — wait for it rather than launching a duplicate.
        semaphore.wait()
        // Re-signal so the next waiter is not stranded (broadcast pattern).
        semaphore.signal()

        lock.lock()
        if case let .ready(choices) = cacheState {
            lock.unlock()
            return choices
        }
        lock.unlock()
        // Defensive fallback; should not be reached.
        return [.builtInSynth]
    }

    // MARK: - Overridable scan hook (for testing)

    /// Performs the actual AU component scan.  Override in tests to inject a stub result.
    func performScan() -> [AudioInstrumentChoice] {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let manager = AVAudioUnitComponentManager.shared()
        var choices = manager.components(matching: description).map {
            AudioInstrumentChoice(
                name: $0.name,
                manufacturerName: $0.manufacturerName,
                componentType: $0.audioComponentDescription.componentType,
                componentSubType: $0.audioComponentDescription.componentSubType,
                componentManufacturer: $0.audioComponentDescription.componentManufacturer
            )
        }

        if !choices.contains(.builtInSynth) {
            choices.insert(.builtInSynth, at: 0)
        }

#if DEBUG
        if !choices.contains(.testInstrument) {
            choices.append(.testInstrument)
        }
#endif

        return choices.sorted { lhs, rhs in
            if lhs == .builtInSynth { return true }
            if rhs == .builtInSynth { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
