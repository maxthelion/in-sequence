import AVFoundation
import AppKit
import Foundation
import SwiftUI

@MainActor
enum VisualScenarioCommandRunner {
    private static let commandFileEnvironmentKey = "SEQUENCER_AI_VISUAL_COMMAND_FILE"
    private static let commandFileDefaultsKey = "VisualScenarioCommandFile"
    private static var drumPartHeaderRenameVisualState = false
    // Slice 6a "kit view first": a drum-group track now lands on the kit matrix
    // by default; the per-part editor is the dive-in. This flag records whether
    // a fixture has dived into the part editor, so the harness reflects which of
    // the two views the drum track is actually showing.
    private static var drumPartHeaderDivedIn = false
    private static var drumPartHeaderOpenKitOriginPartName: String?
    private static var drumPartHeaderOpenKitOriginGroupName: String?
    private static var drumKitMatrixVisualState = false
    private static var drumKitMatrixRoutingEditorVisualState = false
    private static var drumKitMatrixRenderedVisualState = false
    private static var drumKitMatrixRenderedRoutingEditorState = false
    private static var drumKitMatrixRenderedTemplateChooserState = false
    private static var drumKitMatrixRenderedDisplayStepCount = 16
    private static var drumKitMatrixRenderedLayer = "none"
    private static var drumKitMatrixRenderedGroupPatternSlot = "none"
    private static var drumKitMatrixRenderedGroupName = "none"
    private static var drumKitMatrixRenderedMemberCount = 0
    private static var phraseMatrixRenderedVisible = false
    private static var phraseMatrixPageIndex = 0
    private static var phraseMatrixPageCount = 0
    private static var phraseMatrixTrackCount = 0
    private static var phraseMatrixPreviousEnabled = false
    private static var phraseMatrixNextEnabled = false
    private static var phraseMatrixPreviousOccupancy = 0
    private static var phraseMatrixNextOccupancy = 0
    private static var phraseMatrixSelectedLayerID = "none"
    private static var phraseMatrixSelectedLayerName = "none"
    private static var phraseMatrixSelectorWidth: CGFloat = 0
    private static var phraseMatrixTrackGridWidth: CGFloat = 0
    private static var phrasePerformLayerMode = TrackPerformLayerMode.pattern.rawValue
    private static var phrasePerformLayerSelectorVisible = false
    private static var phrasePerformLayerVariant = "none"
    private static var phraseWorkspaceTab = "layers"
    private static var phraseCellTool = "value"
    private static var phraseGlobalApplyTrackSelectorVisible = false
    private static var phraseCaptureVisible = false
    private static var stepOrderFixtureState = "none"
    private static var trackSourceTabState = "none"
    private static var sceneEditorFixtureState = "none"
    private static var libraryCategoryState = "none"
    private static var libraryFixtureState = "none"
    private static var slicerFixtureState = "none"
    private static var slicerLayerState = SliceTrackClipLayer.steps.rawValue
    private static var slicerTabState = "source"
    private static var audioInputTabState = "source"
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

