import AVFoundation
import AudioToolbox
import Foundation

/// Process-global cache for the AU instrument component list.
///
/// `AVAudioUnitComponentManager.shared().components(matching:)` validates every installed
/// third-party AU plug-in (sandbox entitlements, code-signing, licence state) on the first
/// call. On machines with many or slow-validating AUs, this blocks the calling thread for
/// many seconds. The app warms the list once at launch, then explicit user rescans refresh
/// it on a background queue when plug-ins are installed while the app is running.
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

    private let condition = NSCondition()
    private var cacheState: CacheState = .idle

    private enum CacheState {
        case idle
        case warming(previous: [AudioInstrumentChoice]?)
        case ready([AudioInstrumentChoice])
    }

    init() {}

    /// Start warming the cache on a background queue.  Safe to call multiple times — only
    /// the first call launches the background scan; subsequent calls are no-ops.
    func beginWarmingIfNeeded() {
        condition.lock()
        guard case .idle = cacheState else {
            condition.unlock()
            return
        }
        if ProcessInfo.processInfo.environment["SEQUENCER_AI_SKIP_AUDIO_COMPONENT_SCAN"] == "1" {
            cacheState = .ready([.builtInSynth])
            condition.broadcast()
            condition.unlock()
            return
        }
        cacheState = .warming(previous: nil)
        condition.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.completeScan(self.performScan())
        }
    }

    /// Start a refresh on a background queue. Returns `false` if a warm/rescan is already
    /// running, making repeated button presses cheap and safe.
    @discardableResult
    func beginRescanIfNeeded() -> Bool {
        condition.lock()
        let previousChoices: [AudioInstrumentChoice]?
        switch cacheState {
        case .warming:
            condition.unlock()
            return false
        case .idle:
            previousChoices = nil
        case let .ready(choices):
            previousChoices = choices
        }
        cacheState = .warming(previous: previousChoices)
        condition.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.completeScan(self.performScan())
        }
        return true
    }

    /// Force a refresh on the caller's thread, waiting for any in-flight scan to finish
    /// first. Intended for off-main rescan coordinators and deterministic tests.
    func rescanChoices() -> [AudioInstrumentChoice] {
        condition.lock()
        while case .warming = cacheState {
            condition.wait()
        }

        let previousChoices: [AudioInstrumentChoice]?
        switch cacheState {
        case .idle:
            previousChoices = nil
        case let .ready(choices):
            previousChoices = choices
        case .warming:
            previousChoices = nil
        }
        cacheState = .warming(previous: previousChoices)
        condition.unlock()

        let choices = performScan()
        completeScan(choices)
        return choices
    }

    /// Non-blocking snapshot for UI redraws while a rescan is running.
    var currentChoicesIfAvailable: [AudioInstrumentChoice]? {
        condition.lock()
        defer { condition.unlock() }
        switch cacheState {
        case .idle:
            return nil
        case let .warming(previous):
            return previous
        case let .ready(choices):
            return choices
        }
    }

    /// The cached AU instrument choices.  Blocks the caller once (until the background scan
    /// finishes) and returns instantly on every subsequent call.
    var cachedChoices: [AudioInstrumentChoice] {
        condition.lock()
        switch cacheState {
        case let .ready(choices):
            condition.unlock()
            return choices
        case .idle:
            cacheState = .warming(previous: nil)
            condition.unlock()
            // No warm has been requested yet — do it synchronously on the caller thread.
            let choices = performScan()
            completeScan(choices)
            return choices
        case .warming:
            while case .warming = cacheState {
                condition.wait()
            }
            if case let .ready(choices) = cacheState {
                condition.unlock()
                return choices
            }
            condition.unlock()
            // Defensive fallback; should not be reached.
            return [.builtInSynth]
        }
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

    private func completeScan(_ choices: [AudioInstrumentChoice]) {
        condition.lock()
        cacheState = .ready(choices)
        condition.broadcast()
        condition.unlock()
    }
}
