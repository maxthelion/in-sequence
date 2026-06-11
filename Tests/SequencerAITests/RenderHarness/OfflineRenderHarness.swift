import AVFoundation
import Foundation
@testable import SequencerAI

/// Drives the real engine (EngineController + MainAudioGraph +
/// SamplePlaybackEngine) through its tick API with AVAudioEngine in offline
/// manual rendering mode, producing a deterministic faster-than-realtime
/// master render plus per-tick cost stats.
///
/// Timing model: the harness renders exactly one tick's worth of frames
/// after each `processTick`, so events the engine dispatches "immediately"
/// begin at the first frame of their step's block — i.e. sample-aligned to
/// the step grid. Sub-tick events (note repeats) carry future timeline
/// times, which the harness maps onto the manual-rendering sample clock via
/// `scheduledAudioTimeOverrideForTesting`.
enum OfflineRenderHarness {
    static let sampleRate: Double = 48_000
    /// Pre-roll of silence so the windowed transient detector has a quiet
    /// baseline before the first onset (an onset at frame 0 has no
    /// preceding window and would be missed).
    static let preRollSeconds: Double = 0.25
    /// Post-roll so the final step's audio decays inside the file.
    static let tailSeconds: Double = 0.35
    static let renderChunkFrames: AVAudioFrameCount = 4_096

    struct TickStat {
        /// Wall-clock cost of processTick (event prep + dispatch).
        var processSeconds: Double
        /// Wall-clock cost of rendering this tick's audio block.
        var renderSeconds: Double
        /// The tick's musical duration — the live deadline budget.
        var budgetSeconds: Double

        var totalSeconds: Double { processSeconds + renderSeconds }
        var isOverBudget: Bool { totalSeconds > budgetSeconds }
    }

    struct Result {
        let scenarioName: String
        let sampleRate: Double
        /// Non-interleaved master output channels.
        let channels: [[Float]]
        let preRollFrames: Int
        /// Absolute frame at which each tick's block starts — the expected
        /// onset frame for events on that step.
        let tickStartFrames: [Int]
        let tickStats: [TickStat]
        /// Total wall-clock spent in processTick + renderOffline.
        let renderWallSeconds: Double
        /// Diagnostic: every scheduled-time mapping the engine requested.
        let overrideCalls: [(timelineSeconds: Double, mappedSampleTime: Int?, cursorFrames: Int)]

        var totalFrames: Int { channels.first?.count ?? 0 }
        var audioSeconds: Double { Double(totalFrames) / sampleRate }
        /// < 1 means faster than realtime.
        var realTimeFactor: Double { renderWallSeconds / max(audioSeconds, 0.000_001) }
        var overBudgetTickCount: Int { tickStats.filter(\.isOverBudget).count }

        var peak: Float {
            channels.reduce(0) { partial, channel in
                channel.reduce(partial) { max($0, abs($1)) }
            }
        }

        func expectedOnsetSeconds(forTicks ticks: [Int]) -> [Double] {
            ticks.compactMap { tick in
                guard tick >= 0, tick < tickStartFrames.count else { return nil }
                return Double(tickStartFrames[tick]) / sampleRate
            }
        }

        /// RMS over a mono mixdown window.
        func rms(startSeconds: Double, durationSeconds: Double) -> Double {
            let start = max(0, Int(startSeconds * sampleRate))
            let end = min(totalFrames, start + Int(durationSeconds * sampleRate))
            guard end > start, !channels.isEmpty else { return 0 }
            var sum = 0.0
            for frame in start..<end {
                var mono: Double = 0
                for channel in channels {
                    mono += Double(channel[frame])
                }
                mono /= Double(channels.count)
                sum += mono * mono
            }
            return (sum / Double(end - start)).squareRoot()
        }

        func writeWAV(to url: URL) throws {
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(channels.count)
            )!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
            buffer.frameLength = AVAudioFrameCount(totalFrames)
            for (channelIndex, channel) in channels.enumerated() {
                let destination = buffer.floatChannelData![channelIndex]
                channel.withUnsafeBufferPointer { source in
                    destination.update(from: source.baseAddress!, count: channel.count)
                }
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
    }