    /// True when a command file is configured — i.e. the app is being driven
    /// by the deterministic capture harness. UI must not trigger system
    /// permission dialogs in this mode.
    static var isConfigured: Bool {
        let configuredPath = ProcessInfo.processInfo.environment[commandFileEnvironmentKey]
            ?? UserDefaults.standard.string(forKey: commandFileDefaultsKey)
        guard let rawPath = configuredPath else { return false }
        return !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func runIfConfigured(
        section: Binding<WorkspaceSection>,
        visualPhraseControlsOpenIndex: Binding<Int?>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) async {
        // The command-file path is exported via `launchctl setenv` (global),
        // so XCTest host apps spawning during a capture run inherit it and
        // would race the driven instance over the command/status protocol.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let configuredPath = ProcessInfo.processInfo.environment[commandFileEnvironmentKey]
            ?? UserDefaults.standard.string(forKey: commandFileDefaultsKey)
        guard let rawPath = configuredPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        NSLog("[VisualScenarioCommandRunner] watching command file %@", rawPath)

        let commandURL = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        let statusURL = commandURL.appendingPathExtension("status")
        var lastPayload = ""
        // Harness runs must be fully unattended: never touch the live input
        // node. macOS re-prompts for mic access at IO time when the ad-hoc
        // code signature changed since the grant, even if the authorization
        // status API still reports .authorized — so a status-based gate
        // cannot prevent a blocking dialog. Simulated input connections give
        // the fixtures everything they display.
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        observeRenderedMatrixState()

        while !Task.isCancelled {
            if let payload = try? String(contentsOf: commandURL), payload != lastPayload {
                lastPayload = payload
                DevActivity.trace(DevActivity.harness, "apply command: \(payload.replacingOccurrences(of: "\n", with: "; "))")
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
                drumKitMatrixRenderedTemplateChooserState = userInfo["templateChooserVisible"] as? Bool ?? false
                drumKitMatrixRenderedDisplayStepCount = userInfo["displayStepCount"] as? Int ?? 16
                drumKitMatrixRenderedLayer = userInfo["layer"] as? String ?? "none"
                drumKitMatrixRenderedGroupPatternSlot = userInfo["groupPatternSlot"] as? String ?? "none"
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
        NotificationCenter.default.addObserver(
            forName: .phraseMatrixRenderedVisualState,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            Task { @MainActor in
                phraseMatrixRenderedVisible = userInfo["visible"] as? Bool ?? false
                phraseMatrixPageIndex = userInfo["pageIndex"] as? Int ?? 0
                phraseMatrixPageCount = userInfo["pageCount"] as? Int ?? 0
                phraseMatrixTrackCount = userInfo["trackCount"] as? Int ?? 0
                phraseMatrixPreviousEnabled = userInfo["previousEnabled"] as? Bool ?? false
                phraseMatrixNextEnabled = userInfo["nextEnabled"] as? Bool ?? false
                phraseMatrixPreviousOccupancy = userInfo["previousOccupancy"] as? Int ?? 0
                phraseMatrixNextOccupancy = userInfo["nextOccupancy"] as? Int ?? 0
                phraseMatrixSelectedLayerID = userInfo["selectedLayerID"] as? String ?? "none"
                phraseMatrixSelectedLayerName = userInfo["selectedLayerName"] as? String ?? "none"
                phraseMatrixSelectorWidth = userInfo["selectorWidth"] as? CGFloat ?? 0
                phraseMatrixTrackGridWidth = userInfo["trackGridWidth"] as? CGFloat ?? 0
                phrasePerformLayerMode = userInfo["performLayerMode"] as? String ?? TrackPerformLayerMode.pattern.rawValue
                phrasePerformLayerSelectorVisible = userInfo["performLayerSelectorVisible"] as? Bool ?? false
                phrasePerformLayerVariant = userInfo["performLayerVariant"] as? String ?? "none"
                phraseWorkspaceTab = userInfo["workspaceTab"] as? String ?? "layers"
                phraseCellTool = userInfo["cellTool"] as? String ?? "value"
                phraseGlobalApplyTrackSelectorVisible = userInfo["globalApplyTrackSelectorVisible"] as? Bool ?? false
                phraseCaptureVisible = userInfo["captureVisible"] as? Bool ?? false
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

    /// Internal (not private) so command-protocol tests can drive it directly.
    static func apply(
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

        // Legacy tracks-page command: sets the GLOBAL workspace mode
        // (edit ≙ setup, perform ≙ perform) and navigates to the tracks
        // page, preserving the old command's observable behaviour.
        if let requestedTracksMode = command["tracksMode"],
           let mode = TracksWorkspaceMode(rawValue: requestedTracksMode) {
            session.workspaceMode = WorkspaceMode(tracksMode: mode)
            section.wrappedValue = .tracks
        }

        // The global mode's own command (no navigation side effect). Applied
        // after the legacy keys so it wins when both appear in one payload.
        if let requestedWorkspaceMode = command["workspaceMode"],
           let mode = WorkspaceMode(rawValue: requestedWorkspaceMode) {
            session.workspaceMode = mode
        }

        // Quantised perform toggles (slice 2): drive the session Q setting.
        if let requestedQuantise = command["quantise"],
           let quantise = PerformQuantise(rawValue: requestedQuantise) {
            session.performQuantise = quantise
        }

        // Scoped Track Perform (AC22): enter the reused tracks-perform surface
        // scoped to a single track. `selected` scopes the currently selected
        // track; a UUID scopes that explicit track.
        if let rawTrack = command["performScopeTrack"] {
            let trackID = rawTrack == "selected"
                ? session.store.selectedTrackID
                : UUID(uuidString: rawTrack)
            if let trackID, session.store.tracks.contains(where: { $0.id == trackID }) {
                session.enterScopedPerform(trackIDs: [trackID])
                section.wrappedValue = .tracks
            }
        }

        // Scoped Kit Perform (AC22): enter the reused tracks-perform surface
        // scoped to a drum group's member tracks. `selected` resolves the group
        // of the currently selected track; a UUID scopes that explicit group.
        if let rawGroup = command["performScopeKit"] {
            let groupID: TrackGroupID? = rawGroup == "selected"
                ? session.store.tracks.first(where: { $0.id == session.store.selectedTrackID })?.groupID
                : UUID(uuidString: rawGroup)
            if let groupID {
                let memberIDs = session.store.tracksInGroup(groupID).map(\.id)
                if !memberIDs.isEmpty {
                    session.enterScopedPerform(trackIDs: memberIDs)
                    section.wrappedValue = .tracks
                }
            }
        }

        // Clear any scoped perform back to the whole project (AC22).
        if command["clearPerformScope"] == "true" {
            session.performTrackScope = []
        }

        if let rawWindowFrame = command["windowFrame"] {
            applyWindowFrame(rawWindowFrame)
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
        applyStepOrderFixture(command: command, section: section, session: session, engineController: engineController)
        applyPhraseMatrixFixture(command: command, section: section, session: session)
        applyPhrasePerformOverlayFixture(command: command, section: section, session: session)
        applyTrackPerformLayerMatrixFixture(command: command, section: section, session: session)
        applyNoteRepeatPerformFixture(command: command, section: section, session: session)
        applyDrumPartHeaderFixture(command: command, section: section, session: session)
        applyDrumKitMatrixCommand(command: command, session: session)
        applyTrackSourceTabCommand(command: command, section: section)
        applySlicerFixture(command: command, section: section, session: session)
        applyScenesModeCommand(command: command, section: section, session: session)
        applyLibraryCommand(command: command, section: section, session: session)
        applyWorkspaceScrollCommand(command: command)

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

    private static func selectedSlicerStatus(
        session: SequencerDocumentSession
    ) -> (sampleName: String, sliceCount: Int, clipStepCount: Int, activeStepCount: Int) {
        let trackID = session.store.selectedTrackID
        let selectedPattern = session.store.selectedPattern(for: trackID)
        let clip = selectedPattern.sourceRef.clipID.flatMap { session.store.clipEntry(id: $0) }
        let clipContent = clip?.content.normalized
        let activeStepCount: Int
        if case let .sliceTriggers(stepPattern, _, _, _) = clipContent {
            activeStepCount = stepPattern.filter { $0 }.count
        } else {
            activeStepCount = 0
        }

        guard session.store.selectedTrack.trackType == .slice,
              case let .slicer(sliceSetID, _) = session.store.resolvedDestination(for: trackID),
              let sliceSet = session.store.sliceSet(id: sliceSetID)
        else {
            return ("none", 0, clipContent?.stepCount ?? 0, activeStepCount)
        }

        let sampleName = sliceSet.sampleID
            .flatMap { AudioSampleLibrary.shared.sample(id: $0)?.name }
            ?? "none"
        return (sampleName, sliceSet.userSliceCount, clipContent?.stepCount ?? 0, activeStepCount)
    }

    /// Armed quantised changes as `<track>:<change>` pairs in arm order
    /// (e.g. `Drums:mute-on,Bass:fill-cue`), `none` when nothing is armed.
    /// Internal (not private) so command-protocol tests can pin the format.
    static func quantisePendingStatus(
        session: SequencerDocumentSession,
        engineController: EngineController
    ) -> String {
        let trackNamesByID = Dictionary(
            uniqueKeysWithValues: session.store.tracks.map { ($0.id, $0.name) }
        )
        let entries = engineController.quantisedPendingChanges.map { change -> String in
            let trackName = trackNamesByID[change.trackID] ?? change.trackID.uuidString
            switch change {
            case let .mute(_, muted, _):
                return "\(trackName):\(muted ? "mute-on" : "mute-off")"
            case let .lengthLimitedMute(_, muted, _, lengthBars, _):
                return "\(trackName):\(muted ? "mute-on" : "mute-off")-\(lengthBars)b"
            case let .fillFlag(_, enabled, _, lengthBars, _):
                let suffix = lengthBars.map { "-\($0)b" } ?? ""
                return "\(trackName):\(enabled ? "fill-on" : "fill-off")\(suffix)"
            case let .pattern(_, slotIndex, _, lengthBars, _):
                let suffix = lengthBars.map { "-\($0)b" } ?? ""
                return "\(trackName):pattern-p\(slotIndex + 1)\(suffix)"
            case .fillCue:
                return "\(trackName):fill-cue"
            }
        }
        return entries.isEmpty ? "none" : entries.joined(separator: ",")
    }

    /// Tracks whose cued fill bar is playing, in track order; `none` if idle.
    static func quantiseFillCueActiveStatus(
        session: SequencerDocumentSession,
        engineController: EngineController
    ) -> String {
        let activeTrackIDs = engineController.quantisedFillCueActiveTrackIDs
        let names = session.store.tracks
            .filter { activeTrackIDs.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    /// Internal (not private) so command-protocol tests can drive it directly.
    static func writeStatus(
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
        let stepOrderStatus = currentStepOrderStatus(
            phrases: phrases,
            visualPhraseControlsOpenIndex: visualPhraseControlsOpenIndex,
            session: session
        )
        let currentPhraseName = engineController.currentPhraseID.flatMap { phraseID in
            phrases.first { $0.id == phraseID }?.name
        }
        let queuedPhraseName = engineController.queuedPhraseID.flatMap { phraseID in
            phrases.first { $0.id == phraseID }?.name
        }
        let selectedPattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        let selectedSlicer = selectedSlicerStatus(session: session)
        let selectedNoteRepeatSnapshot = engineController.noteRepeatRuntimeSnapshot(for: session.store.selectedTrackID)
        let activeNoteRepeatTrackNames = session.store.tracks.compactMap { track in
            engineController.noteRepeatRuntimeSnapshot(for: track.id) == nil ? nil : track.name
        }
        let activeFillPreviewTrack = session.trackFillPreviewState.activeTrackID.flatMap { activeTrackID in
            session.store.tracks.first { $0.id == activeTrackID }
        }
        let drumPartHeaderModel = DrumPartWorkspaceHeaderModel(
            selectedTrack: session.store.selectedTrack,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups
        )
        let drumKitMatrixModel = currentDrumKitMatrixModel(session: session)
        let phrasePerformOverlayBasisName = session.phrasePerformOverlay.basisPhraseID.flatMap { phraseID in
            phrases.first { $0.id == phraseID }?.name
        }
        let canSavePhrasePerformOverlay = session.phrasePerformOverlay.basisPhraseID.map { phraseID in
            phrases.contains { $0.id == phraseID }
        } ?? false
        // tracksMode is still derived from the one global mode. Top-level
        // Scenes is now management only; scene perform lives under Phrase.
        let scenesModeStatus = section == .scenes
            ? ScenesWorkspaceMode.browseEdit
            : session.workspaceMode.scenesModeValue
        let status: String = """
        workspace=\(section.rawValue)
        workspaceMode=\(session.workspaceMode.rawValue)
        tracksMode=\(session.workspaceMode.tracksModeValue.rawValue)
        quantise=\(session.performQuantise.rawValue)
        performScopeCount=\(session.performTrackScope.count)
        quantisePending=\(quantisePendingStatus(session: session, engineController: engineController))
        quantiseFillCueActive=\(quantiseFillCueActiveStatus(session: session, engineController: engineController))
        transport=\(engineController.isRunning ? "play" : "stop")
        phraseCount=\(phrases.count)
        phraseNames=\(phrases.map(\.name).joined(separator: "|"))
        phraseControlsOpenIndex=\(visualPhraseControlsOpenIndex.map(String.init) ?? "none")
        stepOrderStatus=\(stepOrderStatus.status)
        stepOrderActiveMap=\(stepOrderStatus.activeMap)
        stepOrderMapCount=\(session.store.stepOrderMaps.count)
        stepOrderMapNames=\(session.store.stepOrderMaps.map(\.name).joined(separator: "|"))
        stepOrderAssignedMapID=\(stepOrderStatus.assignedMapID)
        stepOrderPendingToggle=\(stepOrderStatus.pendingToggle)
        stepOrderFixtureState=\(stepOrderFixtureState)
        trackSourceTab=\(trackSourceTabState)
        slicerFixture=\(slicerFixtureState)
        slicerLayer=\(slicerLayerState)
        slicerTab=\(slicerTabState)
        slicerSampleName=\(selectedSlicer.sampleName)
        slicerSliceCount=\(selectedSlicer.sliceCount)
        slicerClipStepCount=\(selectedSlicer.clipStepCount)
        slicerClipActiveStepCount=\(selectedSlicer.activeStepCount)
        scenesMode=\(scenesModeStatus.rawValue)
        sceneEditorFixture=\(sceneEditorFixtureState)
        libraryCategory=\(libraryCategoryState)
        libraryFixture=\(libraryFixtureState)
        libraryPoolCount=\(session.store.assetPool.count)
        libraryRecordingsCount=\(RecordingLibrary.shared.recordings.count)
        stepOrderMapDeletionStates=\(stepOrderMapDeletionStates(session: session))
        currentPhraseName=\(currentPhraseName ?? "none")
        queuedPhraseName=\(queuedPhraseName ?? "none")
        phraseQueueEnabled=\(engineController.isRunning && !phrases.isEmpty)
        phraseNowEnabled=\(!phrases.isEmpty)
        phrasePerformOverlayDirty=\(session.phrasePerformOverlay.isDirty)
        phrasePerformOverlayBasisPhraseName=\(phrasePerformOverlayBasisName ?? "none")
        stagedCellCount=\(session.phrasePerformOverlay.stagedCellCount)
        phrasePerformOverlayCanSaveBack=\(canSavePhrasePerformOverlay)
        phrasePerformOverlayCanRevert=\(session.phrasePerformOverlay.hasLiveCopy)
        phraseMatrixRenderedVisible=\(phraseMatrixRenderedVisible)
        phraseMatrixPageIndex=\(phraseMatrixPageIndex)
        phraseMatrixPageCount=\(phraseMatrixPageCount)
        phraseMatrixTrackCount=\(phraseMatrixTrackCount)
        phraseMatrixPreviousEnabled=\(phraseMatrixPreviousEnabled)
        phraseMatrixNextEnabled=\(phraseMatrixNextEnabled)
        phraseMatrixPreviousOccupancy=\(phraseMatrixPreviousOccupancy)
        phraseMatrixNextOccupancy=\(phraseMatrixNextOccupancy)
        phraseMatrixSelectedLayerID=\(phraseMatrixSelectedLayerID)
        phraseMatrixSelectedLayerName=\(phraseMatrixSelectedLayerName)
        phraseMatrixSelectorWidth=\(phraseMatrixSelectorWidth)
        phraseMatrixTrackGridWidth=\(phraseMatrixTrackGridWidth)
        phrasePerformLayerMode=\(phrasePerformLayerMode)
        phrasePerformLayerSelectorVisible=\(phrasePerformLayerSelectorVisible)
        phrasePerformLayerVariant=\(phrasePerformLayerVariant)
        phraseWorkspaceTab=\(phraseWorkspaceTab)
        phraseCellTool=\(phraseCellTool)
        phraseGlobalApplyTrackSelectorVisible=\(phraseGlobalApplyTrackSelectorVisible)
        phraseCaptureVisible=\(phraseCaptureVisible)
        masterGain=\(session.store.masterBus.masterOutputGain)
        firstTrackSendA=\(session.store.tracks.first?.mix.sendA ?? 0)
        firstTrackSendB=\(session.store.tracks.first?.mix.sendB ?? 0)
        trackCount=\(session.store.tracks.count)
        selectedTrackName=\(session.store.selectedTrack.name)
        selectedTrackType=\(session.store.selectedTrack.trackType.rawValue)
        selectedTrackGroupName=\(drumPartHeaderModel?.groupName ?? "none")
        drumPartHeaderVisible=\(drumPartHeaderModel != nil)
        drumTrackDefaultView=\(drumPartHeaderModel == nil ? "none" : (drumPartHeaderDivedIn ? "partEditor" : "kitMatrix"))
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
        drumKitMatrixRenderedTemplateChooserVisible=\(drumKitMatrixRenderedTemplateChooserState)
        drumKitMatrixRenderedDisplayStepCount=\(drumKitMatrixRenderedDisplayStepCount)
        drumKitMatrixRenderedLayer=\(drumKitMatrixRenderedLayer)
        drumKitMatrixRenderedGroupPatternSlot=\(drumKitMatrixRenderedGroupPatternSlot)
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
        drumKitMatrixGroupSelectedSlot=\(drumKitMatrixModel.map { $0.groupSelectedSlotIndex.map { "\($0 + 1)" } ?? "mixed" } ?? "none")
        drumKitMatrixStaleMemberCount=\(drumKitMatrixModel?.staleMemberCount ?? 0)
        drumKitMatrixDisplayStepCount=\(drumKitMatrixModel?.displayStepCount ?? drumKitMatrixDisplayStepCount)
        selectedPatternSourceMode=\(selectedPattern.sourceRef.mode.rawValue)
        selectedPatternHasClip=\(session.store.clipEntry(id: selectedPattern.sourceRef.clipID) != nil)
        selectedPatternHasGenerator=\(session.store.generatorEntry(id: selectedPattern.sourceRef.generatorID) != nil)
        performOverviewRowCount=\(PerformOverviewRowModel.rows(tracks: session.store.tracks, groups: session.store.trackGroups).count)
        selectedNoteRepeatAvailable=\(session.isNoteRepeatAvailable(trackID: session.store.selectedTrackID))
        selectedNoteRepeatStoredInterval=\(session.store.selectedTrack.noteRepeatInterval.rawValue)
        selectedNoteRepeatActive=\(selectedNoteRepeatSnapshot != nil)
        selectedNoteRepeatActiveInterval=\(selectedNoteRepeatSnapshot?.interval.rawValue ?? "none")
        selectedNoteRepeatCapturedStepNoteCount=\(selectedNoteRepeatSnapshot?.capturedStep?.notes.count ?? 0)
        noteRepeatActiveTrackNames=\(activeNoteRepeatTrackNames.isEmpty ? "none" : activeNoteRepeatTrackNames.joined(separator: "|"))
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
        audioInputTab=\(audioInputTabState)
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

    private static func currentStepOrderStatus(
        phrases: [PhraseModel],
        visualPhraseControlsOpenIndex: Int?,
        session: SequencerDocumentSession
    ) -> (status: String, activeMap: String, assignedMapID: String, pendingToggle: String) {
        let phrase: PhraseModel?
        if let visualPhraseControlsOpenIndex,
           phrases.indices.contains(visualPhraseControlsOpenIndex) {
            phrase = phrases[visualPhraseControlsOpenIndex]
        } else {
            phrase = phrases.first { $0.id == session.store.selectedPhraseID }
        }

        guard let phrase else {
            return ("none", "none", "none", "none")
        }

        let presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: session.store.stepOrderMaps,
            toggleState: session.stepOrderToggleState(phraseID: phrase.id)
        )
        let pendingToggle = session.stepOrderPendingToggle.map { pending in
            "\(pending.phraseID.uuidString):\(pending.requestedEnabled ? "on" : "off")"
        } ?? "none"
        return (
            presentation.statusLabel,
            presentation.activeMapName,
            presentation.assignedMapID?.uuidString ?? "none",
            pendingToggle
        )
    }

    private static func stepOrderMapDeletionStates(session: SequencerDocumentSession) -> String {
        session.store.stepOrderMaps
            .map { map in
                let status = session.stepOrderMapDeletionStatus(id: map.id)
                return "\(map.name):\(status.canDelete ? "deleteAvailable" : "deleteBlocked")"
            }
            .joined(separator: "|")
    }

    private static func applyPhrasePerformOverlayFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard let overlayCommand = command["phrasePerformOverlay"] else { return }

        switch overlayCommand {
        case "dirtyOneCell", "dirty-one-cell":
            guard let phrase = phraseForPerformOverlayFixture(session: session),
                  let trackID = session.store.tracks.first?.id,
                  let muteLayer = session.store.layers.first(where: { $0.target == .mute })
            else { return }

            section.wrappedValue = .tracks
            session.workspaceMode = .perform
            session.setSelectedTrackID(trackID)
            _ = session.stagePhrasePerformCell(
                .single(.bool(true)),
                layerID: muteLayer.id,
                trackIDs: [trackID],
                basisPhraseID: phrase.id
            )
        case "revert", "clear":
            session.revertPhrasePerformOverlay()
        default:
            break
        }
    }

    private static func phraseForPerformOverlayFixture(session: SequencerDocumentSession) -> PhraseModel? {
        session.store.phrases.first { $0.name == "Phrase A" } ?? session.store.phrases.first
    }

    /// RETIRED: the tracks Perform view no longer has a bespoke layer surface
    /// (it is navigation + selection; layer perform launches scoped from the
    /// selection). The `trackPerformLayer` / `trackPerformLayerSelector` /
    /// `trackPerformLayerVariant` / `phrasePerformCapture` commands and the
    /// `trackPerformLayer*` status fields are gone. Only the still-meaningful
    /// `trackPerformTrackCount` navigation fixture is kept (it just opens the
    /// tracks page in perform mode with N tracks). The retired keys are
    /// accepted but ignored so old visual scripts don't error.
    private static func applyTrackPerformLayerMatrixFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["trackPerformLayerSelector"] != nil ||
              command["trackPerformLayer"] != nil ||
              command["trackPerformLayerVariant"] != nil ||
              command["phrasePerformCapture"] != nil ||
              command["trackPerformTrackCount"] != nil
        else { return }

        section.wrappedValue = .tracks
        session.workspaceMode = .perform

        if let rawTrackCount = command["trackPerformTrackCount"],
           let trackCount = Int(rawTrackCount) {
            ensureTrackCount(trackCount, session: session)
        }
        // trackPerformLayer*/phrasePerformCapture intentionally ignored
        // (bespoke layer surface removed).
    }

    /// Note-repeat lived on the retired tracks-perform layer surface. The
    /// runtime engage/release/clear interaction is no longer driven from the
    /// tracks matrix (note repeat is a scoped/phrase-perform concern now), so
    /// the visual-command posts and the `trackPerformLayer` key are retired.
    /// The document-truth bits that are still meaningful — navigating to the
    /// tracks page in perform mode, ensuring track count, selecting a track,
    /// the fill source, and the stored note-repeat interval — are kept so
    /// existing fixtures that set up state don't break.
    private static func applyNoteRepeatPerformFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["noteRepeatSelectedTrackIndex"] != nil ||
              command["noteRepeatSource"] != nil ||
              command["noteRepeatInterval"] != nil ||
              command["noteRepeatEnsureSecondClipTrack"] == "true"
        else { return }

        section.wrappedValue = .tracks
        session.workspaceMode = .perform

        if command["noteRepeatEnsureSecondClipTrack"] == "true" {
            ensureTrackCount(2, session: session)
        }

        if let rawIndex = command["noteRepeatSelectedTrackIndex"],
           let selectedIndex = Int(rawIndex) {
            ensureTrackCount(selectedIndex + 1, session: session)
            let clampedIndex = min(max(0, selectedIndex), session.store.tracks.count - 1)
            session.setSelectedTrackID(session.store.tracks[clampedIndex].id)
        }

        if let sourceState = command["noteRepeatSource"] {
            applyTrackFillSource(sourceState, session: session)
        }

        if let rawInterval = command["noteRepeatInterval"],
           let interval = NoteRepeatInterval(rawValue: rawInterval) {
            session.setTrackNoteRepeatInterval(interval, trackID: session.store.selectedTrackID)
        }
        // noteRepeatAction (press/release/clear) retired: the tracks-matrix
        // note-repeat runtime trigger surface was removed.
    }

    private static func applyPhraseMatrixFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["phraseMatrixTrackCount"] != nil ||
              command["phraseMatrixPhraseCount"] != nil ||
              command["phraseMatrixPageIndex"] != nil ||
              command["phraseMatrixLayerID"] != nil ||
              command["phraseMatrixLayerIndex"] != nil ||
              command["phrasePerformLayerSelector"] != nil ||
              command["phrasePerformLayer"] != nil ||
              command["phrasePerformLayerVariant"] != nil ||
              command["phraseWorkspaceTab"] != nil ||
              command["phraseCellTool"] != nil ||
              command["phraseGlobalApplyTrackSelector"] != nil ||
              command["phraseCapture"] != nil
        else { return }

        section.wrappedValue = .phrase

        if let rawTrackCount = command["phraseMatrixTrackCount"],
           let trackCount = Int(rawTrackCount) {
            ensureTrackCount(trackCount, session: session)
        }

        if let rawPhraseCount = command["phraseMatrixPhraseCount"],
           let phraseCount = Int(rawPhraseCount) {
            ensurePhraseCount(phraseCount, session: session)
        }

        // New documents only carry the pattern and mute layers; layer-variant
        // captures need the full built-in set present before selecting one.
        if command["phraseMatrixEnsureDefaultLayers"] == "true" {
            session.batch(impact: .snapshotOnly, changed: .full) { store in
                var project = store.exportToProject()
                let existingLayerIDs = Set(project.layers.map(\.id))
                let missing = PhraseLayerDefinition.defaultSet(for: project.tracks)
                    .filter { !existingLayerIDs.contains($0.id) }
                guard !missing.isEmpty else { return }
                project.layers.append(contentsOf: missing)
                store.importFromProject(project)
            }
        }

        var posts: [String] = []

        if let rawPageIndex = command["phraseMatrixPageIndex"],
           let pageIndex = Int(rawPageIndex) {
            posts.append("page-index:\(pageIndex)")
        }

        if let layerID = command["phraseMatrixLayerID"] {
            posts.append("layer-id:\(layerID)")
        }

        if let rawLayerIndex = command["phraseMatrixLayerIndex"],
           let layerIndex = Int(rawLayerIndex) {
            posts.append("layer-index:\(layerIndex)")
        }

        switch command["phrasePerformLayerSelector"] {
        case "open", "visible", "true":
            phrasePerformLayerSelectorVisible = true
            posts.append("open-layer-selector")
        case "close", "hidden", "false":
            phrasePerformLayerSelectorVisible = false
            posts.append("close-layer-selector")
        default:
            break
        }

        if let rawLayer = command["phrasePerformLayer"],
           let layer = TrackPerformLayerMode(rawValue: rawLayer) {
            phrasePerformLayerMode = layer.rawValue

            if let variant = command["phrasePerformLayerVariant"],
               layer.inlineVariantLabels.contains(variant) {
                phrasePerformLayerVariant = variant
                phrasePerformLayerSelectorVisible = false
                posts.append("select-variant:\(layer.rawValue):\(variant)")
            } else if command["phrasePerformLayerSelector"] == nil {
                phrasePerformLayerVariant = "none"
                phrasePerformLayerSelectorVisible = false
                posts.append("select-layer:\(layer.rawValue)")
            }
        }

        if let rawTab = command["phraseWorkspaceTab"] {
            posts.append("tab:\(rawTab)")
        }

        if let rawTool = command["phraseCellTool"] {
            posts.append("cell-tool:\(rawTool)")
        }

        switch command["phraseGlobalApplyTrackSelector"] {
        case "open", "visible", "true":
            posts.append("global-apply-track-selector:open")
        case "close", "hidden", "false":
            posts.append("global-apply-track-selector:close")
        default:
            break
        }

        switch command["phraseCapture"] {
        case "open", "visible", "true":
            posts.append("phrase-capture:open")
        case "close", "hidden", "false":
            posts.append("phrase-capture:close")
        default:
            break
        }

        // The command may arrive in the same runloop tick that switches the
        // workspace to .phrase, before PhraseWorkspaceView has subscribed to
        // the notification. Keep the batch pending so the view can drain it
        // from onAppear; live views still react via the notifications.
        pendingPhraseMatrixCommands = posts
        for post in posts {
            NotificationCenter.default.post(name: .phraseMatrixVisualCommand, object: post)
        }
    }

    /// Pending phrase-matrix visual commands for a PhraseWorkspaceView that
    /// mounts after the command was applied (workspace-switch race). The view
    /// drains this in onAppear.
    static var pendingPhraseMatrixCommands: [String] = []

    static func drainPendingPhraseMatrixCommands() -> [String] {
        let pending = pendingPhraseMatrixCommands
        pendingPhraseMatrixCommands = []
        return pending
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
            switch row.content {
            case let .editable(_, lengthSteps, _):
                let visibleCount = min(model.displayStepCount, lengthSteps)
                return "steps\(visibleCount)\(lengthSteps > model.displayStepCount ? "+" : "")"
            case .generator:
                return "GEN"
            case let .readOnly(badge, _, _):
                return badge
            }
        }
        .joined(separator: "|")
    }

    private static func matrixPreviewActiveCounts(_ model: DrumKitMatrixModel) -> String {
        model.rows.map { row in
            switch row.content {
            case let .editable(_, lengthSteps, steps):
                let visibleCount = min(model.displayStepCount, lengthSteps)
                let activeCount = steps.prefix(visibleCount).filter { $0.main != nil }.count
                return "\(activeCount)"
            case .generator, .readOnly:
                return "NA"
            }
        }
        .joined(separator: "|")
    }

    private static func applyDrumKitMatrixCommand(
        command: [String: String],
        session: SequencerDocumentSession
    ) {
        guard command["drumKitMatrixCommand"] != nil ||
              command["drumKitMatrixLayer"] != nil ||
              command["drumKitMatrixPattern"] != nil ||
              command["drumKitMatrixTemplateChooser"] != nil
        else { return }

        switch command["drumKitMatrixCommand"] {
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
        case let rawCommand?:
            if rawCommand.hasPrefix("selectIndex:"),
               let rawIndex = rawCommand.split(separator: ":").last,
               let selectedIndex = Int(rawIndex) {
                drumKitMatrixVisualState = false
                drumKitMatrixRoutingEditorVisualState = false
                drumGroupRoutingEditorRenderedState = false
                drumGroupRoutingEditorMode = "none"
                NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "select-index:\(selectedIndex)")
            }
        case nil:
            break
        }

        // Matrix-wide step layer (steps / velocity / chance). Posted
        // repeatedly because the matrix view may mount after open-kit-view.
        if let rawLayer = command["drumKitMatrixLayer"],
           DrumKitMatrixLayer(rawValue: rawLayer) != nil {
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: "layer:\(rawLayer)")
        }

        // Group pattern row selection (1-based slot number in the command).
        if let rawPattern = command["drumKitMatrixPattern"],
           let slotNumber = Int(rawPattern),
           (1...TrackPatternBank.slotCount).contains(slotNumber) {
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: "pattern:\(slotNumber - 1)")
        }

        switch command["drumKitMatrixTemplateChooser"] {
        case "open", "visible", "true":
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: "open-template-chooser")
        case "close", "hidden", "false":
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-template-chooser")
        default:
            break
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
              command["drumPartHeaderDiveIn"] != nil ||
              command["drumKitMatrixFixture"] != nil
        else { return }

        section.wrappedValue = .track
        drumPartHeaderOpenKitOriginPartName = nil
        drumPartHeaderOpenKitOriginGroupName = nil
        drumPartHeaderDivedIn = false
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

        // Kit-first default: a drum-group track lands directly on the kit
        // matrix, so reflect the matrix as the default-visible view (and seed
        // the model-backed status keys) whenever a kit fixture is selected.
        // Rows that want the per-part editor must explicitly dive in below.
        let defaultMatrixModel = DrumPartWorkspaceHeaderModel(
            selectedTrack: session.store.selectedTrack,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups
        )
        if let defaultMatrixModel {
            drumKitMatrixVisualState = true
            drumKitMatrixGroupID = defaultMatrixModel.groupID
            drumKitMatrixOriginatingPartID = defaultMatrixModel.currentPartID
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

        // Kit-first dive-in: drill from the default kit matrix into the
        // currently selected part's editor. Mirrors selecting a part row in the
        // matrix, so QA rows that want the per-part editor still capture it.
        if command["drumPartHeaderDiveIn"] == "true" {
            drumPartHeaderDivedIn = true
            drumKitMatrixVisualState = false
            drumKitMatrixRoutingEditorVisualState = false
            drumKitMatrixGroupID = nil
            drumKitMatrixOriginatingPartID = nil
            postRepeatedVisualCommand(name: .drumPartWorkspaceHeaderVisualCommand, object: "dive-into-part")
        }
    }

    /// Drives the Steps/Clip/Sound/FX/Macros/Mixer tab on the track editor
    /// without coordinate clicks. Posts repeatedly because the editor view may
    /// not exist yet right after the section switch. The ROUTING tab is
    /// setup-only; the editor's own guard ignores a `routing` selection while
    /// the workspace is in perform mode.
    private static func applyTrackSourceTabCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>
    ) {
        guard let rawTab = command["trackSourceTab"],
              TrackSourceEditorTab.tab(forVisualCommand: rawTab) != nil
        else { return }

        section.wrappedValue = .track
        trackSourceTabState = rawTab
        postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:\(rawTab)")
    }

    /// Drives the slice-track workspace into populated, reviewable states.
    /// The fixture uses the real sample library and document mutation path so
    /// waveform, slice-set, and clip rendering stay honest.
    private static func applySlicerFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["slicerFixture"] != nil ||
              command["slicerLayer"] != nil
        else { return }

        section.wrappedValue = .track

        switch command["slicerFixture"] {
        case "populated", "grid":
            guard let sample = slicerFixtureSample(),
                  ensurePopulatedSlicerTrack(sample: sample, session: session) != nil
            else {
                slicerFixtureState = "missingSample"
                break
            }
            slicerFixtureState = "populated"
        case "empty":
            if session.store.selectedTrack.trackType != .slice {
                session.appendTrack(trackType: .slice)
            }
            slicerFixtureState = "empty"
        default:
            break
        }

        if let rawLayer = command["slicerLayer"],
           SliceTrackClipLayer(rawValue: rawLayer) != nil {
            slicerLayerState = rawLayer
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "layer:\(rawLayer)")
        }

        if let rawTab = command["slicerTab"],
           ["source", "slice", "fx", "macros", "mixer"].contains(rawTab) {
            slicerTabState = rawTab
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "tab:\(rawTab)")
        }
    }

    @discardableResult
    private static func ensurePopulatedSlicerTrack(
        sample: AudioSample,
        session: SequencerDocumentSession
    ) -> UUID? {
        let trackID: UUID
        if session.store.selectedTrack.trackType == .slice {
            trackID = session.store.selectedTrackID
        } else if let createdTrackID = session.appendSliceTrack(sample: sample) {
            trackID = createdTrackID
        } else {
            return nil
        }

        let sampleLengthFrames = slicerSampleLengthFrames(sample)
        guard sampleLengthFrames > 0 else { return nil }

        let existingSliceSetID: UUID? = {
            guard case let .slicer(sliceSetID, _) = session.store.resolvedDestination(for: trackID),
                  sliceSetID != SliceSet.emptyID
            else { return nil }
            return sliceSetID
        }()
        let settings: SlicerSettings = {
            guard case let .slicer(_, settings) = session.store.resolvedDestination(for: trackID) else {
                return .default
            }
            return settings
        }()

        var sliceSet = SliceSet(
            id: existingSliceSetID ?? UUID(),
            sampleID: sample.id,
            markers: gridSliceMarkers(sampleLengthFrames: sampleLengthFrames, sliceCount: 8),
            mode: .grid,
            bars: 2
        )
        sliceSet.normalize(sampleLengthFrames: sampleLengthFrames)

        session.setSelectedTrackID(trackID)
        session.setSlicerDestination(sliceSet: sliceSet, settings: settings, for: trackID)
        session.applySlicerAnalysis(
            sliceSet: sliceSet,
            sampleLengthFrames: sampleLengthFrames,
            clipLengthSteps: 16,
            for: trackID
        )
        return trackID
    }

    private static func slicerFixtureSample() -> AudioSample? {
        let library = AudioSampleLibrary.shared
        return library.samples(in: .breaks).sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }.first
            ?? library.samples(in: .recordings).first
            ?? library.samples.first
    }

    private static func slicerSampleLengthFrames(_ sample: AudioSample) -> Int64 {
        if let lengthFrames = sample.lengthFrames {
            return lengthFrames
        }
        guard let url = try? sample.fileRef.resolve(libraryRoot: AudioSampleLibrary.shared.libraryRoot),
              let file = try? AVAudioFile(forReading: url)
        else {
            return 0
        }
        return file.length
    }

    private static func gridSliceMarkers(sampleLengthFrames: Int64, sliceCount: Int) -> [SliceMarker] {
        let resolvedLength = max(1, sampleLengthFrames)
        let resolvedSliceCount = max(1, sliceCount)
        let whole = SliceMarker(startFrame: 0, endFrame: resolvedLength, tag: "Whole")
        let slices = (0..<resolvedSliceCount).map { index in
            let start = (resolvedLength * Int64(index)) / Int64(resolvedSliceCount)
            let end = (resolvedLength * Int64(index + 1)) / Int64(resolvedSliceCount)
            return SliceMarker(startFrame: start, endFrame: max(start + 1, end), tag: "S\(index + 1)")
        }
        return [whole] + slices
    }

    /// Drives the Library page: category selection plus deterministic
    /// fixtures for the pool and recordings states.
    private static func applyLibraryCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["libraryCategory"] != nil ||
              command["libraryFixture"] != nil
        else { return }

        section.wrappedValue = .library

        switch command["libraryFixture"] {
        case "recordings":
            applyLibraryRecordingsFixture()
            libraryFixtureState = "recordings"
        case "pool":
            applyLibraryPoolFixture(session: session)
            libraryFixtureState = "pool"
        default:
            break
        }

        if let rawCategory = command["libraryCategory"],
           LibraryCategory(rawValue: rawCategory) != nil {
            libraryCategoryState = rawCategory
            postRepeatedVisualCommand(name: .libraryWorkspaceVisualCommand, object: "category:\(rawCategory)")
        }
    }

    /// Replace the shared recording library's contents with two
    /// deterministic takes so the recordings captures are stable run-to-run.
    private static func applyLibraryRecordingsFixture() {
        let library = RecordingLibrary.shared
        try? FileManager.default.removeItem(at: library.recordingsDirectory)

        let capturedAt = Date(timeIntervalSince1970: 1_770_000_000)
        for (index, barCount) in [2, 4].enumerated() {
            let frameCount = 4410 * barCount
            let pcm = AudioInputCapturedPCM(
                sampleRate: 44_100,
                channels: (0..<2).map { channel in
                    (0..<frameCount).map { frame in
                        Float(sin(Double(frame) * 0.05 + Double(channel))) * 0.4
                    }
                }
            )
            do {
                _ = try library.storeRecording(
                    pcm: pcm,
                    sourceTrackName: "Audio In",
                    barCount: barCount,
                    bpm: 120,
                    capturedAt: capturedAt.addingTimeInterval(TimeInterval(index * 60))
                )
            } catch {
                NSLog("[VisualScenarioCommandRunner] recordings fixture write failed: \(error)")
            }
        }
        library.reload()
        AudioSampleLibrary.shared.reload()
        postRepeatedVisualCommand(name: .libraryWorkspaceVisualCommand, object: "reload")
    }

    /// Deterministic project pool: one sample, the factory 808 kit and
    /// template, plus a dangling sample ref so the missing state renders.
    private static func applyLibraryPoolFixture(session: SequencerDocumentSession) {
        for ref in session.store.assetPool {
            _ = session.removeAssetFromPool(kind: ref.kind, assetID: ref.assetID)
        }

        if let sample = AudioSampleLibrary.shared.firstSample(in: .kick) {
            _ = session.addAssetToPool(kind: .sample, assetID: sample.id)
        }
        if let kit = DrumAssetLibrary.factoryKits.first {
            _ = session.addAssetToPool(kind: .drumKit, assetID: kit.id)
        }
        if let template = DrumAssetLibrary.factoryTemplates.first {
            _ = session.addAssetToPool(kind: .patternTemplate, assetID: template.id)
        }
        let missingAssetID = UUID(uuidString: "DEAD0000-0000-4000-8000-000000000001") ?? UUID()
        _ = session.addAssetToPool(kind: .sample, assetID: missingAssetID)
    }

    /// Drives the top-level Scenes workspace via the legacy `scenesMode=`
    /// command. Top-level Scenes is management only now; phrase-local scene
    /// perform is captured through `workspace=phrase, phraseWorkspaceTab=scenes`.
    private static func applyScenesModeCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["scenesMode"] != nil || command["sceneEditorFixture"] != nil else { return }

        section.wrappedValue = .scenes

        if let rawMode = command["scenesMode"],
           let scenesMode = ScenesWorkspaceMode(rawValue: rawMode) {
            session.workspaceMode = .setup
            if command["sceneEditorFixture"] == nil {
                sceneEditorFixtureState = "none"
            }
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "mode:\(scenesMode.rawValue)")
        }

        if let rawFixture = command["sceneEditorFixture"],
           ["empty", "content"].contains(rawFixture) {
            session.workspaceMode = .setup
            sceneEditorFixtureState = rawFixture
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "mode:\(ScenesWorkspaceMode.browseEdit.rawValue)")
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "fixture:\(rawFixture)")
        }
    }

    private static func postRepeatedVisualCommand(name: Notification.Name, object: String) {
        NotificationCenter.default.post(name: name, object: object)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            NotificationCenter.default.post(name: name, object: object)
            try? await Task.sleep(nanoseconds: 350_000_000)
            NotificationCenter.default.post(name: name, object: object)
        }
    }

    private static func applyWorkspaceScrollCommand(command: [String: String]) {
        guard let rawScroll = command["workspaceScroll"] else { return }

        switch rawScroll {
        case "top":
            postRepeatedVisualCommand(name: .workspaceDetailVisualCommand, object: "scroll-top")
        case "bottom":
            postRepeatedVisualCommand(name: .workspaceDetailVisualCommand, object: "scroll-bottom")
        default:
            break
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

        let plan = DrumGroupPlan(
            name: "808 Bones",
            color: "#C06030",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare"),
                DrumGroupPlan.Member(tag: "clap", trackName: "Clap"),
                DrumGroupPlan.Member(tag: "hat-closed", trackName: "Closed Hat"),
                DrumGroupPlan.Member(tag: "hat-open", trackName: "Open Hat"),
                DrumGroupPlan.Member(tag: "rim", trackName: "Rim Shot"),
            ],
            sharedDestination: nil
        )
        _ = session.addDrumGroup(plan: plan)
        if let created = session.store.trackGroups.first(where: { $0.name == "808 Bones" && $0.memberIDs.count >= 6 }) {
            ensureVisibleDrumKitMatrixSeeds(groupID: created.id, session: session)
            return created
        }
        return session.store.trackGroups.last
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

        let plan = DrumGroupPlan(
            name: groupName,
            color: "#3A8F7A",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
            ],
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

        let plan = DrumGroupPlan(
            name: groupName,
            color: "#5A7FD6",
            members: [
                DrumGroupPlan.Member(
                    tag: "hat-closed",
                    trackName: "Generator Driven Closed Hat With A Very Long Performance Name"
                ),
                DrumGroupPlan.Member(
                    tag: "rim",
                    trackName: "Rim Shot With Long Alternate Layer Name"
                ),
            ],
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

    private static func applyStepOrderFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        guard let fixture = command["stepOrderFixture"] else { return }

        if engineController.isRunning {
            engineController.stop()
        }
        engineController.clearPendingStepOrderToggle()

        let assignedID = UUID(uuidString: "10000000-0000-4000-8000-000000000101") ?? UUID()
        let unusedID = UUID(uuidString: "10000000-0000-4000-8000-000000000102") ?? UUID()
        let invalidID = UUID(uuidString: "10000000-0000-4000-8000-000000000103") ?? UUID()
        let missingID = UUID(uuidString: "10000000-0000-4000-8000-000000000104") ?? UUID()
        let remapValues: [UInt8] = [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3]
        let assignedMap = StepOrderMap(id: assignedID, name: "Break Fold", values: remapValues)
        let unusedMap = StepOrderMap(id: unusedID, name: "Unused Identity")
        let invalidMap = StepOrderMap(id: invalidID, name: "Short Saved Map", values: [0, 1, 2])

        var project = session.store.exportToProject()
        guard !project.phrases.isEmpty else { return }

        let phraseIndex = project.selectedPhraseIndex
        var phrase = project.phrases[phraseIndex]
        phrase.lengthBars = 1
        phrase.stepsPerBar = StepOrderMap.stepCount
        phrase.stepOrderAssignment = nil
        project.stepOrderMaps = []

        switch fixture {
        case "unassigned", "supportedUnassigned":
            break
        case "assignedOff", "populatedEditor", "deleteBlocked", "deleteAvailable":
            project.stepOrderMaps = [assignedMap, unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: assignedID, isEnabled: false)
        case "assignedOn":
            project.stepOrderMaps = [assignedMap, unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: assignedID, isEnabled: true)
        case "pendingOn":
            project.stepOrderMaps = [assignedMap, unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: assignedID, isEnabled: false)
        case "pendingOff":
            project.stepOrderMaps = [assignedMap, unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: assignedID, isEnabled: true)
        case "invalid", "invalidMap":
            project.stepOrderMaps = [invalidMap, unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: invalidID, isEnabled: true)
        case "missing", "missingAssignedMap":
            project.stepOrderMaps = [unusedMap]
            phrase.stepOrderAssignment = StepOrderAssignment(mapID: missingID, isEnabled: true)
        default:
            return
        }

        project.phrases[phraseIndex] = phrase
        project.selectedPhraseID = phrase.id
        stepOrderFixtureState = fixture

        session.batch(impact: .snapshotOnly, changed: .full) { store in
            store.importFromProject(project)
        }
        section.wrappedValue = .phrase

        switch fixture {
        case "pendingOn":
            engineController.start()
            _ = session.requestPhraseStepOrderEnabled(true, phraseID: phrase.id)
        case "pendingOff":
            engineController.start()
            _ = session.requestPhraseStepOrderEnabled(false, phraseID: phrase.id)
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

    private static func applyWindowFrame(_ rawFrame: String) {
        let values = rawFrame
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 4,
              let window = NSApplication.shared.windows.first(where: { $0.isVisible })
                ?? NSApplication.shared.windows.first
        else { return }

        window.setFrame(
            NSRect(x: values[0], y: values[1], width: values[2], height: values[3]),
            display: true
        )
    }

    private static func ensurePhraseCount(_ count: Int, session: SequencerDocumentSession) {
        let targetCount = min(max(count, 1), 12)
        session.batch(impact: .snapshotOnly, changed: .full) { store in
            var project = store.exportToProject()
            project.syncPhrasesWithTracks()
            while project.phrases.count < targetCount {
                project.appendPhrase()
            }

            let tracks = project.tracks
            let layers = project.layers
            let patternLayerID = layers.first(where: { $0.target == .patternIndex })?.id
            let muteLayerID = layers.first(where: { $0.target == .mute })?.id
            let fillLayerID = layers.first(where: {
                if case .macroRow("fill-flag") = $0.target {
                    return true
                }
                return false
            })?.id

            for phraseIndex in project.phrases.indices.prefix(targetCount) {
                var phrase = project.phrases[phraseIndex]
                phrase.name = visualPhraseName(at: phraseIndex)
                phrase.lengthBars = [8, 4, 12, 2, 6][phraseIndex % 5]
                phrase.repeatCount = [1, 2, 0, 4, 1][phraseIndex % 5]
                phrase.loopEnabled = phraseIndex == 2

                for (trackIndex, track) in tracks.enumerated() {
                    if let patternLayerID {
                        phrase.setCell(.single(.index((phraseIndex + trackIndex) % 4)), for: patternLayerID, trackID: track.id)
                    }
                    if let muteLayerID, (phraseIndex + trackIndex).isMultiple(of: 5) {
                        phrase.setCell(.single(.bool(true)), for: muteLayerID, trackID: track.id)
                    }
                    if let fillLayerID, (phraseIndex + trackIndex).isMultiple(of: 4) {
                        phrase.setCell(.single(.bool(true)), for: fillLayerID, trackID: track.id)
                    }
                }

                project.phrases[phraseIndex] = phrase.synced(with: tracks, layers: layers)
            }

            if let firstPhraseID = project.phrases.first?.id {
                project.selectedPhraseID = firstPhraseID
            }
            store.importFromProject(project)
        }
    }

    private static func visualPhraseName(at index: Int) -> String {
        let names = ["Phrase A", "Phrase B", "Breakdown", "Build", "Drop", "Outro"]
        if names.indices.contains(index) {
            return names[index]
        }
        return "Phrase \(index + 1)"
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
              command["audioInputAvailableChannels"] != nil ||
              command["audioInputTab"] != nil
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
            session.setAudioInputChannel(trackID: trackID, channel: .stereo(firstChannel: 0))
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

        if let rawTab = command["audioInputTab"],
           ["source", "fx", "macros", "mixer"].contains(rawTab) {
            audioInputTabState = rawTab
            postRepeatedVisualCommand(name: .audioInputTrackWorkspaceVisualCommand, object: "tab:\(rawTab)")
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
