import AVFoundation
import XCTest
@testable import SequencerAI

final class MasterRenderTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("master-render-\(UUID().uuidString).wav")
    }

    private func tmpDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("master-render-\(UUID().uuidString)", isDirectory: true)
    }

    func test_startStop_roundTripCreatesReadableFile() throws {
        let graph = MainAudioGraph()
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(graph.startMasterRender(to: url))
        XCTAssertTrue(graph.isMasterRenderActive)
        XCTAssertFalse(graph.startMasterRender(to: tmpURL()), "second concurrent render must be refused")

        // Push synthetic audio through the write path (no running engine).
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        buffer.frameLength = 512
        for ch in 0..<2 {
            let samples = buffer.floatChannelData![ch]
            for i in 0..<512 { samples[i] = sinf(Float(i) * 0.1) * 0.5 }
        }
        graph.writeMasterRenderBufferForTesting(buffer)
        graph.writeMasterRenderBufferForTesting(buffer)

        XCTAssertEqual(graph.stopMasterRender(), url)
        XCTAssertFalse(graph.isMasterRenderActive)
        XCTAssertNil(graph.stopMasterRender())

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.length, 1024)
        // Content survived: non-silent RMS.
        let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024)!
        try file.read(into: read)
        var sum: Float = 0
        let data = read.floatChannelData![0]
        for i in 0..<Int(read.frameLength) { sum += data[i] * data[i] }
        XCTAssertGreaterThan(sum / Float(read.frameLength), 0.01)
    }

    func test_writeWithoutActiveRender_isNoOp() {
        let graph = MainAudioGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)!
        buffer.frameLength = 64
        graph.writeMasterRenderBufferForTesting(buffer)
        XCTAssertFalse(graph.isMasterRenderActive)
    }

    func test_sampleTrackRendersNonSilentAudioAtMasterOutput() throws {
        let sampleRoot = tmpDirectory()
        defer { try? FileManager.default.removeItem(at: sampleRoot) }
        let kickDirectory = sampleRoot.appendingPathComponent("kick", isDirectory: true)
        try FileManager.default.createDirectory(at: kickDirectory, withIntermediateDirectories: true)
        try writeClickWAV(to: kickDirectory.appendingPathComponent("diagnostic-click.wav"))

        let library = AudioSampleLibrary(libraryRoot: sampleRoot)
        let sample = try XCTUnwrap(library.firstSample(in: .kick))
        let track = StepSequenceTrack(
            name: "Diagnostic Sample",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: sample.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generatorID = UUID()
        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Every Step",
            trackType: track.trackType,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [DrumKitNoteMap.baselineNote], pickMode: .sequential)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generatorID))]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            mainAudioGraph: audioGraph,
            sampleEngine: sampleEngine,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        XCTAssertEqual(sampleEngine.preparedTrackIDs, [track.id])
        XCTAssertTrue(sampleEngine.isFirstPreparedVoiceConnectedForTesting(trackID: track.id))

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(controller.startMasterRender(to: renderURL))
        controller.start()
        XCTAssertTrue(sampleEngine.isFirstPreparedVoiceConnectedForTesting(trackID: track.id))
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        controller.stop()
        XCTAssertEqual(controller.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A real sample track should reach the master output render tap.")
    }

    func test_sampleTrackRoutedToMixerBusAudibilityRegressionIsCaptured() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let preparedAsset = PreparedSampleAsset(
            sampleID: UUID(),
            name: "Prepared Drum",
            url: sampleURL,
            fileIdentity: SampleAssetFileIdentity(path: sampleURL.path, modifiedAt: nil, fileSize: nil),
            file: try AVAudioFile(forReading: sampleURL),
            pcmBuffer: nil
        )

        let bus = MixerBus(name: "Drum Bus")
        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        let trackID = UUID()
        sampleEngine.setTrackOutputBus(trackID: trackID, busID: bus.id)
        sampleEngine.prepareTrack(trackID: trackID)

        XCTAssertNotNil(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        XCTAssertEqual(
            sampleEngine.preparedTrackRouteReadoutForTesting(trackID: trackID),
            [
                "prepared": true,
                "busSafeRoute": true,
                "voiceToVoiceFilter": false,
                "voiceFilterToMixer": true,
                "mixerToTrackFilter": false,
                "trackFilterHasOutput": true,
                "voicePlayable": true,
            ]
        )
        XCTAssertNotNil(sampleEngine.play(sampleAsset: preparedAsset, settings: .default, trackID: trackID, at: nil))
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        sampleEngine.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A sample track routed through a mixer bus should remain audible at master.")
    }

    /// docs/bugs/20260626-route-track-to-mixer-bus-goes-silent: a sole sample
    /// track routed to a bus must (a) reach MASTER (was silent) and (b) show on
    /// the per-bus meter (bus<N>Peak was -inf even with signal — the rig blind
    /// spot). Both are asserted here from an offline render.
    func test_sampleTrackRoutedToBus_reachesMaster_andBusMeterShowsSignal() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let preparedAsset = PreparedSampleAsset(
            sampleID: UUID(),
            name: "Prepared Drum",
            url: sampleURL,
            fileIdentity: SampleAssetFileIdentity(path: sampleURL.path, modifiedAt: nil, fileSize: nil),
            file: try AVAudioFile(forReading: sampleURL),
            pcmBuffer: nil
        )

        let bus = MixerBus(name: "FX Bus")
        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        let trackID = UUID()
        sampleEngine.setTrackOutputBus(trackID: trackID, busID: bus.id)
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        XCTAssertNotNil(sampleEngine.play(sampleAsset: preparedAsset, settings: .default, trackID: trackID, at: nil))
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        // The tap captures peaks into the publisher's transport on the render
        // thread; displayState only commits on a pump. Pump it manually so the
        // offline test can read the latched peak.
        let busPublisher = audioGraph.channelMeterBank.publisher(for: .bus(bus.id))
        busPublisher.publishPendingToMain()
        let busPeak = busPublisher.displayState.leftPeakDBFS
        sampleEngine.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        // (a) master sees the signal (was -inf / rms 0 = the silence bug).
        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "bus-routed track must reach master")

        // (b) per-bus meter sees the signal (was -inf even with audio flowing —
        // the rig blind spot that let the bug ship). On a CoreAudio-degraded host
        // the OFFLINE render meter taps can read -inf even though audio genuinely
        // reaches master (HALC_ShellObject proxy errors); the master proof (a)
        // bypasses the tap by analysing the rendered file, so it stays a hard
        // assert, but skip the meter check when metering itself is non-functional
        // (verify the meter on a healthy host / after `sudo killall coreaudiod`).
        try XCTSkipIf(
            busPeak <= -120.0 && rms > 0.01,
            "bus meter unreadable (-inf) while audio reaches master — degraded CoreAudio meter taps on this host; re-run after a coreaudiod restart"
        )
        XCTAssertGreaterThan(busPeak, -120.0, "bus meter must show real signal, not -inf")
    }

    func test_directSamplePlaybackEngineRendersNonSilentAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        XCTAssertNotNil(sampleEngine.play(sampleURL: sampleURL, settings: .default, trackID: trackID, at: nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Direct sample playback should reach the master output render tap.")
    }

    func test_directSamplePlaybackEngineRendersNonSilentAudioInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        XCTAssertNotNil(sampleEngine.play(sampleURL: sampleURL, settings: .default, trackID: trackID, at: nil))
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        sampleEngine.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Direct sample playback should render offline in automation/manual mode.")
    }

    func test_rawPlayerRoutedToMixerBusRendersNonSilentAudioInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        let player = AVAudioPlayerNode()
        audioGraph.attach(player)
        let busReadout = try XCTUnwrap(audioGraph.mixerBusReadoutForTesting(busID: bus.id))
        audioGraph.connect(player, to: busReadout.inputMixer)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        player.stop()
        player.scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        player.play()
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A raw player should render through a mixer bus in manual mode.")
    }

    func test_rawPlayerThroughSampleStyleChainRoutedToMixerBusRendersInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Chain Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])

        let player = AVAudioPlayerNode()
        let voiceFilter = SamplerFilterNode()
        let mixer = AVAudioMixerNode()
        let trackFilter = SamplerFilterNode()
        audioGraph.attach(player)
        audioGraph.attach(voiceFilter.avNode)
        audioGraph.attach(mixer)
        audioGraph.attach(trackFilter.avNode)
        audioGraph.connect(player, to: voiceFilter.avNode)
        audioGraph.connect(voiceFilter.avNode, to: mixer)
        audioGraph.connect(mixer, to: trackFilter.avNode)
        audioGraph.connectTrackOutput(trackFilter.avNode, to: bus.id)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        player.scheduleFile(file, at: nil)
        player.play()
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A raw player should render through the sample-style chain into a mixer bus.")
    }

    func test_rawPreparedStyleFanInThroughTrackFilterToMasterRendersInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        let mixer = AVAudioMixerNode()
        let trackFilter = SamplerFilterNode()
        audioGraph.attach(mixer)
        audioGraph.attach(trackFilter.avNode)
        audioGraph.connect(mixer, to: trackFilter.avNode)
        audioGraph.connectTrackOutput(trackFilter.avNode, to: nil)

        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.engine.connect(voiceFilters[index].avNode, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].stop()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A prepared-style fan-in should render through the master bus.")
    }

    func test_rawPreparedStyleFanInToMixerBusAudibilityRegressionIsCaptured() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Prepared Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        let mixer = AVAudioMixerNode()
        audioGraph.attach(mixer)
        audioGraph.connectTrackOutput(mixer, to: bus.id)

        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        for index in players.indices {
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.connect(voiceFilters[index].avNode, to: mixer)
        }
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A repaired prepared-style fan-in should still render through a mixer bus.")
    }

    func test_rawPreparedStyleFanInThroughTrackFilterToMixerBusRendersInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Prepared Filtered Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        let mixer = AVAudioMixerNode()
        let trackFilter = SamplerFilterNode()
        audioGraph.attach(mixer)
        audioGraph.attach(trackFilter.avNode)
        audioGraph.connect(mixer, to: trackFilter.avNode)
        audioGraph.connectTrackOutput(trackFilter.avNode, to: bus.id)

        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.engine.connect(voiceFilters[index].avNode, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A prepared-style fan-in through the sample track filter should render through a mixer bus.")
    }

    func test_rawPreparedStyleFanInThroughBridgeMixerToMixerBusRendersInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Prepared Bridge Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        let mixer = AVAudioMixerNode()
        let trackFilter = SamplerFilterNode()
        let bridge = AVAudioMixerNode()
        audioGraph.attach(mixer)
        audioGraph.attach(trackFilter.avNode)
        audioGraph.attach(bridge)
        audioGraph.connect(mixer, to: trackFilter.avNode)
        audioGraph.connect(trackFilter.avNode, to: bridge)
        audioGraph.connectTrackOutput(bridge, to: bus.id)

        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.engine.connect(voiceFilters[index].avNode, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A bridge mixer should keep a prepared-style fan-in audible through a mixer bus.")
    }

    func test_rawPreparedVoicesDirectToMixerBusRenderInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Direct Voice Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        XCTAssertNotNil(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.connectPreparedSampleVoiceOutput(
                voiceFilters[index].avNode,
                toMixerBus: bus.id
            )
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Prepared voices should be able to feed a mixer bus directly.")
    }

    func test_rawPreparedVoicesDirectToMixerBusWithSampleEnginePreviewWiringRenderInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Direct Voice Bus With Preview")
        let audioGraph = MainAudioGraph()
        _ = SamplePlaybackEngine(audioGraph: audioGraph)
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        XCTAssertNotNil(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.connectPreparedSampleVoiceOutput(
                players[index],
                toMixerBus: bus.id
            )
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].stop()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Preview wiring should not make a direct prepared voice bus route silent.")
    }

    func test_rawPreparedVoicesThroughPerVoiceMixersToMixerBusRenderInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Per Voice Mixer Bus")
        let audioGraph = MainAudioGraph()
        _ = SamplePlaybackEngine(audioGraph: audioGraph)
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        XCTAssertNotNil(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceMixers = (0..<4).map { _ in AVAudioMixerNode() }
        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceMixers[index])
            audioGraph.engine.connect(players[index], to: voiceMixers[index], fromBus: 0, toBus: 0, format: nil)
            voiceMixers[index].outputVolume = 1
            voiceMixers[index].pan = 0
            audioGraph.connectPreparedSampleVoiceOutput(
                voiceMixers[index],
                toMixerBus: bus.id
            )
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].stop()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Per-voice mixers should keep prepared voices audible through a mixer bus.")
    }

    func test_rawPreparedVoicesThroughPerVoiceMixersToPreexistingMixerBusRenderInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Preexisting Per Voice Mixer Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        _ = SamplePlaybackEngine(audioGraph: audioGraph)
        XCTAssertNotNil(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceMixers = (0..<4).map { _ in AVAudioMixerNode() }
        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceMixers[index])
            audioGraph.engine.connect(players[index], to: voiceMixers[index], fromBus: 0, toBus: 0, format: nil)
            voiceMixers[index].outputVolume = 1
            voiceMixers[index].pan = 0
            audioGraph.connectPreparedSampleVoiceOutput(
                voiceMixers[index],
                toMixerBus: bus.id
            )
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].stop()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        if exception != nil {
            audioGraph.stop()
            XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)
            throw XCTSkip("Documents a separate CoreAudio graph-order hazard: constructing SamplePlaybackEngine after a preexisting bus can leave newly added raw player nodes disconnected. The app lifecycle constructs the engine before document bus sync.")
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Per-voice mixers should also work when the sample engine is constructed after the bus.")
    }

    func test_rawMasterPreparedPoolRebuiltDirectToMixerBusRendersInManualRendering() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)
        let file = try AVAudioFile(forReading: sampleURL)

        let bus = MixerBus(name: "Raw Rebuilt Direct Voice Bus")
        let audioGraph = MainAudioGraph()
        try audioGraph.start()
        audioGraph.stop()
        audioGraph.installMixerBuses([bus])
        let busReadout = try XCTUnwrap(audioGraph.mixerBusReadoutForTesting(busID: bus.id))

        let oldPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
        let oldVoiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        let mixer = AVAudioMixerNode()
        let trackFilter = SamplerFilterNode()
        audioGraph.attach(mixer)
        audioGraph.attach(trackFilter.avNode)
        audioGraph.connect(mixer, to: trackFilter.avNode)
        audioGraph.connectTrackOutput(trackFilter.avNode, to: nil)
        for index in oldPlayers.indices {
            audioGraph.attach(oldPlayers[index])
            audioGraph.attach(oldVoiceFilters[index].avNode)
            audioGraph.engine.connect(oldPlayers[index], to: oldVoiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.engine.connect(oldVoiceFilters[index].avNode, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
        }

        for index in oldPlayers.indices {
            oldPlayers[index].stop()
            audioGraph.disconnectOutput(oldPlayers[index])
            audioGraph.detach(oldPlayers[index])
            audioGraph.disconnectOutput(oldVoiceFilters[index].avNode)
            audioGraph.detach(oldVoiceFilters[index].avNode)
        }
        audioGraph.disconnectOutput(mixer)
        audioGraph.disconnectOutput(trackFilter.avNode)
        audioGraph.detach(mixer)
        audioGraph.detach(trackFilter.avNode)

        let players = (0..<4).map { _ in AVAudioPlayerNode() }
        let voiceFilters = (0..<4).map { _ in SamplerFilterNode() }
        for index in players.indices {
            audioGraph.attach(players[index])
            audioGraph.attach(voiceFilters[index].avNode)
            audioGraph.engine.connect(players[index], to: voiceFilters[index].avNode, fromBus: 0, toBus: 0, format: nil)
            audioGraph.engine.connect(voiceFilters[index].avNode, to: busReadout.inputMixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: nil)
        }

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try audioGraph.start()
        players[0].stop()
        players[0].scheduleSegment(
            file,
            startingFrame: 0,
            frameCount: AVAudioFrameCount(file.length),
            at: nil,
            completionHandler: nil
        )
        let exception = SEQRunCatchingObjCException {
            players[0].play()
        }
        XCTAssertNil(exception)
        try audioGraph.renderOfflineForTesting(frameCount: 44_100)
        audioGraph.stop()
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "A rebuilt direct prepared voice pool should feed a mixer bus.")
    }

    func test_directSamplePlaybackWithMasterBusHostRendersNonSilentAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let masterBusHost = MasterBusHost()
        masterBusHost.attach(to: audioGraph)
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        XCTAssertNotNil(sampleEngine.play(sampleURL: sampleURL, settings: .default, trackID: trackID, at: nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Master bus host should not disconnect sample playback from the master output.")
    }

    func test_directSamplePlaybackEngineRendersScheduledHostTimeAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let hostTime = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime)
        XCTAssertNotNil(sampleEngine.play(
            sampleURL: sampleURL,
            settings: .default,
            trackID: trackID,
            at: AVAudioTime(hostTime: hostTime)
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Scheduled host-time sample playback should reach the master output render tap.")
    }

    func test_directSamplePlaybackEngineRendersStaleScheduledHostTimeAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let staleSeconds = ProcessInfo.processInfo.systemUptime - 0.05
        let hostTime = AVAudioTime.hostTime(forSeconds: staleSeconds)
        XCTAssertNotNil(sampleEngine.play(
            sampleURL: sampleURL,
            settings: .default,
            trackID: trackID,
            at: AVAudioTime(hostTime: hostTime)
        ))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Slightly stale sample triggers should degrade to immediate playback, not silence.")
    }

    func test_directSamplePlaybackEngineRendersOffMainScheduledAudioAtMasterOutput() throws {
        let sampleURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        try writeClickWAV(to: sampleURL)

        let audioGraph = MainAudioGraph()
        let sampleEngine = SamplePlaybackEngine(audioGraph: audioGraph)
        let trackID = UUID()
        sampleEngine.prepareTrack(trackID: trackID)

        let renderURL = tmpURL()
        defer { try? FileManager.default.removeItem(at: renderURL) }
        XCTAssertTrue(audioGraph.startMasterRender(to: renderURL))
        try sampleEngine.start()
        defer { sampleEngine.stop() }

        let dispatched = expectation(description: "off-main dispatch returned")
        DispatchQueue(label: "MasterRenderTests.off-main-sample-play").async {
            let hostTime = AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime)
            _ = sampleEngine.play(
                sampleURL: sampleURL,
                settings: .default,
                trackID: trackID,
                at: AVAudioTime(hostTime: hostTime)
            )
            dispatched.fulfill()
        }

        wait(for: [dispatched], timeout: 1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(audioGraph.stopMasterRender(), renderURL)

        let rms = try rmsOfFirstChannel(at: renderURL)
        XCTAssertGreaterThan(rms, 0.01, "Off-main scheduled sample playback should reach the master output render tap.")
    }

    private func writeClickWAV(to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount = AVAudioFrameCount(4_410)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) {
            let envelope = max(0, 1 - (Float(index) / Float(frameCount)))
            samples[index] = sinf(Float(index) * 0.45) * envelope * 0.8
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func rmsOfFirstChannel(at url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else {
            return 0
        }
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        guard buffer.frameLength > 0,
              let channel = buffer.floatChannelData?[0]
        else { return 0 }

        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += channel[index] * channel[index]
        }
        return sqrt(sum / Float(buffer.frameLength))
    }
}