    /// Rewires track -> (dry | bus, sends), bus -> preMaster, and send
    /// return -> final output edges with explicitly allocated destination
    /// input buses. See the call site for why manual rendering needs this.
    private static func canonicalizeMixTopology(
        graph: MainAudioGraph,
        sampleEngine: SamplePlaybackEngine,
        trackIDs: [UUID]
    ) {
        let engine = graph.engine

        struct TrackWiring {
            let source: AVAudioNode
            let dryDestination: AVAudioNode
            let fanout: AVAudioMixerNode?
            let sendAGain: AVAudioMixerNode?
            let sendBGain: AVAudioMixerNode?
        }

        var trackWirings: [TrackWiring] = []
        for trackID in trackIDs {
            guard let filter = sampleEngine.filterNode(for: trackID) as? SamplerFilterNode else { continue }
            guard let readout = graph.trackSendReadoutForTesting(filter.avNode) else { continue }
            trackWirings.append(TrackWiring(
                source: filter.avNode,
                dryDestination: readout.dryDestination,
                fanout: readout.sendFanoutNode,
                sendAGain: readout.sendAGainNode,
                sendBGain: readout.sendBGainNode
            ))
        }

        let busReadouts = graph.mixerBusReadoutsForTesting
        let sendReadouts = graph.sendBusReadoutsForTesting
        var sendMixersByID: [SendBusID: AVAudioMixerNode] = [:]
        for readout in sendReadouts {
            sendMixersByID[readout.busID] = readout.inputMixer
        }

        // Disconnect every edge we are about to re-issue so destination
        // input buses free up before allocation.
        for wiring in trackWirings {
            engine.disconnectNodeOutput(wiring.source)
            if let fanout = wiring.fanout { engine.disconnectNodeOutput(fanout) }
            if let gain = wiring.sendAGain { engine.disconnectNodeOutput(gain) }
            if let gain = wiring.sendBGain { engine.disconnectNodeOutput(gain) }
        }
        for readout in busReadouts {
            engine.disconnectNodeOutput(readout.terminalSourceNode ?? readout.inputMixer)
        }
        for readout in sendReadouts {
            engine.disconnectNodeOutput(readout.terminalSourceNode ?? readout.inputMixer)
        }

        // Explicit input-bus allocation: pending connections are invisible
        // to nextAvailableInputBus, so query once per mixer and advance
        // manually.
        var busCursor: [ObjectIdentifier: AVAudioNodeBus] = [:]
        func allocateBus(_ destination: AVAudioNode) -> AVAudioNodeBus {
            guard let mixer = destination as? AVAudioMixerNode else { return 0 }
            let key = ObjectIdentifier(mixer)
            let bus = busCursor[key] ?? mixer.nextAvailableInputBus
            busCursor[key] = bus + 1
            return bus
        }

        // Bus terminal -> preMaster.
        for readout in busReadouts {
            let source = readout.terminalSourceNode ?? readout.inputMixer
            engine.connect(
                source,
                to: graph.preMasterMixer,
                fromBus: 0,
                toBus: allocateBus(graph.preMasterMixer),
                format: nil
            )
        }

        // Send return terminal -> final output.
        for readout in sendReadouts {
            let source = readout.terminalSourceNode ?? readout.inputMixer
            let destination = graph.sendReturnDestinationForTesting
            engine.connect(
                source,
                to: destination,
                fromBus: 0,
                toBus: allocateBus(destination),
                format: nil
            )
        }

        // Track source -> dry destination (+ send fanout/gains).
        for wiring in trackWirings {
            if let fanout = wiring.fanout,
               let sendAGain = wiring.sendAGain,
               let sendBGain = wiring.sendBGain,
               let sendAMixer = sendMixersByID[.sendA],
               let sendBMixer = sendMixersByID[.sendB]
            {
                engine.connect(
                    wiring.source,
                    to: [
                        AVAudioConnectionPoint(node: wiring.dryDestination, bus: allocateBus(wiring.dryDestination)),
                        AVAudioConnectionPoint(node: fanout, bus: allocateBus(fanout)),
                    ],
                    fromBus: 0,
                    format: nil
                )
                engine.connect(
                    fanout,
                    to: [
                        AVAudioConnectionPoint(node: sendAGain, bus: allocateBus(sendAGain)),
                        AVAudioConnectionPoint(node: sendBGain, bus: allocateBus(sendBGain)),
                    ],
                    fromBus: 0,
                    format: nil
                )
                engine.connect(sendAGain, to: sendAMixer, fromBus: 0, toBus: allocateBus(sendAMixer), format: nil)
                engine.connect(sendBGain, to: sendBMixer, fromBus: 0, toBus: allocateBus(sendBMixer), format: nil)
            } else {
                engine.connect(
                    wiring.source,
                    to: wiring.dryDestination,
                    fromBus: 0,
                    toBus: allocateBus(wiring.dryDestination),
                    format: nil
                )
            }
        }
    }

