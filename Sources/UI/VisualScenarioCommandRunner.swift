import AVFoundation
import Foundation
import SwiftUI

@MainActor
enum VisualScenarioCommandRunner {
    private static let commandFileEnvironmentKey = "SEQUENCER_AI_VISUAL_COMMAND_FILE"
    private static let commandFileDefaultsKey = "VisualScenarioCommandFile"
    private static var drumPartHeaderRenameVisualState = false
    private static var drumPartHeaderOpenKitOriginPartName: String?
    private static var drumPartHeaderOpenKitOriginGroupName: String?
    private static var drumKitMatrixVisualState = false
    private static var drumKitMatrixRoutingEditorVisualState = false
    private static var drumKitMatrixRenderedVisualState = false
    private static var drumKitMatrixRenderedRoutingEditorState = false
    private static var drumKitMatrixRenderedDisplayStepCount = 16
    private static var drumKitMatrixRenderedGroupName = "none"
    private static var drumKitMatrixRenderedMemberCount = 0
    private static var drumGroupRoutingEditorRenderedState = false
    private static var drumGroupRoutingEditorMode = "none"
    private static var drumGroupRoutingEditorCanApply = false
    private static var drumGroupRoutingEditorSharedDestinationKind = "none"
    private static var drumGroupRoutingEditorWarnings = "none"
    private static var drumGroupRoutingEditorValidationIssues = "none"
    private static var drumGroupRoutingEditorRowInheritance = "none"
    private static var drumGroupRoutingEditorNoteInputs = "none"
    private static var drumGroupRoutingEditorChannelInputs = "none"
    private static var drumKitMatrixGroupID: TrackGroupID?
    private static var drumKitMatrixOriginatingPartID: UUID?
    private static var drumKitMatrixDisplayStepCount = 16
    private static var isObservingRenderedMatrixState = false

