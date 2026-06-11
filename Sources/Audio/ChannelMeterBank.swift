import AVFoundation
import Foundation

/// Identifies one mixer strip's live level stream.
enum ChannelMeterID: Hashable {
    case track(UUID)
    case bus(UUID)
    case send(SendBusID)
}

/// Per-strip level meters (roadmap 29), generalizing the master tap pattern:
/// every channel gets a `MasterMeterPublisher` fed from a tap installed at
/// graph build time, and one main-queue timer pumps all publishers so
/// `displayState` mutates on the main thread with no locks held — the same
/// discipline as the master meter (Observation re-entrancy is the known
/// deadlock class here).
final class ChannelMeterBank {
    private let lock = NSLock()
    private var publishers: [ChannelMeterID: MasterMeterPublisher] = [:]
    private var pumpTimer: DispatchSourceTimer?
    private let publishInterval: TimeInterval

    init(publishInterval: TimeInterval = 1.0 / 60.0) {
        self.publishInterval = publishInterval
    }

    deinit {
        pumpTimer?.cancel()
    }

    /// Stable per-channel publisher; lazily created so SwiftUI strips can
    /// observe a channel before its tap exists (it reads silent until then).
    func publisher(for id: ChannelMeterID) -> MasterMeterPublisher {
        lock.lock()
        defer { lock.unlock() }
        if let existing = publishers[id] {
            return existing
        }
        let publisher = MasterMeterPublisher()
        publishers[id] = publisher
        return publisher
    }

    /// Records silence into every publisher — used when taps are removed so
    /// stale peaks decay instead of freezing mid-meter.
    func recordSilenceEverywhere() {
        for publisher in publishersSnapshot() {
            publisher.recordPeakAmplitudes(left: 0, right: 0)
        }
    }

    func startPublishing() {
        if Thread.isMainThread {
            startPublishingOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startPublishingOnMain()
            }
        }
    }

    func stopPublishing() {
        if Thread.isMainThread {
            stopPublishingOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.stopPublishingOnMain()
            }
        }
    }

    /// Test hook: one pump tick, on the caller's (main) thread.
    func pumpOnceForTesting(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        for publisher in publishersSnapshot() {
            publisher.publishPendingToMain(now: now)
        }
    }

    private func publishersSnapshot() -> [MasterMeterPublisher] {
        lock.lock()
        defer { lock.unlock() }
        return Array(publishers.values)
    }

    private func startPublishingOnMain() {
        guard pumpTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + publishInterval, repeating: publishInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Snapshot under the lock, publish outside it: publishing
            // mutates @Observable state, which synchronously re-enters
            // SwiftUI bodies.
            for publisher in self.publishersSnapshot() {
                publisher.publishPendingToMain()
            }
        }
        pumpTimer = timer
        timer.resume()
    }

    private func stopPublishingOnMain() {
        pumpTimer?.cancel()
        pumpTimer = nil
    }
}