    /// Mutable box shared with the scheduled-time override closure.
    private final class FrameCursor {
        var renderedFrames = 0
        var overrideCalls: [(timelineSeconds: Double, mappedSampleTime: Int?, cursorFrames: Int)] = []
    }

    static func render(scenario: RenderScenario, libraryRoot: URL) throws -> Result {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let built = try RenderScenarioProjectBuilder.build(scenario: scenario, library: library)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw RenderHarnessError.manualRenderingUnavailable("cannot create render format")
        }
        // Enable manual rendering on a virgin engine BEFORE MainAudioGraph
        // builds its node topology: once the graph has prepared against the
        // hardware device, switching modes fails (-80801).
        let engine = AVAudioEngine()
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: renderChunkFrames)
        } catch {
            throw RenderHarnessError.manualRenderingUnavailable("\(error)")
        }
        let graph = MainAudioGraph(engine: engine)

        let sampleEngine = SamplePlaybackEngine(audioGraph: graph)
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            mainAudioGraph: graph,
            sampleEngine: sampleEngine,
            sampleLibrary: library
        )

        let cursor = FrameCursor()
        controller.scheduledAudioTimeOverrideForTesting = { [weak cursor] timelineSeconds in
            // Map the synthetic musical timeline onto the manual-rendering
            // sample clock. Times at/behind the render cursor play at the
            // next rendered frame (nil = immediate), which for step events
            // is exactly the start of their step's block.
            guard let cursor else { return nil }
            let sampleTime = AVAudioFramePosition(((timelineSeconds + preRollSeconds) * sampleRate).rounded())
            guard sampleTime > AVAudioFramePosition(cursor.renderedFrames) else {
                cursor.overrideCalls.append((timelineSeconds, nil, cursor.renderedFrames))
                return nil
            }
            cursor.overrideCalls.append((timelineSeconds, Int(sampleTime), cursor.renderedFrames))
            return AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
        }

        // Manual-rendering wiring lifecycle (found empirically):
        // - Production rewires topology dynamically on a RUNNING engine;
        //   in manual rendering mode those connects park as "pending" and
        //   a mid-apply engine restart then fails AVAudioEngine's source-
        //   node validation (NSException).
        // - Connections made to fresh input buses of already-initialized
        //   mixers on a never-started engine also stay pending forever
        //   (bus-routed tracks render silent).
        // The reliable recipe: one real start/stop cycle first, apply the
        // document while STOPPED (installs then skip their mid-apply
        // restarts), and restart once at the end — which activates every
        // pending connection.
        do {
            try graph.start()
        } catch {
            throw RenderHarnessError.manualRenderingUnavailable("engine start failed: \(error)")
        }
        graph.engine.stop()

        controller.apply(documentModel: built.project)

        // Canonicalize the mix topology: production wires tracks/buses/
        // sends with next-available-bus connects, often on a running
        // engine. In manual rendering mode, connects made against
        // already-initialized junction mixers park as "pending" — they
        // never activate, are invisible to nextAvailableInputBus (so later
        // connects can collide/evict), and a mid-apply restart trips
        // AVAudioEngine's source-node validation. Rewiring every edge here
        // with explicitly allocated input buses while stopped makes the
        // final prepare/start activate a deterministic, complete graph.
        canonicalizeMixTopology(graph: graph, sampleEngine: sampleEngine, trackIDs: built.trackIDs)

        graph.engine.prepare()
        do {
            try graph.engine.start()
        } catch {
            throw RenderHarnessError.manualRenderingUnavailable("engine restart failed: \(error)")
        }
        controller.setBPM(scenario.bpm)
        controller.startTransportWithoutClockForTesting(now: 0)
        defer {
            controller.stop()
            controller.scheduledAudioTimeOverrideForTesting = nil
        }

        guard graph.engine.isRunning else {
            throw RenderHarnessError.manualRenderingUnavailable("engine did not start in manual rendering mode")
        }
        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: graph.engine.manualRenderingFormat,
            frameCapacity: renderChunkFrames
        ) else {
            throw RenderHarnessError.renderFailed("cannot allocate render buffer")
        }

        var channels: [[Float]] = [[], []]
        let estimatedFrames = Int((preRollSeconds + tailSeconds + Double(scenario.totalTicks) * 0.15) * sampleRate)
        channels[0].reserveCapacity(estimatedFrames)
        channels[1].reserveCapacity(estimatedFrames)

        func renderFrames(_ count: Int) throws {
            var remaining = count
            while remaining > 0 {
                let chunk = AVAudioFrameCount(min(remaining, Int(renderChunkFrames)))
                let status = try graph.engine.renderOffline(chunk, to: renderBuffer)
                guard status == .success else {
                    throw RenderHarnessError.renderFailed("renderOffline returned \(status)")
                }
                let frames = Int(renderBuffer.frameLength)
                for channelIndex in 0..<min(2, Int(renderBuffer.format.channelCount)) {
                    let data = renderBuffer.floatChannelData![channelIndex]
                    channels[channelIndex].append(contentsOf: UnsafeBufferPointer(start: data, count: frames))
                }
                cursor.renderedFrames += frames
                remaining -= frames
            }
        }

        // Pre-roll silence (transport prepared, no events dispatched yet).
        try renderFrames(Int(preRollSeconds * sampleRate))

        var mixes = scenario.tracks.map { spec in
            TrackMixSettings(level: spec.level, pan: spec.pan, isMuted: false, sendA: spec.sendA, sendB: spec.sendB)
        }
        var busMixes = scenario.buses.map { spec in
            BusMixSettings(level: spec.level, pan: 0, isMuted: false, isSoloed: false)
        }

        var bpm = min(max(scenario.bpm, 40), 300)
        var timelineSeconds: TimeInterval = 0
        var frameRemainder = 0.0
        var tickStartFrames: [Int] = []
        var tickStats: [TickStat] = []
        var renderWallSeconds = 0.0

        for tick in 0..<scenario.totalTicks {
            for action in scenario.actions where action.tick == tick {
                switch action.kind {
                case let .setBPM(value):
                    bpm = min(max(value, 40), 300)
                    controller.setBPM(value)
                case let .setTrackLevel(trackIndex, level):
                    guard trackIndex < mixes.count else { break }
                    mixes[trackIndex].level = level
                    controller.setMix(trackID: built.trackIDs[trackIndex], mix: mixes[trackIndex])
                case let .setTrackPan(trackIndex, pan):
                    guard trackIndex < mixes.count else { break }
                    mixes[trackIndex].pan = pan
                    controller.setMix(trackID: built.trackIDs[trackIndex], mix: mixes[trackIndex])
                case let .setTrackSends(trackIndex, sendA, sendB):
                    guard trackIndex < mixes.count else { break }
                    mixes[trackIndex].sendA = sendA
                    mixes[trackIndex].sendB = sendB
                    controller.setMix(trackID: built.trackIDs[trackIndex], mix: mixes[trackIndex])
                case let .setBusLevel(busIndex, level):
                    guard busIndex < busMixes.count else { break }
                    busMixes[busIndex].level = level
                    controller.setMixerBusMix(busID: built.busIDs[busIndex], mix: busMixes[busIndex])
                case let .setMasterOutputGain(value):
                    controller.setLiveMasterOutputGain(value)
                }
            }

            tickStartFrames.append(cursor.renderedFrames)

            let processStart = ProcessInfo.processInfo.systemUptime
            controller.processTick(tickIndex: UInt64(tick), now: timelineSeconds)
            let processSeconds = ProcessInfo.processInfo.systemUptime - processStart

            // AVAudioPlayerNode performs its file read-ahead on an internal
            // queue. Realtime playback has a full tick of slack before the
            // first frame is pulled; offline rendering would race it and
            // start voices mid-block (observed 7-14 ms late). Yield briefly
            // so freshly scheduled segments are primed before their block
            // renders.
            usleep(3_000)

            let secondsPerTick = (60 / bpm) * 4 / Double(scenario.stepsPerBar)
            let exactFrames = secondsPerTick * sampleRate + frameRemainder
            let frames = Int(exactFrames.rounded(.down))
            frameRemainder = exactFrames - Double(frames)

            let renderStart = ProcessInfo.processInfo.systemUptime
            try renderFrames(frames)
            let renderSeconds = ProcessInfo.processInfo.systemUptime - renderStart

            tickStats.append(TickStat(
                processSeconds: processSeconds,
                renderSeconds: renderSeconds,
                budgetSeconds: secondsPerTick
            ))
            renderWallSeconds += processSeconds + renderSeconds
            timelineSeconds += secondsPerTick
        }

        // Tail so the last step's audio fully decays inside the file.
        try renderFrames(Int(tailSeconds * sampleRate))

        return Result(
            scenarioName: scenario.name,
            sampleRate: sampleRate,
            channels: channels,
            preRollFrames: Int(preRollSeconds * sampleRate),
            tickStartFrames: tickStartFrames,
            tickStats: tickStats,
            renderWallSeconds: renderWallSeconds,
            overrideCalls: cursor.overrideCalls
        )
    }
}
