import AVFoundation
import Foundation
import SwiftUI

@MainActor
enum VisualScenarioCommandRunner {
    private static let commandFileEnvironmentKey = "SEQUENCER_AI_VISUAL_COMMAND_FILE"
    private static let commandFileDefaultsKey = "VisualScenarioCommandFile"

    static func runIfConfigured(
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) async {
        let configuredPath = ProcessInfo.processInfo.environment[commandFileEnvironmentKey]
            ?? UserDefaults.standard.string(forKey: commandFileDefaultsKey)
        guard let rawPath = configuredPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        NSLog("[VisualScenarioCommandRunner] watching command file %@", rawPath)

        let commandURL = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        let statusURL = commandURL.appendingPathExtension("status")
        var lastPayload = ""

        while !Task.isCancelled {
            if let payload = try? String(contentsOf: commandURL), payload != lastPayload {
                lastPayload = payload
                apply(
                    command: parse(payload),
                    section: section,
                    session: session,
                    engineController: engineController
                )
                writeStatus(
                    to: statusURL,
                    section: section.wrappedValue,
                    session: session,
                    engineController: engineController
                )
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func parse(_ payload: String) -> [String: String] {
        payload
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let separator = line.firstIndex(of: "=")
                else { return }

                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
    }

    private static func apply(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        if let workspace = command["workspace"],
           let requestedSection = WorkspaceSection(rawValue: workspace) {
            section.wrappedValue = requestedSection
        }

        if let addTrack = command["addTrack"],
           let trackType = TrackType(rawValue: addTrack) {
            session.appendTrack(trackType: trackType)
            section.wrappedValue = .track
        }

        if let gainRaw = command["masterGain"],
           let gain = Double(gainRaw) {
            session.setMasterOutputGain(gain)
            engineController.setLiveMasterOutputGain(gain)
        }

        if let peakRaw = command["meterPeak"],
           let peak = Double(peakRaw) {
            engineController.masterMeterPublisher.recordPeakAmplitudes(left: peak, right: peak)
            engineController.masterMeterPublisher.publishPendingToMain()
        }

        if command["clearClip"] == "true" {
            engineController.masterMeterPublisher.clearClip()
        }

        applySendEffects(command: command, session: session)
        applyTrackFillPreviewFixture(command: command, section: section, session: session)
        applyAudioInputFixture(
            command: command,
            section: section,
            session: session,
            engineController: engineController
        )

        switch command["transport"] {
        case "play":
            engineController.start()
        case "stop":
            engineController.stop()
        default:
            break
        }
    }

    private static func applySendEffects(command: [String: String], session: SequencerDocumentSession) {
        let tracks = session.store.tracks
        for index in tracks.indices {
            let track = tracks[index]
            let sendARaw = command["track\(index)SendA"]
            let sendBRaw = command["track\(index)SendB"]
            guard sendARaw != nil || sendBRaw != nil else { continue }
            session.setTrackSends(
                trackID: track.id,
                sendA: sendARaw.flatMap(Double.init) ?? track.mix.sendA,
                sendB: sendBRaw.flatMap(Double.init) ?? track.mix.sendB
            )
        }

        if let sendAInsert = command["sendAInserts"] {
            session.setSendBusInserts(sendInserts(from: sendAInsert), busID: .sendA)
        }
        if let sendBInsert = command["sendBInserts"] {
            session.setSendBusInserts(sendInserts(from: sendBInsert), busID: .sendB)
        }
    }

    private static func sendInserts(from rawValue: String) -> [SendBusInsert] {
        rawValue
            .split(separator: ",")
            .compactMap { token in
                switch token.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "filter":
                    return .filter()
                case "bitcrusher":
                    return .bitcrusher()
                case "empty", "none", "":
                    return nil
                default:
                    return nil
                }
            }
    }

    private static func writeStatus(
        to statusURL: URL,
        section: WorkspaceSection,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        let meterState = engineController.masterMeterPublisher.displayState
        let selectedAudioInputRuntime = engineController.audioInputRuntime(for: session.store.selectedTrackID)
        let activeAudioInputTrack = session.store.tracks.first { track in
            track.trackType == .audioInput && engineController.audioInputRuntime(for: track.id) != nil
        }
        let activeAudioInputRuntime = activeAudioInputTrack.flatMap { engineController.audioInputRuntime(for: $0.id) }
        let selectedAudioInputReadout = engineController.audioInputRoutingReadoutForTesting(trackID: session.store.selectedTrackID)
        let audioInputTrackCount = session.store.tracks.filter { $0.trackType == .audioInput }.count
        let selectedPattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        let activeFillPreviewTrack = session.trackFillPreviewState.activeTrackID.flatMap { activeTrackID in
            session.store.tracks.first { $0.id == activeTrackID }
        }
        let status = """
        workspace=\(section.rawValue)
        transport=\(engineController.isRunning ? "play" : "stop")
        masterGain=\(session.store.masterBus.masterOutputGain)
        firstTrackSendA=\(session.store.tracks.first?.mix.sendA ?? 0)
        firstTrackSendB=\(session.store.tracks.first?.mix.sendB ?? 0)
        trackCount=\(session.store.tracks.count)
        selectedTrackName=\(session.store.selectedTrack.name)
        selectedTrackType=\(session.store.selectedTrack.trackType.rawValue)
        selectedPatternSourceMode=\(selectedPattern.sourceRef.mode.rawValue)
        selectedPatternHasClip=\(session.store.clipEntry(id: selectedPattern.sourceRef.clipID) != nil)
        selectedPatternHasGenerator=\(session.store.generatorEntry(id: selectedPattern.sourceRef.generatorID) != nil)
        selectedTrackFillPreviewAvailable=\(session.isTrackFillPreviewAvailable(trackID: session.store.selectedTrackID))
        selectedTrackFillPreviewActive=\(session.trackFillPreviewState.isActive(for: session.store.selectedTrackID))
        fillPreviewActiveTrackName=\(activeFillPreviewTrack?.name ?? "none")
        fillPreviewActiveTrackIsSelected=\(session.trackFillPreviewState.activeTrackID == session.store.selectedTrackID)
        selectedPhraseID=\(session.store.selectedPhraseID.uuidString)
        sessionRevision=\(session.revision)
        canAppendAudioInputTrack=\(session.canAppendAudioInputTrack)
        audioInputTrackCount=\(audioInputTrackCount)
        activeAudioInputTrackName=\(activeAudioInputTrack?.name ?? "none")
        activeAudioInputTrackSelected=\(activeAudioInputTrack?.id == session.store.selectedTrackID)
        activeAudioInputArmState=\(activeAudioInputRuntime.map(audioInputArmStateLabel) ?? "none")
        activeAudioInputRouteState=\(activeAudioInputRuntime.map(audioInputRouteStateLabel) ?? "none")
        activeAudioInputRecordingProgress=\(activeAudioInputRuntime?.recordingProgress ?? 0)
        activeAudioInputCaptureBucketCount=\(activeAudioInputRuntime?.captureWaveformBuckets.count ?? 0)
        activeAudioInputCompletedBucketCount=\(activeAudioInputRuntime?.waveformBuckets.count ?? 0)
        sendAInsertCount=\(session.store.sendBusA.inserts.count)
        sendBInsertCount=\(session.store.sendBusB.inserts.count)
        clipLatched=\(meterState.isClipLatched)
        clearClipActionable=\(meterState.isClearClipActionable)
        leftPeakDBFS=\(meterState.leftPeakDBFS)
        rightPeakDBFS=\(meterState.rightPeakDBFS)
        audioInputArmState=\(selectedAudioInputRuntime.map(audioInputArmStateLabel) ?? "none")
        audioInputRouteState=\(selectedAudioInputRuntime.map(audioInputRouteStateLabel) ?? "none")
        audioInputMonitorMode=\(selectedAudioInputRuntime.map(audioInputMonitorModeLabel) ?? "none")
        audioInputActiveMonitorMode=\(selectedAudioInputRuntime.map(audioInputActiveMonitorModeLabel) ?? "none")
        audioInputIsSilent=\(selectedAudioInputRuntime?.isSilent ?? true)
        audioInputCanArm=\((selectedAudioInputRuntime?.routeState ?? .silentUnavailable) == .available)
        audioInputLivePeak=\(selectedAudioInputRuntime?.liveLevel.peak ?? 0)
        audioInputRecordingProgress=\(selectedAudioInputRuntime?.recordingProgress ?? 0)
        audioInputCaptureBucketCount=\(selectedAudioInputRuntime?.captureWaveformBuckets.count ?? 0)
        audioInputCompletedBucketCount=\(selectedAudioInputRuntime?.waveformBuckets.count ?? 0)
        audioInputScheduledLoopFrameCount=\(selectedAudioInputReadout?.scheduledLoopFrameCount ?? 0)
        audioInputLoopPlaybackScheduleCount=\(selectedAudioInputReadout?.loopPlaybackScheduleCount ?? 0)
        """

        try? status.write(to: statusURL, atomically: true, encoding: .utf8)
    }

    private static func audioInputArmStateLabel(_ runtime: EngineController.AudioInputTrackRuntime) -> String {
        switch runtime.armState {
        case .idle:
            return "idle"
        case .armed:
            return "armed"
        case .recording:
            return "recording"
        case .hasLoop:
            return "hasLoop"
        }
    }

    private static func audioInputRouteStateLabel(_ runtime: EngineController.AudioInputTrackRuntime) -> String {
        switch runtime.routeState {
        case .available:
            return "available"
        case .silentUnavailable:
            return "silentUnavailable"
        }
    }

    private static func audioInputMonitorModeLabel(_ runtime: EngineController.AudioInputTrackRuntime) -> String {
        switch runtime.monitorMode {
        case .input:
            return "input"
        case .loop:
            return "loop"
        }
    }

    private static func audioInputActiveMonitorModeLabel(_ runtime: EngineController.AudioInputTrackRuntime) -> String {
        switch runtime.activeMonitorMode {
        case .input:
            return "input"
        case .loop:
            return "loop"
        }
    }

    private static func applyTrackFillPreviewFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["trackFillPreview"] != nil ||
              command["trackFillSource"] != nil ||
              command["trackFillSelectedTrackIndex"] != nil ||
              command["trackFillEnsureSecondClipTrack"] == "true"
        else { return }

        section.wrappedValue = .track

        if command["trackFillEnsureSecondClipTrack"] == "true" {
            ensureTrackCount(2, session: session)
        }

        if let rawIndex = command["trackFillSelectedTrackIndex"],
           let selectedIndex = Int(rawIndex) {
            ensureTrackCount(selectedIndex + 1, session: session)
            let clampedIndex = min(max(0, selectedIndex), session.store.tracks.count - 1)
            session.setSelectedTrackID(session.store.tracks[clampedIndex].id)
        }

        if let sourceState = command["trackFillSource"] {
            applyTrackFillSource(sourceState, session: session)
        }

        switch command["trackFillPreview"] {
        case "on", "active", "true":
            session.enableSelectedTrackFillPreview()
        case "off", "clear", "inactive", "false":
            session.clearTrackFillPreview(reason: .userCleared)
        default:
            break
        }
    }

    private static func ensureTrackCount(_ count: Int, session: SequencerDocumentSession) {
        while session.store.tracks.count < count {
            session.appendTrack(trackType: .monoMelodic)
        }
    }

    private static func applyTrackFillSource(_ sourceState: String, session: SequencerDocumentSession) {
        let trackID = session.store.selectedTrackID
        let slotIndex = session.store.selectedPatternIndex(for: trackID)
        switch sourceState {
        case "clip":
            let pattern = session.store.selectedPattern(for: trackID)
            if let clipID = pattern.sourceRef.clipID,
               session.store.clipEntry(id: clipID) != nil {
                session.assignClipSource(clipID, to: trackID, slotIndex: slotIndex)
            } else {
                _ = session.createBlankClipSource(trackID: trackID, slotIndex: slotIndex)
            }
        case "empty", "unavailable":
            session.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)
        case "generator":
            if let generator = session.store.compatibleGenerators(for: session.store.selectedTrack).first {
                session.assignGeneratorSource(generator.id, to: trackID, slotIndex: slotIndex)
            } else {
                _ = session.createBlankGeneratorSource(trackID: trackID, slotIndex: slotIndex)
            }
        default:
            break
        }
    }

