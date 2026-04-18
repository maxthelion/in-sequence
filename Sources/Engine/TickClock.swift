import Dispatch
import Foundation

final class TickClock {
    private let beatsPerBar = 4.0 // 4/4 for this plan: four beats per bar.
    private let stepsPerBar: Int
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var timer: DispatchSourceTimer?
    private var storedBPM: Double
    private var nextTickIndex: UInt64 = 0

    init(stepsPerBar: Int = 16, bpm: Double = 120) {
        self.stepsPerBar = max(1, stepsPerBar)
        self.storedBPM = max(1, bpm)
        self.queue = DispatchQueue(label: "ai.sequencer.SequencerAI.TickClock")
        self.queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    var bpm: Double {
        get {
            syncOnQueue { storedBPM }
        }
        set {
            syncOnQueue {
                storedBPM = max(1, newValue)
                rescheduleTimerIfNeeded()
            }
        }
    }

    var isRunning: Bool {
        syncOnQueue { timer != nil }
    }

    func start(onTick: @escaping (UInt64, TimeInterval) -> Void) {
        syncOnQueue {
            guard timer == nil else {
                return
            }

            nextTickIndex = 0

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: intervalForCurrentBPM(),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                guard let self else {
                    return
                }

                let tickIndex = self.nextTickIndex
                self.nextTickIndex += 1
                onTick(tickIndex, ProcessInfo.processInfo.systemUptime)
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        syncOnQueue {
            guard let timer else {
                return
            }

            timer.setEventHandler {}
            timer.cancel()
            self.timer = nil
        }
    }

    private func intervalForCurrentBPM() -> DispatchTimeInterval {
        let seconds = 60.0 / storedBPM / Double(stepsPerBar) * beatsPerBar
        return .nanoseconds(Int(seconds * 1_000_000_000))
    }

    private func rescheduleTimerIfNeeded() {
        guard let timer else {
            return
        }

        timer.schedule(
            deadline: .now() + intervalForCurrentBPM(),
            repeating: intervalForCurrentBPM(),
            leeway: .milliseconds(1)
        )
    }

    private func syncOnQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }

        return queue.sync(execute: body)
    }
}
