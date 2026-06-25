import XCTest
import AVFoundation
@testable import SequencerAI

final class SamplePlaybackEngineTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        fixtureURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        try writeSilentWAV(to: fixtureURL, durationSeconds: 0.1)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureURL)
        MainAudioGraph.useManualRenderingForAutomation = false
    }

    private func writeSilentWAV(to url: URL, durationSeconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(durationSeconds * format.sampleRate))!
        buffer.frameLength = buffer.frameCapacity
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    private func makeEngine() -> SamplePlaybackEngine? {
        let engine = SamplePlaybackEngine()
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    func test_playReturnsHandle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(handle)
    }

    func test_playWithoutStart_returnsNil() {
        let engine = SamplePlaybackEngine()
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil))
    }

    func test_playWithoutPrepareTrack_returnsNilWhenStarted() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        XCTAssertNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: UUID(), at: nil))
    }

    func test_playSliceWithoutPrepareTrack_returnsNilWhenStarted() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        XCTAssertNil(engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 0,
            endFrame: 100,
            settings: .default,
            trackID: UUID(),
            at: nil,
            reverse: false,
            stepParameters: nil
        ))
    }

    func test_playSliceWithPreparedTrack_returnsHandle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let handle = engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 0,
            endFrame: 100,
            settings: .default,
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )
        XCTAssertNotNil(handle)
    }

    // MARK: - Mute as ramped gain

    /// Poll the per-track output gain until it settles near `expected` (the
    /// ramp runs asynchronously on a background queue, ~12 ms).
    private func waitForTrackGain(
        _ engine: SamplePlaybackEngine,
        trackID: UUID,
        expected: Float,
        tolerance: Float = 0.001,
        timeout: TimeInterval = 1.0
    ) -> Float? {
        let deadline = Date().addingTimeInterval(timeout)
        var last = engine.trackOutputGainForTesting(trackID: trackID)
        while Date() < deadline {
            last = engine.trackOutputGainForTesting(trackID: trackID)
            if let last, abs(last - expected) <= tolerance {
                return last
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return last
    }

    func test_setTrackMuteGain_ramps_outputVolumeToZero_andRestoresOnUnmute() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.setTrackMix(trackID: trackID, level: 0.8, pan: 0)

        XCTAssertEqual(try XCTUnwrap(engine.trackOutputGainForTesting(trackID: trackID)), 0.8, accuracy: 0.001)

        // Mute → gain ramps to 0 (voices keep playing; this is gain, not gate).
        engine.setTrackMuteGain(trackID: trackID, muted: true)
        let muted = waitForTrackGain(engine, trackID: trackID, expected: 0)
        XCTAssertEqual(try XCTUnwrap(muted), 0, accuracy: 0.001)

        // Unmute → gain ramps back to the stored fader level (not lost).
        engine.setTrackMuteGain(trackID: trackID, muted: false)
        let unmuted = waitForTrackGain(engine, trackID: trackID, expected: 0.8)
        XCTAssertEqual(try XCTUnwrap(unmuted), 0.8, accuracy: 0.001)
    }

    func test_setTrackMix_whileMuted_keepsGainAtZero_butRestoresNewLevelOnUnmute() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.setTrackMix(trackID: trackID, level: 0.5, pan: 0)
        engine.setTrackMuteGain(trackID: trackID, muted: true)
        _ = waitForTrackGain(engine, trackID: trackID, expected: 0)

        // Moving the fader while muted must NOT un-silence the track.
        engine.setTrackMix(trackID: trackID, level: 0.9, pan: 0)
        XCTAssertEqual(try XCTUnwrap(engine.trackOutputGainForTesting(trackID: trackID)), 0, accuracy: 0.001)

        // Unmute restores the new fader level.
        engine.setTrackMuteGain(trackID: trackID, muted: false)
        let unmuted = waitForTrackGain(engine, trackID: trackID, expected: 0.9)
        XCTAssertEqual(try XCTUnwrap(unmuted), 0.9, accuracy: 0.001)
    }

    // F1 (OR-combine): mixer-mute and layer-mute are INDEPENDENT sources. A
    // layer-mute toggle must NOT clobber a standing mixer-mute (the old
    // last-writer-wins bug un-silenced a mixer-muted track when the layer-mute
    // path wrote `false`). Effective gain = mixerMuted || layerMuted.
    func test_setTrackMuteGain_orCombinesMixerAndLayerSources() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.setTrackMix(trackID: trackID, level: 0.8, pan: 0)
        XCTAssertEqual(try XCTUnwrap(engine.trackOutputGainForTesting(trackID: trackID)), 0.8, accuracy: 0.001)

        // Mixer-mute the track.
        engine.setTrackMuteGain(trackID: trackID, muted: true, source: .mixer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0)), 0, accuracy: 0.001)

        // Layer-mute it too, then layer-UNMUTE it. The mixer-mute still stands,
        // so the track MUST stay silent (the repro for the OR-not-implemented bug).
        engine.setTrackMuteGain(trackID: trackID, muted: true, source: .layer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0)), 0, accuracy: 0.001)
        engine.setTrackMuteGain(trackID: trackID, muted: false, source: .layer)
        // Give the ramp a moment; gain must remain 0 (mixer-mute wins).
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0)), 0, accuracy: 0.001)

        // Only when the MIXER source also clears does the track come back.
        engine.setTrackMuteGain(trackID: trackID, muted: false, source: .mixer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0.8)), 0.8, accuracy: 0.001)
    }

    // Symmetric case: a standing LAYER-mute must survive a mixer-mute+unmute.
    func test_setTrackMuteGain_layerMuteSurvivesMixerToggle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.setTrackMix(trackID: trackID, level: 0.5, pan: 0)

        engine.setTrackMuteGain(trackID: trackID, muted: true, source: .layer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0)), 0, accuracy: 0.001)
        // Mixer-mute then unmute; the layer-mute still stands → stay silent.
        engine.setTrackMuteGain(trackID: trackID, muted: true, source: .mixer)
        engine.setTrackMuteGain(trackID: trackID, muted: false, source: .mixer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0)), 0, accuracy: 0.001)
        // Clearing the layer source restores the level.
        engine.setTrackMuteGain(trackID: trackID, muted: false, source: .layer)
        XCTAssertEqual(try XCTUnwrap(waitForTrackGain(engine, trackID: trackID, expected: 0.5)), 0.5, accuracy: 0.001)
    }

    func test_playSliceMonoReusesAndStopsSingleVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        _ = engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 0,
            endFrame: 100,
            settings: SlicerSettings(voiceMode: .mono),
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )
        _ = engine.playSlice(
            sampleURL: fixtureURL,
            startFrame: 100,
            endFrame: 200,
            settings: SlicerSettings(voiceMode: .mono),
            trackID: trackID,
            at: nil,
            reverse: false,
            stepParameters: nil
        )

        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.voiceMode), [.mono, .mono])
        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.voiceIndex), [0, 0])
        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.stoppedPriorVoice), [true, true])
    }

    func test_playSliceMonoRapidAlternatingSlicesAlwaysReusesSingleVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        let settings = SlicerSettings(voiceMode: .mono)
        for index in 0..<32 {
            let start = AVAudioFramePosition((index % 8) * 64)
            let parameters = SliceTriggerStepParameters(
                gain: Double((index % 5) - 2),
                startTrim: index.isMultiple(of: 3) ? 0.15 : 0,
                endTrim: index.isMultiple(of: 4) ? 0.2 : 0,
                pan: index.isMultiple(of: 2) ? -0.5 : 0.5,
                filter: Double(index % 10) / 10,
                attackMs: index.isMultiple(of: 5) ? 2 : 0,
                releaseMs: index.isMultiple(of: 6) ? 3 : 0,
                reverse: index.isMultiple(of: 7),
                choke: false
            )

            _ = engine.playSlice(
                sampleURL: fixtureURL,
                startFrame: start,
                endFrame: start + 512,
                settings: settings,
                trackID: trackID,
                at: nil,
                reverse: parameters.reverse,
                stepParameters: parameters
            )
        }

        XCTAssertEqual(engine.voiceSelectionsForTesting.count, 32)
        XCTAssertEqual(Set(engine.voiceSelectionsForTesting.map(\.voiceMode)), [.mono])
        XCTAssertEqual(Set(engine.voiceSelectionsForTesting.map(\.voiceIndex)), [0])
        XCTAssertEqual(Set(engine.voiceSelectionsForTesting.map(\.stoppedPriorVoice)), [true])
    }

    func test_samplePlaybackRemainsPolyphonicByDefault() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)

        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.voiceMode), [.polyphonic, .polyphonic])
        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.voiceIndex), [0, 1])
        XCTAssertEqual(engine.voiceSelectionsForTesting.map(\.stoppedPriorVoice), [false, false])
    }

    func test_effectivePlaybackTime_clampsStaleHostTimeToImmediate() {
        let now = ProcessInfo.processInfo.systemUptime
        let stale = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: now - 0.05))
        let future = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: now + 0.05))
        let sampleTime = AVAudioTime(sampleTime: 128, atRate: 44_100)

        XCTAssertNil(SamplePlaybackEngine.effectivePlaybackTime(for: nil, now: now))
        XCTAssertNil(SamplePlaybackEngine.effectivePlaybackTime(for: stale, now: now))
        XCTAssertTrue(SamplePlaybackEngine.effectivePlaybackTime(for: future, now: now) === future)
        XCTAssertTrue(SamplePlaybackEngine.effectivePlaybackTime(for: sampleTime, now: now) === sampleTime)
    }

    func test_startRepairsPreparedVoiceGraphBeforePlayback() throws {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectFirstPreparedVoiceForTesting(trackID: trackID)
        XCTAssertFalse(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))

        do {
            try engine.start()
        } catch {
            throw XCTSkip("Audio engine unavailable in this environment: \(error)")
        }
        defer { engine.stop() }

        XCTAssertTrue(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))
        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(handle)
    }

    func test_playRepairsDisconnectedPreparedVoiceAfterStart() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectFirstPreparedVoiceForTesting(trackID: trackID)
        XCTAssertFalse(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))

        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)

        XCTAssertNotNil(handle)
        XCTAssertTrue(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))
    }

    func test_playRepairsDisconnectedPreparedTrackMixerAfterStart() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectPreparedTrackMixerOutputForTesting(trackID: trackID)
        XCTAssertFalse(engine.isPreparedTrackMixerOutputConnectedForTesting(trackID: trackID))

        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)

        XCTAssertNotNil(handle)
        XCTAssertTrue(engine.isPreparedTrackMixerOutputConnectedForTesting(trackID: trackID))
    }

    func test_playRepairsDisconnectedPreparedTrackTerminalAfterStart() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectPreparedTrackTerminalOutputForTesting(trackID: trackID)
        XCTAssertFalse(engine.isPreparedTrackTerminalOutputConnectedForTesting(trackID: trackID))

        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)

        XCTAssertNotNil(handle)
        XCTAssertTrue(engine.isPreparedTrackTerminalOutputConnectedForTesting(trackID: trackID))
    }

    @MainActor
    func test_preparedTrackRoutedToExistingMixerBusFeedsBusInput() throws {
        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let trackID = UUID()
        let busID = UUID()

        graph.installMixerBuses([MixerBus(id: busID, name: "Drum Bus")])
        engine.prepareTrack(trackID: trackID)
        engine.setTrackOutputBus(trackID: trackID, busID: busID)

        XCTAssertNotNil(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertEqual(
            engine.preparedTrackRouteReadoutForTesting(trackID: trackID),
            [
                "prepared": true,
                "busSafeRoute": true,
                "voiceToVoiceFilter": false,
                "voiceFilterToMixer": true,
                "mixerToTrackFilter": false,
                "trackFilterHasOutput": true,
                "voicePlayable": false,
            ]
        )
    }

    @MainActor
    func test_preparedTrackRoutedToMixerBusInstalledAfterRouteRefeedsBusInput() throws {
        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        let trackID = UUID()
        let busID = UUID()

        engine.prepareTrack(trackID: trackID)
        engine.setTrackOutputBus(trackID: trackID, busID: busID)
        XCTAssertEqual(engine.preparedTrackRouteReadoutForTesting(trackID: trackID)["busSafeRoute"], false)

        graph.installMixerBuses([MixerBus(id: busID, name: "Drum Bus")])
        engine.setTrackOutputBus(trackID: trackID, busID: busID)

        XCTAssertNotNil(graph.mixerBusReadoutForTesting(busID: busID))
        XCTAssertEqual(
            engine.preparedTrackRouteReadoutForTesting(trackID: trackID),
            [
                "prepared": true,
                "busSafeRoute": true,
                "voiceToVoiceFilter": false,
                "voiceFilterToMixer": true,
                "mixerToTrackFilter": false,
                "trackFilterHasOutput": true,
                "voicePlayable": false,
            ]
        )
    }

    func test_applyEnvelope_shapesAttackAndRelease() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 10)!
        buffer.frameLength = 10
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<10 {
            samples[index] = 1
        }

        SamplePlaybackEngine.applyEnvelope(to: buffer, attackMs: 3, releaseMs: 3)

        XCTAssertEqual(samples[0], 0, accuracy: 0.0001)
        XCTAssertEqual(samples[1], Float(1.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(samples[3], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[6], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[8], Float(1.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(samples[9], 0, accuracy: 0.0001)
    }

    func test_applyEnvelope_zeroEnvelopeLeavesBufferUntouched() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        buffer.frameLength = 4
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4 {
            samples[index] = Float(index + 1)
        }

        SamplePlaybackEngine.applyEnvelope(to: buffer, attackMs: 0, releaseMs: 0)

        XCTAssertEqual(samples[0], 1, accuracy: 0.0001)
        XCTAssertEqual(samples[1], 2, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 3, accuracy: 0.0001)
        XCTAssertEqual(samples[3], 4, accuracy: 0.0001)
    }

    func test_prepareTrack_isIdempotent() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.prepareTrack(trackID: trackID)
        XCTAssertEqual(engine.preparedTrackIDs, [trackID])
    }

    func test_prepareTrack_thenRemoveTrack_clearsBookkeeping() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.removeTrack(trackID: trackID)
        XCTAssertTrue(engine.preparedTrackIDs.isEmpty)
    }

    func test_rapidPlays_doNotCrash() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        for _ in 0..<20 {
            let trackID = UUID()
            engine.prepareTrack(trackID: trackID)
            _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        }
    }

    /// Off-main play is fire-and-forget: it returns nil immediately (voice
    /// handles are only meaningful to main-thread callers) and must never
    /// sync onto the main thread — that hop deadlocked against
    /// TickClock.stop()'s tick-queue join. Prepared voices can schedule on
    /// the fast path. If a prepared voice fails during that fast path, repair is
    /// deferred instead of queued from the trigger path.
    func test_playFromBackgroundQueue_isFireAndForgetWithoutBlocking() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let returned = expectation(description: "background sample play returns")
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let lock = NSLock()
        var handle: VoiceHandle?

        DispatchQueue(label: "SamplePlaybackEngineTests.background-play").async {
            let result = engine.play(sampleURL: self.fixtureURL, settings: .default, trackID: trackID, at: nil)
            lock.lock()
            handle = result
            lock.unlock()
            returned.fulfill()
        }

        wait(for: [returned], timeout: 2)
        lock.lock()
        let resolvedHandle = handle
        lock.unlock()
        XCTAssertNil(resolvedHandle)

        // Drain the deferred main hop so the voice scheduling actually runs
        // (this would surface a crash if the deferred path broke).
        let drained = expectation(description: "main hop drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    func test_backgroundFastPathFailureDefersRepairInsteadOfMainHopRepairStorm() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }

        let returned = expectation(description: "background failed sample play returns")
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.disconnectFirstPreparedVoiceForFastPathFailureForTesting(trackID: trackID)
        XCTAssertFalse(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))

        DispatchQueue(label: "SamplePlaybackEngineTests.background-failed-play").async {
            _ = engine.play(sampleURL: self.fixtureURL, settings: .default, trackID: trackID, at: nil)
            returned.fulfill()
        }

        wait(for: [returned], timeout: 2)
        XCTAssertEqual(engine.deferredPreparedTrackRepairIDsForTesting, [trackID])

        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertFalse(
            engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID),
            "Failed fast-path playback must not queue a main-thread graph repair"
        )

        engine.prepareTrack(trackID: trackID)
        XCTAssertTrue(engine.isFirstPreparedVoiceConnectedForTesting(trackID: trackID))
        XCTAssertTrue(engine.deferredPreparedTrackRepairIDsForTesting.isEmpty)
    }

    /// Main-thread play keeps returning a live voice handle.
    func test_playFromMainThread_returnsHandle() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)

        XCTAssertNotNil(handle)
    }

    func test_audition_runsIndependent() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        engine.audition(sampleURL: fixtureURL)
        _ = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
    }

    /// start=1, length=0 must produce a clamped 1-frame segment (not zero frames,
    /// which AVAudioPlayerNode would reject). The handle must be non-nil (voice was
    /// allocated), stoppable (voice is registered in the engine), and the engine must
    /// remain operational for subsequent plays.
    func test_playWithExtremeTrimSettings_clampsToOneFrameSegment() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let settings = SamplerSettings(start: 1, length: 0, gain: 0)

        // The call must succeed (not return nil) — the bounds clamp produced a
        // valid 1-frame segment that AVAudioPlayerNode accepted.
        let handle = try XCTUnwrap(
            engine.play(sampleURL: fixtureURL, settings: settings, trackID: trackID, at: nil),
            "start=1/length=0 must return a handle; the 1-frame clamp must succeed"
        )

        // The voice must be registered: stopVoice must not crash.
        engine.stopVoice(handle)

        // Engine must still accept new play calls after the extreme-settings voice.
        let nextHandle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil)
        XCTAssertNotNil(nextHandle, "Engine must remain operational after extreme-trim play")
    }

    func test_stopVoice_silencesThatVoice() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        guard let handle = engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil) else {
            XCTFail("play returned nil in a started engine"); return
        }
        engine.stopVoice(handle)
    }

    func test_missingFile_returnsNil() throws {
        guard let engine = makeEngine() else { return }
        defer { engine.stop() }
        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        XCTAssertNil(engine.play(sampleURL: missing, settings: .default, trackID: trackID, at: nil))
    }

    func test_setTrackMix_doesNotCrash() {
        let engine = SamplePlaybackEngine()
        let trackID = UUID()
        engine.setTrackMix(trackID: trackID, level: 0.5, pan: 0.25)
        XCTAssertEqual(engine.preparedTrackIDs, [trackID])
    }

    func test_removeTrack_unknownIsNoOp() {
        let engine = SamplePlaybackEngine()
        engine.removeTrack(trackID: UUID())
    }

    // MARK: - Route bus -> master keeps playable voices (regression)

    /// Regression for the route-to-master SILENCE bug: a track routed to a mixer
    /// bus and then back to master previously had its bus voice pool torn down
    /// WITHOUT its master voice pool being re-established, so it went silent and
    /// never recovered. The fix rebuilds the master (prepared track) voice pool
    /// in the teardownBus branch of `setTrackOutputBus`. This asserts that after
    /// bus -> master the track is on the master route with playable voices and
    /// `play` succeeds.
    @MainActor
    func test_routeBusToMaster_reestablishesPlayableMasterVoices() throws {
        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        try engine.start()
        defer { engine.stop() }

        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)

        // Route to the bus: the track now plays on the bus voice pool.
        engine.setTrackOutputBus(trackID: trackID, busID: busID)
        let onBus = engine.preparedTrackRouteReadoutForTesting(trackID: trackID)
        XCTAssertEqual(onBus["prepared"], true, "track should be prepared on the bus")
        XCTAssertEqual(onBus["busSafeRoute"], true, "track should be on the bus route")

        // Route back to master: the bus pool is torn down and the master voice
        // pool MUST be re-established so the track keeps sounding.
        engine.setTrackOutputBus(trackID: trackID, busID: nil)
        let onMaster = engine.preparedTrackRouteReadoutForTesting(trackID: trackID)
        XCTAssertEqual(onMaster["prepared"], true, "track must remain prepared after bus -> master")
        XCTAssertEqual(onMaster["busSafeRoute"], false, "track must be back on the master route")
        XCTAssertEqual(
            onMaster["voiceToVoiceFilter"], true,
            "master voice -> voice filter must be reconnected"
        )
        XCTAssertEqual(
            onMaster["voiceFilterToMixer"], true,
            "master voice filter -> track mixer must be reconnected"
        )
        XCTAssertEqual(
            onMaster["trackFilterHasOutput"], true,
            "master track filter must drive the master output chain"
        )
        XCTAssertEqual(
            onMaster["voicePlayable"], true,
            "master voices must be playable after the reroute"
        )

        // The watertight acceptance: the track keeps sounding on master.
        XCTAssertNotNil(
            engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil),
            "play must succeed on the master route after bus -> master (no lost voices)"
        )
    }

    /// Master -> bus -> master also keeps the track playable on master.
    @MainActor
    func test_routeMasterToBusToMaster_keepsPlayableVoices() throws {
        let graph = MainAudioGraph()
        let engine = SamplePlaybackEngine(audioGraph: graph)
        try engine.start()
        defer { engine.stop() }

        let busID = UUID()
        graph.installMixerBuses([MixerBus(id: busID, name: "FX Bus")])

        let trackID = UUID()
        engine.prepareTrack(trackID: trackID)
        XCTAssertNotNil(engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil))

        engine.setTrackOutputBus(trackID: trackID, busID: busID)
        engine.setTrackOutputBus(trackID: trackID, busID: nil)

        let onMaster = engine.preparedTrackRouteReadoutForTesting(trackID: trackID)
        XCTAssertEqual(onMaster["prepared"], true)
        XCTAssertEqual(onMaster["busSafeRoute"], false)
        XCTAssertEqual(onMaster["voicePlayable"], true)
        XCTAssertNotNil(
            engine.play(sampleURL: fixtureURL, settings: .default, trackID: trackID, at: nil),
            "track must keep sounding on master after master -> bus -> master"
        )
    }
}