    private static func applyAudioInputFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        guard command["audioInputState"] != nil ||
              command["audioInputFixture"] != nil ||
              command["audioInputAvailableChannels"] != nil
        else { return }

        let requestedAudioInputState = command["audioInputState"] ?? command["audioInputFixture"]
        var trackID = ensureSelectedAudioInputTrack(section: section, session: session)
        if shouldResetAudioInputFixtureTrack(for: requestedAudioInputState) {
            trackID = replaceAudioInputFixtureTrack(section: section, session: session)
        }
        engineController.audioInputCapturePlanOverrideForTesting = { requestedTrackID, bars in
            guard requestedTrackID == trackID else { return nil }
            return AudioInputCapturePlan(
                sampleRate: 44_100,
                channelCount: 2,
                maximumFrameCount: max(1, bars * 4096)
            )
        }
        if let channels = Int(command["audioInputAvailableChannels"] ?? "") {
            engineController.audioInputAvailableChannelCountOverrideForTesting = max(0, channels)
        } else {
            engineController.audioInputAvailableChannelCountOverrideForTesting = 2
        }
        _ = engineController.rerouteAudioInput(trackID: trackID, channel: session.store.selectedTrack.inputChannel)
        _ = engineController.setAudioInputMonitorMode(trackID: trackID, mode: .input)

