import Dispatch
import Foundation

final class TickClock {
    private let beatsPerBar = 4.0 // 4/4 for this plan: four beats per bar.
    private let stepsPerBar: Int
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    // realtime-allow-pump-pacing: TickClock is the lookahead pump's wake timer — it paces *when* the engine prepares/commits the next step, NEVER the frame an event sounds on (that is anchored by AudioMasterClock from the tempo map, Rule 1). Pump jitter does not move the sounding frame. Test: OfflineFrameAccuracyTests.
    private var timer: DispatchSourceTimer?
    private var storedBPM: Double
    private var nextTickIndex: UInt64 = 0
    private var nextExpectedUptime: TimeInterval?

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
            // realtime-allow-pump-pacing: seeds the pump's wake-jitter probe baseline (next expected wake), not a sounding time. Test: OfflineFrameAccuracyTests.
            nextExpectedUptime = ProcessInfo.processInfo.systemUptime

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

                // realtime-allow-pump-pacing: the pump's actual wake time, passed to onTick as `now` for the wake-jitter probe and the MIDI/note-off wall-clock path; the AUDIO sounding frame is derived in AudioMasterClock from the tempo map, not from this value (Rule 1). Test: OfflineFrameAccuracyTests.
                let actual = ProcessInfo.processInfo.systemUptime
                let tickIndex = self.nextTickIndex
                let interval = self.intervalSecondsForCurrentBPM()
                let expected = self.nextExpectedUptime ?? actual
                self.nextTickIndex += 1
                self.nextExpectedUptime = expected + interval
                SequencerTimingProbe.tickClock(
                    tickIndex: tickIndex,
                    expected: expected,
                    actual: actual,
                    interval: interval,
                    bpm: self.storedBPM
                )
                onTick(tickIndex, actual)
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
            self.nextExpectedUptime = nil
        }
    }

    private func intervalForCurrentBPM() -> DispatchTimeInterval {
        .nanoseconds(Int(intervalSecondsForCurrentBPM() * 1_000_000_000))
    }

    private func intervalSecondsForCurrentBPM() -> TimeInterval {
        60.0 / storedBPM / Double(stepsPerBar) * beatsPerBar
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
        // realtime-allow-pump-pacing: recomputes the pump's next expected wake after a BPM change (wake-jitter probe baseline), not a sounding time. Test: OfflineFrameAccuracyTests.
        nextExpectedUptime = ProcessInfo.processInfo.systemUptime + intervalSecondsForCurrentBPM()
    }

    private func syncOnQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }

        return queue.sync(execute: body)
    }
}