    static func runIfConfigured(
        section: Binding<WorkspaceSection>,
        visualPhraseControlsOpenIndex: Binding<Int?>,
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
        observeRenderedMatrixState()

        while !Task.isCancelled {
            if let payload = try? String(contentsOf: commandURL), payload != lastPayload {
                lastPayload = payload
                apply(
                    command: parse(payload),
                    section: section,
                    visualPhraseControlsOpenIndex: visualPhraseControlsOpenIndex,
                    session: session,
                    engineController: engineController
                )
            }

            writeStatus(
                to: statusURL,
                section: section.wrappedValue,
                visualPhraseControlsOpenIndex: visualPhraseControlsOpenIndex.wrappedValue,
                session: session,
                engineController: engineController
            )
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func observeRenderedMatrixState() {
        guard !isObservingRenderedMatrixState else { return }
        isObservingRenderedMatrixState = true

        NotificationCenter.default.addObserver(
            forName: .drumKitMatrixRenderedVisualState,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            Task { @MainActor in
                drumKitMatrixRenderedVisualState = userInfo["visible"] as? Bool ?? false
                drumKitMatrixRenderedRoutingEditorState = userInfo["routingEditorVisible"] as? Bool ?? false
                drumKitMatrixRenderedDisplayStepCount = userInfo["displayStepCount"] as? Int ?? 16
                drumKitMatrixRenderedGroupName = userInfo["groupName"] as? String ?? "none"
                drumKitMatrixRenderedMemberCount = userInfo["memberCount"] as? Int ?? 0
            }
        }
        NotificationCenter.default.addObserver(
            forName: .drumGroupRoutingEditorRenderedVisualState,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            Task { @MainActor in
                drumGroupRoutingEditorRenderedState = userInfo["visible"] as? Bool ?? false
                drumGroupRoutingEditorMode = userInfo["mode"] as? String ?? "none"
                drumGroupRoutingEditorCanApply = userInfo["canApply"] as? Bool ?? false
                drumGroupRoutingEditorSharedDestinationKind = userInfo["sharedDestinationKind"] as? String ?? "none"
                drumGroupRoutingEditorWarnings = userInfo["warnings"] as? String ?? "none"
                drumGroupRoutingEditorValidationIssues = userInfo["validationIssues"] as? String ?? "none"
                drumGroupRoutingEditorRowInheritance = userInfo["rowInheritance"] as? String ?? "none"
                drumGroupRoutingEditorNoteInputs = userInfo["noteInputs"] as? String ?? "none"
                drumGroupRoutingEditorChannelInputs = userInfo["channelInputs"] as? String ?? "none"
            }
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
        visualPhraseControlsOpenIndex: Binding<Int?>,
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
        applyPhraseNavigationFixture(
            command: command,
            section: section,
            visualPhraseControlsOpenIndex: visualPhraseControlsOpenIndex,
            session: session,
            engineController: engineController
        )
        applyDrumPartHeaderFixture(command: command, section: section, session: session)
        applyDrumKitMatrixCommand(command: command, session: session)

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
        visualPhraseControlsOpenIndex: Int?,
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
        let phrases = session.store.phrases
        let currentPhraseName = engineController.currentPhraseID.flatMap { phraseID in
            phrases.first { $0.id == phraseID }?.name
        }
        let queuedPhraseName = engineController.queuedPhraseID.flatMap { phraseID in
            phrases.first { $0.id == phraseID }?.name
        }
        let selectedPattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        let activeFillPreviewTrack = session.trackFillPreviewState.activeTrackID.flatMap { activeTrackID in
            session.store.tracks.first { $0.id == activeTrackID }
        }
        let drumPartHeaderModel = DrumPartWorkspaceHeaderModel(
            selectedTrack: session.store.selectedTrack,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups
        )
        let drumKitMatrixModel = currentDrumKitMatrixModel(session: session)
        let status = """
        workspace=\(section.rawValue)
        transport=\(engineController.isRunning ? "play" : "stop")
        phraseCount=\(phrases.count)
        phraseNames=\(phrases.map(\.name).joined(separator: "|"))
        phraseControlsOpenIndex=\(visualPhraseControlsOpenIndex.map(String.init) ?? "none")
        currentPhraseName=\(currentPhraseName ?? "none")
        queuedPhraseName=\(queuedPhraseName ?? "none")
        phraseQueueEnabled=\(engineController.isRunning && !phrases.isEmpty)
        phraseNowEnabled=\(!phrases.isEmpty)
        masterGain=\(session.store.masterBus.masterOutputGain)
        firstTrackSendA=\(session.store.tracks.first?.mix.sendA ?? 0)
        firstTrackSendB=\(session.store.tracks.first?.mix.sendB ?? 0)
        trackCount=\(session.store.tracks.count)
        selectedTrackName=\(session.store.selectedTrack.name)
        selectedTrackType=\(session.store.selectedTrack.trackType.rawValue)
        selectedTrackGroupName=\(drumPartHeaderModel?.groupName ?? "none")
        drumPartHeaderVisible=\(drumPartHeaderModel != nil)
        drumPartHeaderCurrentPartName=\(drumPartHeaderModel?.currentPartName ?? "none")
        drumPartHeaderPosition=\(drumPartHeaderModel?.positionLabel ?? "none")
        drumPartHeaderPreviousEnabled=\(drumPartHeaderModel?.previousPartID != nil)
        drumPartHeaderNextEnabled=\(drumPartHeaderModel?.nextPartID != nil)
        drumPartHeaderMemberCount=\(drumPartHeaderModel?.memberCount ?? 0)
        drumPartHeaderRenameVisualState=\(drumPartHeaderRenameVisualState)
        drumPartHeaderOpenKitOriginPartName=\(drumPartHeaderOpenKitOriginPartName ?? "none")
        drumPartHeaderOpenKitOriginGroupName=\(drumPartHeaderOpenKitOriginGroupName ?? "none")
        drumKitMatrixVisible=\(drumKitMatrixVisualState)
        drumKitMatrixRoutingEditorVisible=\(drumKitMatrixRoutingEditorVisualState)
        drumKitMatrixRenderedVisible=\(drumKitMatrixRenderedVisualState)
        drumKitMatrixRenderedRoutingEditorVisible=\(drumKitMatrixRenderedRoutingEditorState)
        drumKitMatrixRenderedDisplayStepCount=\(drumKitMatrixRenderedDisplayStepCount)
        drumKitMatrixRenderedGroupName=\(drumKitMatrixRenderedGroupName)
        drumKitMatrixRenderedMemberCount=\(drumKitMatrixRenderedMemberCount)
        drumGroupRoutingEditorRenderedVisible=\(drumGroupRoutingEditorRenderedState)
        drumGroupRoutingEditorMode=\(drumGroupRoutingEditorMode)
        drumGroupRoutingEditorCanApply=\(drumGroupRoutingEditorCanApply)
        drumGroupRoutingEditorSharedDestinationKind=\(drumGroupRoutingEditorSharedDestinationKind)
        drumGroupRoutingEditorWarnings=\(drumGroupRoutingEditorWarnings)
        drumGroupRoutingEditorValidationIssues=\(drumGroupRoutingEditorValidationIssues)
        drumGroupRoutingEditorRowInheritance=\(drumGroupRoutingEditorRowInheritance)
        drumGroupRoutingEditorNoteInputs=\(drumGroupRoutingEditorNoteInputs)
        drumGroupRoutingEditorChannelInputs=\(drumGroupRoutingEditorChannelInputs)
        drumKitMatrixGroupName=\(drumKitMatrixModel?.groupName ?? "none")
        drumKitMatrixMemberCount=\(drumKitMatrixModel?.rows.count ?? 0)
        drumKitMatrixMemberNames=\(drumKitMatrixModel.map { $0.rows.map(\.partName).joined(separator: "|") } ?? "none")
        drumKitMatrixPatternBadges=\(drumKitMatrixModel.map { $0.rows.map(\.patternBadge).joined(separator: "|") } ?? "none")
        drumKitMatrixSourceModes=\(drumKitMatrixModel.map { $0.rows.map { $0.sourceMode.rawValue }.joined(separator: "|") } ?? "none")
        drumKitMatrixPreviewKinds=\(drumKitMatrixModel.map(matrixPreviewKinds) ?? "none")
        drumKitMatrixPreviewActiveCounts=\(drumKitMatrixModel.map(matrixPreviewActiveCounts) ?? "none")
        drumKitMatrixPatternMismatch=\(drumKitMatrixModel?.hasPatternMismatch ?? false)
        drumKitMatrixStaleMemberCount=\(drumKitMatrixModel?.staleMemberCount ?? 0)
        drumKitMatrixDisplayStepCount=\(drumKitMatrixModel?.displayStepCount ?? drumKitMatrixDisplayStepCount)
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

    private static func currentDrumKitMatrixModel(session: SequencerDocumentSession) -> DrumKitMatrixModel? {
        guard drumKitMatrixVisualState,
              let groupID = drumKitMatrixGroupID,
              let originatingPartID = drumKitMatrixOriginatingPartID
        else {
            return nil
        }

        return DrumKitMatrixModel(
            groupID: groupID,
            originatingPartID: originatingPartID,
            displayStepCount: drumKitMatrixDisplayStepCount,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups,
            layers: session.store.layers,
            selectedPhrase: session.store.selectedPhrase,
            patternBanks: Array(session.store.patternBanksByTrackID.values),
            clipPool: session.store.clipPool,
            generatorPool: session.store.generatorPool
        )
    }

    private static func matrixPreviewKinds(_ model: DrumKitMatrixModel) -> String {
        model.rows.map { row in
            switch row.preview {
            case let .steps(steps, _, overflow):
                return "steps\(steps.count)\(overflow ? "+" : "")"
            case let .limited(badge, _):
                return badge
            }
        }
        .joined(separator: "|")
    }

    private static func matrixPreviewActiveCounts(_ model: DrumKitMatrixModel) -> String {
        model.rows.map { row in
            switch row.preview {
            case let .steps(steps, _, _):
                return "\(steps.filter { $0 }.count)"
            case .limited:
                return "NA"
            }
        }
        .joined(separator: "|")
    }

    private static func applyDrumKitMatrixCommand(
        command: [String: String],
        session: SequencerDocumentSession
    ) {
        guard let rawCommand = command["drumKitMatrixCommand"] else { return }

        switch rawCommand {
        case "display16", "display-16":
            drumKitMatrixDisplayStepCount = 16
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "display-16")
        case "display32", "display-32":
            drumKitMatrixDisplayStepCount = 32
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "display-32")
        case "openRouting", "open-routing":
            drumKitMatrixRoutingEditorVisualState = true
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "open-routing")
        case "closeRouting", "close-routing":
            drumKitMatrixRoutingEditorVisualState = false
            drumGroupRoutingEditorRenderedState = false
            drumGroupRoutingEditorMode = "none"
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-routing")
        case "back":
            drumKitMatrixVisualState = false
            drumKitMatrixRoutingEditorVisualState = false
            drumGroupRoutingEditorRenderedState = false
            drumGroupRoutingEditorMode = "none"
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "back")
        default:
            if rawCommand.hasPrefix("selectIndex:"),
               let rawIndex = rawCommand.split(separator: ":").last,
               let selectedIndex = Int(rawIndex) {
                drumKitMatrixVisualState = false
                drumKitMatrixRoutingEditorVisualState = false
                drumGroupRoutingEditorRenderedState = false
                drumGroupRoutingEditorMode = "none"
                NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "select-index:\(selectedIndex)")
            }
        }

        if let mutation = command["drumKitMatrixMutation"] {
            applyDrumKitMatrixMutation(mutation, session: session)
        }
        if let routingState = command["drumGroupRoutingEditorState"] {
            NotificationCenter.default.post(
                name: .drumGroupRoutingEditorVisualCommand,
                object: "routing-\(routingState)"
            )
        }
    }

    private static func applyDrumPartHeaderFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["drumPartHeaderFixture"] != nil ||
              command["drumPartHeaderSelectedIndex"] != nil ||
              command["drumPartHeaderRename"] != nil ||
              command["drumPartHeaderOpenKitView"] != nil ||
              command["drumKitMatrixFixture"] != nil
        else { return }

        section.wrappedValue = .track
        drumPartHeaderOpenKitOriginPartName = nil
        drumPartHeaderOpenKitOriginGroupName = nil
        drumKitMatrixVisualState = false
        drumKitMatrixRoutingEditorVisualState = false
        drumKitMatrixGroupID = nil
        drumKitMatrixOriginatingPartID = nil

        switch command["drumPartHeaderFixture"] {
        case "kit", "group", "drumGroup":
            let group = ensureDrumPartHeaderFixtureGroup(session: session)
            let requestedIndex = Int(command["drumPartHeaderSelectedIndex"] ?? "") ?? 2
            selectDrumPartHeaderMember(in: group, requestedIndex: requestedIndex, session: session)
        case "generator", "generatorReadOnly", "readOnly":
            let group = ensureDrumPartHeaderFixtureGroup(session: session)
            let requestedIndex = Int(command["drumPartHeaderSelectedIndex"] ?? "") ?? 2
            if let selectedPartID = selectDrumPartHeaderMember(in: group, requestedIndex: requestedIndex, session: session) {
                ensureGeneratorSource(trackID: selectedPartID, session: session)
            }
        case "oneMember", "single":
            let group = ensureOneMemberDrumPartHeaderFixtureGroup(session: session)
            selectDrumPartHeaderMember(in: group, requestedIndex: 0, session: session)
        case "longNames", "longName":
            let group = ensureLongNameDrumPartHeaderFixtureGroup(session: session)
            let requestedIndex = Int(command["drumPartHeaderSelectedIndex"] ?? "") ?? 0
            selectDrumPartHeaderMember(in: group, requestedIndex: requestedIndex, session: session)
        case "staleGroup", "stale", "unresolved":
            let selectedID = ensureStaleDrumPartHeaderFixture(session: session)
            session.setSelectedTrackID(selectedID)
        case "nonKit", "fallback":
            if let nonKitTrack = session.store.tracks.first(where: { $0.groupID == nil }) {
                session.setSelectedTrackID(nonKitTrack.id)
            } else {
                session.appendTrack(trackType: .monoMelodic)
            }
        default:
            break
        }

        if let matrixFixture = command["drumKitMatrixFixture"],
           let groupID = session.store.selectedTrack.groupID {
            applyDrumKitMatrixFixture(matrixFixture, groupID: groupID, session: session)
        }

        switch command["drumPartHeaderRename"] {
        case "on", "true", "editing":
            drumPartHeaderRenameVisualState = true
            NotificationCenter.default.post(name: .drumPartWorkspaceHeaderVisualCommand, object: "rename-on")
        case "off", "false", "clear":
            drumPartHeaderRenameVisualState = false
            NotificationCenter.default.post(name: .drumPartWorkspaceHeaderVisualCommand, object: "rename-off")
        default:
            break
        }

        if command["drumPartHeaderOpenKitView"] == "true" {
            let model = DrumPartWorkspaceHeaderModel(
                selectedTrack: session.store.selectedTrack,
                tracks: session.store.tracks,
                trackGroups: session.store.trackGroups
            )
            drumPartHeaderOpenKitOriginPartName = model?.currentPartName
            drumPartHeaderOpenKitOriginGroupName = model?.groupName
            drumKitMatrixVisualState = model != nil
            drumKitMatrixRenderedVisualState = false
            drumKitMatrixRenderedRoutingEditorState = false
            drumKitMatrixRenderedGroupName = "none"
            drumKitMatrixRenderedMemberCount = 0
            drumKitMatrixRoutingEditorVisualState = false
            drumKitMatrixGroupID = model?.groupID
            drumKitMatrixOriginatingPartID = model?.currentPartID
            drumKitMatrixDisplayStepCount = Int(command["drumKitMatrixDisplayStepCount"] ?? "") == 32 ? 32 : 16
            postOpenKitViewVisualCommand()

            NotificationCenter.default.post(
                name: .drumKitMatrixVisualCommand,
                object: drumKitMatrixDisplayStepCount == 32 ? "display-32" : "display-16"
            )
            if let mutation = command["drumKitMatrixMutation"] {
                applyDrumKitMatrixMutation(mutation, session: session)
            }
        }
    }

    private static func postOpenKitViewVisualCommand() {
        NotificationCenter.default.post(name: .drumPartWorkspaceHeaderVisualCommand, object: "open-kit-view")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            NotificationCenter.default.post(name: .drumPartWorkspaceHeaderVisualCommand, object: "open-kit-view")
            try? await Task.sleep(nanoseconds: 350_000_000)
            NotificationCenter.default.post(name: .drumPartWorkspaceHeaderVisualCommand, object: "open-kit-view")
        }
    }

    @discardableResult
    private static func selectDrumPartHeaderMember(
        in group: TrackGroup,
        requestedIndex: Int,
        session: SequencerDocumentSession
    ) -> UUID? {
        let resolvedMemberIDs = group.memberIDs.filter { memberID in
            session.store.tracks.contains(where: { $0.id == memberID })
        }
        guard !resolvedMemberIDs.isEmpty else {
            return nil
        }

        let clampedIndex = min(max(0, requestedIndex), resolvedMemberIDs.count - 1)
        let selectedID = resolvedMemberIDs[clampedIndex]
        session.setSelectedTrackID(selectedID)
        return selectedID
    }

    private static func ensureGeneratorSource(trackID: UUID, session: SequencerDocumentSession) {
        let selectedPattern = session.store.selectedPattern(for: trackID)
        if selectedPattern.sourceRef.mode == .generator,
           session.store.generatorEntry(id: selectedPattern.sourceRef.generatorID) != nil {
            return
        }

        session.batch(impact: .snapshotOnly, changed: .patternBank(trackID)) { store in
            var project = store.exportToProject()
            _ = project.createBlankGeneratorSource(trackID: trackID, slotIndex: 0)
            for generator in project.generatorPool where !store.generatorPool.contains(where: { $0.id == generator.id }) {
                store.appendGenerator(generator)
            }
            guard let bank = project.patternBanks.first(where: { $0.trackID == trackID }) else {
                return
            }
            store.setPatternBank(trackID: trackID, bank: bank)
        }
    }

    private static func applyDrumKitMatrixFixture(
        _ fixture: String,
        groupID: TrackGroupID,
        session: SequencerDocumentSession
    ) {
        switch fixture {
        case "mixedPatterns", "mixed":
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                var project = store.exportToProject()
                guard let group = project.trackGroups.first(where: { $0.id == groupID }),
                      let phraseIndex = project.phrases.firstIndex(where: { $0.id == project.selectedPhraseID })
                else { return }

                let resolvedMemberIDs = group.memberIDs.filter { memberID in
                    project.tracks.contains(where: { $0.id == memberID })
                }
                for (index, memberID) in resolvedMemberIDs.enumerated() {
                    project.phrases[phraseIndex].setPatternIndex(index == 1 ? 1 : 0, for: memberID, layers: project.layers)
                }
                store.importFromProject(project)
            }
        case "generatorAndReadOnly", "readOnly":
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                var project = store.exportToProject()
                guard let group = project.trackGroups.first(where: { $0.id == groupID }),
                      let phraseIndex = project.phrases.firstIndex(where: { $0.id == project.selectedPhraseID })
                else { return }

                let resolvedMemberIDs = group.memberIDs.filter { memberID in
                    project.tracks.contains(where: { $0.id == memberID })
                }
                if let readOnlyTrackID = resolvedMemberIDs.dropFirst().first {
                    let readOnlyClip = ClipPoolEntry(
                        id: UUID(),
                        name: "Matrix Read Only Slice",
                        trackType: .monoMelodic,
                        content: .sliceTriggers(
                            stepPattern: [true, false, false, false],
                            sliceIndexes: [0, 0, 0, 0],
                            stepModes: [.single, .single, .single, .single],
                            stepParameters: [.default, .default, .default, .default]
                        )
                    )
                    project.clipPool.append(readOnlyClip)
                    project.setPatternSourceRef(.clip(readOnlyClip.id), for: readOnlyTrackID, slotIndex: 0)
                    project.phrases[phraseIndex].setPatternIndex(0, for: readOnlyTrackID, layers: project.layers)
                }
                if let generatorTrackID = resolvedMemberIDs.dropFirst(2).first {
                    _ = project.createBlankGeneratorSource(trackID: generatorTrackID, slotIndex: 0)
                    project.phrases[phraseIndex].setPatternIndex(0, for: generatorTrackID, layers: project.layers)
                }
                store.importFromProject(project)
            }
        default:
            break
        }
    }

    private static func applyDrumKitMatrixMutation(_ mutation: String, session: SequencerDocumentSession) {
        guard let groupID = drumKitMatrixGroupID else { return }

        switch mutation {
        case "zeroMembers", "zero":
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                var project = store.exportToProject()
                guard let groupIndex = project.trackGroups.firstIndex(where: { $0.id == groupID }) else { return }
                project.trackGroups[groupIndex].memberIDs = []
                store.importFromProject(project)
            }
        case "staleMember", "stale":
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                var project = store.exportToProject()
                guard let groupIndex = project.trackGroups.firstIndex(where: { $0.id == groupID }) else { return }
                let resolvedMemberIDs = project.trackGroups[groupIndex].memberIDs.filter { memberID in
                    project.tracks.contains(where: { $0.id == memberID })
                }
                project.trackGroups[groupIndex].memberIDs = Array(resolvedMemberIDs.prefix(2)) + [UUID()]
                store.importFromProject(project)
            }
        default:
            break
        }
    }

    private static func ensureDrumPartHeaderFixtureGroup(session: SequencerDocumentSession) -> TrackGroup {
        if let existing = session.store.trackGroups.first(where: { $0.name == "808 Bones" }),
           existing.memberIDs.count >= 6 {
            ensureVisibleDrumKitMatrixSeeds(groupID: existing.id, session: session)
            return existing
        }

        let seedPatterns = visibleDrumKitMatrixSeedPatterns()
        let plan = DrumGroupPlan(
            name: "808 Bones",
            color: "#C06030",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick", seedPattern: seedPatterns[0]),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare", seedPattern: seedPatterns[1]),
                DrumGroupPlan.Member(tag: "clap", trackName: "Clap", seedPattern: seedPatterns[2]),
                DrumGroupPlan.Member(tag: "hat-closed", trackName: "Closed Hat", seedPattern: seedPatterns[3]),
                DrumGroupPlan.Member(tag: "hat-open", trackName: "Open Hat", seedPattern: seedPatterns[4]),
                DrumGroupPlan.Member(tag: "rim", trackName: "Rim Shot", seedPattern: seedPatterns[5]),
            ],
            prepopulateClips: true,
            sharedDestination: nil
        )
        _ = session.addDrumGroup(plan: plan)
        return session.store.trackGroups.first(where: { $0.name == "808 Bones" && $0.memberIDs.count >= 6 })
            ?? session.store.trackGroups.last
            ?? TrackGroup(name: "808 Bones", color: "#C06030")
    }

    private static func visibleDrumKitMatrixSeedPatterns() -> [[Bool]] {
        [
            (0..<32).map { [0, 8, 16, 24, 30].contains($0) },
            (0..<32).map { [4, 12, 20, 28].contains($0) },
            (0..<32).map { [6, 14, 22, 30].contains($0) },
            (0..<32).map { $0.isMultiple(of: 2) },
            (0..<32).map { [3, 11, 19, 27].contains($0) },
            (0..<32).map { [2, 10, 18, 26].contains($0) },
        ]
    }

    private static func ensureVisibleDrumKitMatrixSeeds(groupID: TrackGroupID, session: SequencerDocumentSession) {
        let seedPatterns = visibleDrumKitMatrixSeedPatterns()
        session.batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            guard let group = project.trackGroups.first(where: { $0.id == groupID }) else { return }
            let resolvedMemberIDs = group.memberIDs.filter { memberID in
                project.tracks.contains(where: { $0.id == memberID })
            }

            for (index, memberID) in resolvedMemberIDs.prefix(seedPatterns.count).enumerated() {
                let seedPattern = seedPatterns[index]
                if let trackIndex = project.tracks.firstIndex(where: { $0.id == memberID }) {
                    project.tracks[trackIndex].stepPattern = seedPattern
                }

                let clipID = project.patternBanks
                    .first(where: { $0.trackID == memberID })?
                    .slot(at: 0)
                    .sourceRef
                    .clipID
                if let clipID,
                   let clipIndex = project.clipPool.firstIndex(where: { $0.id == clipID }) {
                    project.clipPool[clipIndex].content = .stepSequence(
                        stepPattern: seedPattern,
                        pitches: [DrumKitNoteMap.baselineNote]
                    )
                } else {
                    let clip = ClipPoolEntry(
                        id: UUID(),
                        name: "\(project.tracks.first(where: { $0.id == memberID })?.name ?? "Kit Part") Matrix Seed",
                        trackType: .monoMelodic,
                        content: .stepSequence(
                            stepPattern: seedPattern,
                            pitches: [DrumKitNoteMap.baselineNote]
                        )
                    )
                    project.clipPool.append(clip)
                    project.setPatternSourceRef(.clip(clip.id), for: memberID, slotIndex: 0)
                }
            }

            store.importFromProject(project)
        }
    }

    private static func ensureOneMemberDrumPartHeaderFixtureGroup(session: SequencerDocumentSession) -> TrackGroup {
        let groupName = "Solo Knock"
        if let existing = session.store.trackGroups.first(where: { $0.name == groupName }),
           existing.memberIDs.count == 1 {
            return existing
        }

        let seedPattern = Array(repeating: false, count: 16)
        let plan = DrumGroupPlan(
            name: groupName,
            color: "#3A8F7A",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick", seedPattern: seedPattern),
            ],
            prepopulateClips: false,
            sharedDestination: nil
        )
        _ = session.addDrumGroup(plan: plan)
        return session.store.trackGroups.first(where: { $0.name == groupName })
            ?? session.store.trackGroups.last
            ?? TrackGroup(name: groupName, color: "#3A8F7A")
    }

    private static func ensureLongNameDrumPartHeaderFixtureGroup(session: SequencerDocumentSession) -> TrackGroup {
        let groupName = "Warehouse Breakbeat Kit With Extremely Long Saved Name"
        if let existing = session.store.trackGroups.first(where: { $0.name == groupName }),
           !existing.memberIDs.isEmpty {
            return existing
        }

        let seedPattern = Array(repeating: false, count: 16)
        let plan = DrumGroupPlan(
            name: groupName,
            color: "#5A7FD6",
            members: [
                DrumGroupPlan.Member(
                    tag: "hat-closed",
                    trackName: "Generator Driven Closed Hat With A Very Long Performance Name",
                    seedPattern: seedPattern
                ),
                DrumGroupPlan.Member(
                    tag: "rim",
                    trackName: "Rim Shot With Long Alternate Layer Name",
                    seedPattern: seedPattern
                ),
            ],
            prepopulateClips: false,
            sharedDestination: nil
        )
        _ = session.addDrumGroup(plan: plan)
        return session.store.trackGroups.first(where: { $0.name == groupName })
            ?? session.store.trackGroups.last
            ?? TrackGroup(name: groupName, color: "#5A7FD6")
    }

    private static func ensureStaleDrumPartHeaderFixture(session: SequencerDocumentSession) -> UUID {
        let staleGroupID = TrackGroupID()
        let trackID = UUID()
        let staleTrack = StepSequenceTrack(
            id: trackID,
            name: "Unresolved Kit Part",
            trackType: .monoMelodic,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: Array(repeating: false, count: 16),
            groupID: staleGroupID,
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
        let staleClip = ClipPoolEntry(
            id: UUID(),
            name: "Unresolved Kit Part",
            trackType: .monoMelodic,
            content: .stepSequence(
                stepPattern: Array(repeating: false, count: 16),
                pitches: [DrumKitNoteMap.baselineNote]
            )
        )
        let staleBank = TrackPatternBank.default(for: staleTrack, initialClipID: staleClip.id)

        session.batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            let removedTrackIDs = Set(project.tracks.filter { $0.name == staleTrack.name }.map(\.id))
            project.tracks.removeAll { $0.name == staleTrack.name }
            project.patternBanks.removeAll { removedTrackIDs.contains($0.trackID) || $0.trackID == staleTrack.id }
            project.clipPool.removeAll { $0.name == staleClip.name }
            project.tracks.append(staleTrack)
            project.clipPool.append(staleClip)
            project.patternBanks.append(staleBank)
            project.trackGroups.removeAll { $0.id == staleGroupID || $0.name == "Unresolved Kit" }
            project.trackGroups.append(
                TrackGroup(
                    id: UUID(),
                    name: "Unresolved Kit",
                    color: "#777777",
                    memberIDs: [staleTrack.id]
                )
            )
            project.selectedTrackID = staleTrack.id
            project.syncPhrasesWithTracks()
            store.importFromProject(project)
        }

        return trackID
    }

    private static func applyPhraseNavigationFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        visualPhraseControlsOpenIndex: Binding<Int?>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        if command["phraseFixture"] == "empty" {
            if engineController.isRunning {
                engineController.stop()
            }
            let emptySelection = UUID(uuidString: "00000000-0000-4000-8000-000000000911") ?? UUID()
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                store.replacePhrases([], selectedPhraseID: emptySelection)
            }
        }

        switch command["phrasePicker"] {
        case "open":
            NotificationCenter.default.post(name: .transportPhraseNavigationVisualCommand, object: "open")
        case "close":
            NotificationCenter.default.post(name: .transportPhraseNavigationVisualCommand, object: "close")
        default:
            break
        }

        if let action = command["phraseAction"] {
            NotificationCenter.default.post(name: .transportPhraseNavigationVisualCommand, object: action)
        }

        if let queueIndex = Int(command["phraseQueueIndex"] ?? ""),
           let phraseID = phraseID(at: queueIndex, session: session) {
            _ = session.queuePhrase(phraseID)
        }

        if let nowIndex = Int(command["phraseNowIndex"] ?? ""),
           let phraseID = phraseID(at: nowIndex, session: session) {
            _ = session.switchPhraseNow(phraseID)
        }

        switch command["phraseControlsOpenIndex"] {
        case "none", "close":
            visualPhraseControlsOpenIndex.wrappedValue = nil
        case let rawIndex?:
            if let index = Int(rawIndex) {
                section.wrappedValue = .phrase
                visualPhraseControlsOpenIndex.wrappedValue = index
            }
        default:
            break
        }
    }

    private static func phraseID(at index: Int, session: SequencerDocumentSession) -> UUID? {
        let phrases = session.store.phrases
        guard phrases.indices.contains(index) else { return nil }
        return phrases[index].id
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