        switch requestedAudioInputState {
        case "live":
            _ = engineController.cancelAudioInputArm(trackID: trackID)
            publishAudioInputBuffers(
                trackID: trackID,
                engineController: engineController,
                amplitudes: [0.18, 0.42, 0.67, 0.38, 0.74, 0.51]
            )
        case "recording":
            _ = engineController.armAudioInput(trackID: trackID, pendingStartTick: 16)
            engineController.processTick(tickIndex: 16, now: ProcessInfo.processInfo.systemUptime)
            engineController.processTick(tickIndex: 18, now: ProcessInfo.processInfo.systemUptime)
            publishAudioInputBuffers(
                trackID: trackID,
                engineController: engineController,
                amplitudes: audioInputFixtureBuckets()
            )
        case "completed":
            _ = engineController.cancelAudioInputArm(trackID: trackID)
            _ = engineController.markAudioInputLoopPlaceholder(
                trackID: trackID,
                waveformBuckets: audioInputFixtureBuckets()
            )
        case "playback":
            _ = engineController.armAudioInput(trackID: trackID, pendingStartTick: 16)
            engineController.processTick(tickIndex: 16, now: ProcessInfo.processInfo.systemUptime)
            publishAudioInputBuffers(
                trackID: trackID,
                engineController: engineController,
                amplitudes: audioInputFixtureBuckets()
            )
            engineController.processTick(tickIndex: 32, now: ProcessInfo.processInfo.systemUptime)
            _ = engineController.setAudioInputMonitorMode(trackID: trackID, mode: .loop)
            engineController.processTick(tickIndex: 48, now: ProcessInfo.processInfo.systemUptime)
        case "loop-empty":
            _ = engineController.cancelAudioInputArm(trackID: trackID)
            _ = engineController.setAudioInputMonitorMode(trackID: trackID, mode: .loop)
        case "invalid-route":
            engineController.audioInputAvailableChannelCountOverrideForTesting = 1
            session.setAudioInputChannel(trackID: trackID, channel: .stereo)
            _ = engineController.setAudioInputMonitorMode(trackID: trackID, mode: .input)
            _ = engineController.cancelAudioInputArm(trackID: trackID)
            _ = engineController.armAudioInput(trackID: trackID, pendingStartTick: 16)
        case "recording-away":
            _ = engineController.armAudioInput(trackID: trackID, pendingStartTick: 16)
            engineController.processTick(tickIndex: 16, now: ProcessInfo.processInfo.systemUptime)
            engineController.processTick(tickIndex: 18, now: ProcessInfo.processInfo.systemUptime)
            publishAudioInputBuffers(
                trackID: trackID,
                engineController: engineController,
                amplitudes: audioInputFixtureBuckets()
            )
            let nonInputTrackID = ensureSelectedNonInputTrack(session: session)
            session.setSelectedTrackID(nonInputTrackID)
            section.wrappedValue = .tracks
        default:
            break
        }
    }

    private static func ensureSelectedAudioInputTrack(
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) -> UUID {
        if session.store.selectedTrack.trackType == .audioInput {
            section.wrappedValue = .track
            return session.store.selectedTrackID
        }

        if let existing = session.store.tracks.first(where: { $0.trackType == .audioInput }) {
            session.setSelectedTrackID(existing.id)
            section.wrappedValue = .track
            return existing.id
        }

        session.appendTrack(trackType: .audioInput)
        section.wrappedValue = .track
        return session.store.selectedTrackID
    }

    private static func shouldResetAudioInputFixtureTrack(for state: String?) -> Bool {
        switch state {
        case "recording", "completed", "playback", "loop-empty", "invalid-route", "recording-away":
            return true
        default:
            return false
        }
    }

    private static func replaceAudioInputFixtureTrack(
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) -> UUID {
        if let existingInputTrackID = session.store.tracks.first(where: { $0.trackType == .audioInput })?.id {
            if session.store.tracks.count <= 1 {
                session.appendTrack(trackType: .monoMelodic)
            }
            session.setSelectedTrackID(existingInputTrackID)
            session.removeSelectedTrack()
        }

        session.appendTrack(trackType: .audioInput)
        section.wrappedValue = .track
        return session.store.selectedTrackID
    }

    private static func ensureSelectedNonInputTrack(session: SequencerDocumentSession) -> UUID {
        if let existing = session.store.tracks.first(where: { $0.trackType != .audioInput }) {
            return existing.id
        }

        session.appendTrack(trackType: .monoMelodic)
        return session.store.selectedTrackID
    }

    private static func publishAudioInputBuffers(
        trackID: UUID,
        engineController: EngineController,
        amplitudes: [Float]
    ) {
        for amplitude in amplitudes {
            guard let buffer = makeAudioInputFixtureBuffer(amplitude: amplitude) else { continue }
            engineController.recordAudioInputBufferForTesting(trackID: trackID, buffer: buffer)
        }
        engineController.drainAudioInputCapturePublicationForTesting()
    }

    private static func makeAudioInputFixtureBuffer(amplitude: Float) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32)
        else { return nil }

        let clamped = min(max(amplitude, 0), 1)
        let right = min(1, clamped * 0.82 + 0.08)
        buffer.frameLength = 32
        for frame in 0..<Int(buffer.frameLength) {
            let polarity: Float = frame.isMultiple(of: 2) ? 1 : -1
            let taper = Float(frame + 1) / Float(buffer.frameLength)
            buffer.floatChannelData?[0][frame] = polarity * clamped * taper
            buffer.floatChannelData?[1][frame] = -polarity * right * (1 - (taper * 0.35))
        }
        return buffer
    }

    private static func audioInputFixtureBuckets() -> [Float] {
        (0..<64).map { index in
            let phase = Double(index) / 63.0
            let contour = 0.18 + (sin(phase * .pi * 5.0) + 1.0) * 0.32
            let transient = index.isMultiple(of: 9) ? 0.24 : 0
            return Float(min(0.94, contour + transient))
        }
    }
}
