import AVFoundation
import AppKit
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
    private static var drumKitMatrixRenderedTemplateChooserState = false
    private static var drumKitMatrixRenderedDisplayStepCount = 16
    private static var drumKitMatrixRenderedLayer = "none"
    private static var drumKitMatrixRenderedGroupPatternSlot = "none"
    private static var drumKitMatrixRenderedGroupName = "none"
    private static var drumKitMatrixRenderedMemberCount = 0
    private static var drumKitMatrixRenderedKitTab = "none"
    private static var drumKitMatrixRenderedCaptureOpen = false
    private static var drumKitMatrixRenderedKitFXChooserVisible = false
    private static var drumKitMatrixRenderedSaveSlotPickerVisible = false
    private static var drumKitMatrixRenderedRowExpanded = false
    private static var drumKitMatrixRenderedExpandedPartIndex = -1
    private static var drumKitMatrixRenderedExpandedRowTab = "none"
    private static var drumKitMatrixRenderedExpandedSourceMode = "none"
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
    private static var phraseSceneViewModeState = PhraseSceneViewMode.macros.rawValue
    private static var phraseWorkspaceTab = "layers"
    private static var phraseCellTool = "value"
    private static var phraseGlobalApplyTrackSelectorVisible = false
    private static var phraseSceneSelectVisible = false
    private static var phraseCaptureVisible = false
    private static var tracksCreateTrackModalVisible = false
    private static var tracksAddDrumGroupModalVisible = false
    private static var tracksAddSliceTrackModalVisible = false
    private static var tracksTrackSoundModalVisible = false
    private static var stepOrderFixtureState = "none"
    private static var trackSourceTabState = "none"
    private static var trackSourceEditorRenderedVisible = false
    private static var trackSourceEditorRenderedTab = "none"
    private static var trackSourceGeneratorRenderedStage = "none"
    private static var trackClipLayerState = "trigger"
    private static var trackClipLayerSwitcherState = "closed"
    private static var trackGeneratorStageState = "trigger"
    private static var trackGeneratorKindState = "none"
    private static var sceneEditorFixtureState = "none"
    private static var scenesAddFXModalState = "closed"
    private static var scenesSelectedInsertIndex = "none"
    private static var libraryCategoryState = "none"
    private static var libraryFixtureState = "none"
    private static var slicerFixtureState = "none"
    private static var slicerLayerState = SliceTrackClipLayer.steps.rawValue
    private static var slicerLayerSwitcherState = "closed"
    private static var slicerTabState = "steps"
    private static var sliceSourceModalState = "closed"
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
    private static var lastAppliedVisualCommandID = "none"
    private static weak var commandChannelWindow: NSWindow?

    // MARK: - Command-channel ownership (single-driver protocol)

    /// The visual-command channel is a SINGLE-DRIVER protocol: exactly one
    /// process-wide watcher loop may own the command file.
    ///
    /// Why: macOS window restoration after a `kill -9`'d harness run
    /// resurrects extra document windows, and every `ContentView.onAppear`
    /// spawns its own runner loop bound to its own session +
    /// `EngineController`. In the 2026-07-02 12:40 drum-timing rig run TWO
    /// restored-window loops each applied every command: two 808 kits, two
    /// transport starts 9 ms apart on two controllers (two independent —
    /// each internally perfect — grids, origins 10.7 ms apart), and two
    /// master-render writers opened on ONE WAV path, poisoning the timing
    /// capture with a phantom "step 0 lands 26.4 ms early". First claim
    /// wins; duplicates are suppressed with a trace. Ownership is released
    /// when the owning loop exits (window closed / task cancelled) so a
    /// genuine handoff still works.
    private static let commandChannelOwnershipLock = NSLock()
    private static var commandChannelOwned = false

    /// Claim process-wide ownership of the command channel. Returns false when
    /// another runner loop already owns it (the caller must NOT attach).
    static func claimCommandChannelOwnership() -> Bool {
        commandChannelOwnershipLock.lock()
        defer { commandChannelOwnershipLock.unlock() }
        guard !commandChannelOwned else { return false }
        commandChannelOwned = true
        return true
    }

    /// Release ownership when the owning loop exits. Safe to call when not
    /// owned (idempotent).
    static func releaseCommandChannelOwnership() {
        commandChannelOwnershipLock.lock()
        defer { commandChannelOwnershipLock.unlock() }
        commandChannelOwned = false
        commandChannelWindow = nil
    }

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
        engineController: EngineController,
        owningWindow: @MainActor @escaping () -> NSWindow?
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
        // Single-driver protocol: only the FIRST runner loop attaches. Extra
        // document windows (macOS state restoration after a killed harness
        // run) must not each drive the channel — a duplicate driver
        // double-applies every command (two kits, two transports, two
        // master-render writers on one WAV; see the ownership doc above).
        guard claimCommandChannelOwnership() else {
            DevActivity.trace(
                DevActivity.harness,
                "duplicate visual-command runner suppressed — channel already owned (restored window?)"
            )
            return
        }
        commandChannelWindow = owningWindow()
        defer { releaseCommandChannelOwnership() }
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
            if commandChannelWindow == nil {
                commandChannelWindow = owningWindow()
            }

            if let payload = try? String(contentsOf: commandURL), payload != lastPayload {
                lastPayload = payload
                let command = parse(payload)
                lastAppliedVisualCommandID = command["visualCommandID"].flatMap { $0.isEmpty ? nil : $0 } ?? "none"
                DevActivity.trace(DevActivity.harness, "apply command: \(payload.replacingOccurrences(of: "\n", with: "; "))")
                apply(
                    command: command,
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
                drumKitMatrixRenderedKitTab = userInfo["kitTab"] as? String ?? "none"
                drumKitMatrixRenderedCaptureOpen = userInfo["captureOpen"] as? Bool ?? false
                drumKitMatrixRenderedKitFXChooserVisible = userInfo["kitFXChooserVisible"] as? Bool ?? false
                drumKitMatrixRenderedSaveSlotPickerVisible = userInfo["historySaveSlotPickerVisible"] as? Bool ?? false
                drumKitMatrixRenderedRowExpanded = userInfo["rowExpanded"] as? Bool ?? false
                drumKitMatrixRenderedExpandedPartIndex = userInfo["expandedPartIndex"] as? Int ?? -1
                drumKitMatrixRenderedExpandedRowTab = userInfo["expandedRowTab"] as? String ?? "none"
                drumKitMatrixRenderedExpandedSourceMode = userInfo["expandedSourceMode"] as? String ?? "none"
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
            forName: .trackSourceEditorRenderedVisualState,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            Task { @MainActor in
                trackSourceEditorRenderedVisible = userInfo["visible"] as? Bool ?? false
                trackSourceEditorRenderedTab = userInfo["tab"] as? String ?? "none"
            }
        }
        NotificationCenter.default.addObserver(
            forName: .trackSourceGeneratorRenderedVisualState,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo else { return }
            Task { @MainActor in
                trackSourceGeneratorRenderedStage = userInfo["stage"] as? String ?? "none"
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
                phraseSceneSelectVisible = userInfo["sceneSelectVisible"] as? Bool ?? false
                phraseCaptureVisible = userInfo["captureVisible"] as? Bool ?? false
                phraseSceneViewModeState = userInfo["sceneViewMode"] as? String ?? PhraseSceneViewMode.macros.rawValue
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

        // Tracks navigator selection mode (ux-rethink-2): flip selection mode
        // on/off, then optionally select a track so a capture shows the actions
        // nav. `tracksSelect` accepts `selected` (the current selected track),
        // `first` (the first project track), or a UUID.
        if let rawSelectionMode = command["tracksSelectionMode"] {
            session.tracksSelectionMode = rawSelectionMode == "on"
            section.wrappedValue = .tracks
        }
        // Clear runs BEFORE select so a capture row can reset to a known
        // selection deterministically (rows share session state).
        if command["tracksClearSelection"] == "true" {
            session.tracksSelection.removeAll()
        }
        if let rawSelect = command["tracksSelect"] {
            let trackID: UUID? = {
                switch rawSelect {
                case "selected": return session.store.selectedTrackID
                case "first": return session.store.tracks.first?.id
                default: return UUID(uuidString: rawSelect)
                }
            }()
            if let trackID, session.store.tracks.contains(where: { $0.id == trackID }) {
                session.toggleTrackSelected(trackID)
            }
        }
        if command["tracksPrimeClipboard"] == "true" {
            pendingTracksMatrixCommands.append("copy-selection")
            postRepeatedVisualCommand(name: .tracksMatrixVisualCommand, object: "copy-selection")
        }
        // Drive the tracks actions nav: stash the selection as the perform
        // scope and request navigation to Phrase Layers, exactly as the By
        // Track / By Value buttons do. `WorkspaceDetailView` and
        // `PhraseWorkspaceView` then complete the navigation.
        if let rawAction = command["tracksAction"] {
            let mode: PhraseLayerEditMode? = {
                switch rawAction {
                case "layerPerform", "byTrack": return .byTrack
                case "sameValue", "byValue": return .byValue
                default: return nil
                }
            }()
            if let mode {
                session.requestPhrasePerform(
                    tab: .layers,
                    layerEditMode: mode,
                    trackIDs: session.tracksSelection
                )
            }
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

        // Global transport swing (0…1), the same seam the transport-bar
        // stepper drives (`transport-swing`, commit ade9a296). Clamped by
        // `setSwing`; the status file reports the applied `currentSwing`.
        if let swingRaw = command["swing"],
           let swing = Double(swingRaw) {
            engineController.setSwing(swing)
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
        applyRoutingStressCommands(command: command, session: session)
        applyTrackFillPreviewFixture(command: command, section: section, session: session)
        applyTrackRandomizeFixture(command: command, section: section, session: session)
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
        applyTracksMatrixModalCommand(command: command, section: section)
        applyPhrasePerformOverlayFixture(command: command, section: section, session: session)
        applyTrackPerformLayerMatrixFixture(command: command, section: section, session: session)
        applyNoteRepeatPerformFixture(command: command, section: section, session: session)
        applyDrumPartHeaderFixture(command: command, section: section, session: session)
        applyDrumKitMatrixCommand(command: command, session: session)
        applyTrackSoundSourceCommand(command: command, section: section, session: session)
        applyTrackSourceTabCommand(command: command, section: section, session: session)
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

        // Headless master-audio capture (probe/drum-timing): `masterRender=start:<path>`
        // begins writing the master output tap to a WAV; `masterRender=stop` ends it.
        if let render = command["masterRender"] {
            if render == "stop" {
                _ = engineController.stopMasterRender()
            } else if render.hasPrefix("start:") {
                let path = String(render.dropFirst("start:".count))
                _ = engineController.startMasterRender(to: URL(fileURLWithPath: path))
            }
        }

        // Create the FACTORY default 808 kit + its factory "808" clip via the
        // REAL app path (probe/drum-timing): session.addDrumGroup →
        // Project.createDrumGroup resolves each part to a bundled sample by
        // category and, given the plan's templateID, applies the template's
        // clips into slot 0 — exactly what a user gets. No synthetic fixture.
        // `createDefault808=1` (or `all`) builds the full factory 808 kit;
        // `createDefault808=<tag>` (e.g. kick / snare / hat-closed / clap) builds
        // a single-part kit for clean per-part timing isolation. Still the real
        // path — real bundled sample + the factory clip's pattern for that tag.
        if let raw = command["createDefault808"],
           let kit = DrumAssetLibrary.factoryKits.first(where: { $0.name == "808" }) {
            let templateID = DrumAssetLibrary.factoryTemplates.first(where: { $0.name == "808" })?.id
            var plan = DrumGroupPlan.from(kit: kit, templateID: templateID)
            if raw != "1", raw != "all" {
                plan.members = plan.members.filter { $0.tag == raw }
            }
            if !plan.members.isEmpty {
                _ = session.addDrumGroup(plan: plan)
            }
        }

        if let commandID = command["visualCommandID"], !commandID.isEmpty {
            lastAppliedVisualCommandID = commandID
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

    // MARK: - Routing-stress drive (graph-edit self-test rig)

    /// Drives the live graph-edit operations the routing-stress harness needs
    /// to reproduce/observe the mute and add-insert hangs unattended. All keys
    /// are addressed by TRACK INDEX (`<idx>`) or BUS INDEX into the document's
    /// ordered collections, resolved at apply time. Native inserts only — no AU
    /// (AU needs a human for the TCC prompt). Additive; mirrors the existing
    /// command-apply patterns (resolve → mutate session on the main actor).
    private static func applyRoutingStressCommands(
        command: [String: String],
        session: SequencerDocumentSession
    ) {
        // trackMute=<idx>:<on|off> — mixer track mute via setTrackMix (the
        // setMix / effectiveMixerMuteState path that deadlocks).
        if let raw = command["trackMute"],
           let (index, value) = parseIndexedToggle(raw),
           session.store.tracks.indices.contains(index) {
            // Route through setTrackMuted so the #60 mute/solo mutual-exclusion
            // invariant holds (engaging mute clears solo) consistently with the
            // mixer toggle handlers.
            session.setTrackMuted(value, trackID: session.store.tracks[index].id)
        }

        // trackLayerMute=<idx>:<on|off> — PERFORM-LAYER mute (distinct from the
        // mixer mute above). Stages a mute cell on the live phrase-perform
        // overlay so the engine applies it via setMuteGain (the layer-mute path
        // that the F1 OR-combine fix protects). The gate drives this to verify
        // the OR-combine acoustically: a mixer-muted track must STAY silent when
        // a layer-mute is toggled on then off on top of it.
        if let raw = command["trackLayerMute"],
           let (index, value) = parseIndexedToggle(raw),
           session.store.tracks.indices.contains(index),
           let muteLayer = session.store.layers.first(where: { $0.target == .mute }),
           let basisPhrase = session.store.phrases.first(where: { $0.id == session.store.selectedPhraseID })
            ?? session.store.phrases.first {
            let trackID = session.store.tracks[index].id
            _ = session.stagePhrasePerformCell(
                .single(.bool(value)),
                layerID: muteLayer.id,
                trackIDs: [trackID],
                basisPhraseID: basisPhrase.id
            )
        }

        // busMute=<idx>:<on|off> — mixer bus mute via setMixerBusMuted.
        if let raw = command["busMute"],
           let (index, value) = parseIndexedToggle(raw),
           session.store.buses.indices.contains(index) {
            session.setMixerBusMuted(value, busID: session.store.buses[index].id)
        }

        // trackAddInsert=<idx>:<native-filter|native-bitcrusher> — append a
        // native insert to a track's FX chain (live graph mutation). NO AU.
        if let raw = command["trackAddInsert"],
           let (index, kind) = parseIndexedValue(raw),
           session.store.tracks.indices.contains(index),
           let insert = nativeTrackInsert(kind) {
            session.mutateTrackFXInserts(trackID: session.store.tracks[index].id) { inserts in
                inserts.append(insert)
            }
        }

        // trackRemoveInsert=<idx>:<insertIdx> — remove an insert by position.
        if let raw = command["trackRemoveInsert"],
           let (index, insertIdxRaw) = parseIndexedValue(raw),
           let insertIdx = Int(insertIdxRaw),
           session.store.tracks.indices.contains(index) {
            session.mutateTrackFXInserts(trackID: session.store.tracks[index].id) { inserts in
                if inserts.indices.contains(insertIdx) {
                    inserts.remove(at: insertIdx)
                }
            }
        }

        // masterAddInsert=<native-filter|native-bitcrusher> — append a native
        // insert to the master bus (active scene). NO AU.
        if let raw = command["masterAddInsert"],
           let insert = nativeMasterInsert(raw) {
            session.addMasterBusInsert(insert)
        }

        // routeTrackToBus=<idx>:<busIdx|master> — reassign a track's output bus
        // (live disconnect/reconnect). `master` clears the bus (= master out).
        if let raw = command["routeTrackToBus"],
           let (index, dest) = parseIndexedValue(raw),
           session.store.tracks.indices.contains(index) {
            let trackID = session.store.tracks[index].id
            if dest == "master" {
                session.setTrackOutputBus(trackID: trackID, busID: nil)
            } else if let busIdx = Int(dest),
                      session.store.buses.indices.contains(busIdx) {
                session.setTrackOutputBus(trackID: trackID, busID: session.store.buses[busIdx].id)
            }
        }

        // routeNoteToTrack=<srcIdx>:<dstIdx> — upsert a Route sending the
        // source track's generated notes into the destination track's input.
        // Used by the gate to verify the F2 routed-audio consistency fix
        // acoustically: with the destination track MUTED, the routed note must
        // still trigger the destination's sampler (mute is a gain, not a
        // trigger-gate) yet the destination must read SILENT (its gain is 0).
        if let raw = command["routeNoteToTrack"],
           let (srcIndex, dstRaw) = parseIndexedValue(raw),
           let dstIndex = Int(dstRaw),
           session.store.tracks.indices.contains(srcIndex),
           session.store.tracks.indices.contains(dstIndex) {
            let srcID = session.store.tracks[srcIndex].id
            let dstID = session.store.tracks[dstIndex].id
            session.upsertRoute(
                Route(
                    source: .track(srcID),
                    destination: .trackInput(dstID, tag: nil)
                )
            )
        }

        // trackSend=<idx>:A=<0..1>,B=<0..1> — per-track sends. Either field may
        // be omitted; missing fields keep the current value.
        if let raw = command["trackSend"],
           let (index, fields) = parseIndexedValue(raw),
           session.store.tracks.indices.contains(index) {
            let track = session.store.tracks[index]
            var sendA = track.mix.sendA
            var sendB = track.mix.sendB
            for field in fields.split(separator: ",") {
                let pair = field.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let value = Double(pair[1]) else { continue }
                switch pair[0].uppercased() {
                case "A": sendA = value
                case "B": sendB = value
                default: break
                }
            }
            session.setTrackSends(trackID: track.id, sendA: sendA, sendB: sendB)
        }

        // resetClickHold=1 — reset the master maxSampleDelta peak-hold so the
        // next op's discontinuity is measured from a clean baseline.
        if command["resetClickHold"] == "1" {
            resetMasterMaxSampleDeltaHold()
        }

        // injectClickHold=<value> — POSITIVE-CONTROL hook: force a known value
        // into the master maxSampleDelta peak-hold. The routing-stress gate uses
        // this to PROVE the click metric → status-file → gate plumbing is live
        // and the click floor is reachable (a deterministic positive control),
        // decoupled from the acoustic measurement, which on a continuous bed is
        // dominated by note-onset transients and normalization at low levels and
        // so cannot by itself distinguish an op-click. Harness-only (no effect
        // outside the command channel, which exists only in capture mode).
        if let raw = command["injectClickHold"], let value = Double(raw) {
            injectMasterMaxSampleDeltaHold(value)
        }

        // removeTrack=<idx> — structural track removal (live graph mutation).
        if let raw = command["removeTrack"],
           let index = Int(raw.trimmingCharacters(in: .whitespaces)),
           session.store.tracks.indices.contains(index) {
            session.removeTrack(id: session.store.tracks[index].id)
        }

        // drumGroupAddPart=<groupIdx>:<sampleSourceTrackIdx> — add a sample-backed
        // part to an existing drum group DURING PLAYBACK. The new part reuses the
        // sample destination of an existing resident sample track so it SOUNDS
        // immediately (NOT internalSampler — that is silent). Structural add on
        // the live engine via the unified .fullEngineApply path. NO AU.
        if let raw = command["drumGroupAddPart"],
           let (groupIndex, sourceRaw) = parseIndexedValue(raw),
           let sourceIndex = Int(sourceRaw),
           session.store.trackGroups.indices.contains(groupIndex),
           session.store.tracks.indices.contains(sourceIndex) {
            session.addDrumPart(
                groupID: session.store.trackGroups[groupIndex].id,
                sampleSourceTrackID: session.store.tracks[sourceIndex].id
            )
        }

        // drumGroupRemovePart=<groupIdx>:<memberIdx> — remove the Nth member from
        // a drum group DURING PLAYBACK (structural remove on the live engine via
        // the unified .fullEngineApply path; the part's voices may be sounding).
        if let raw = command["drumGroupRemovePart"],
           let (groupIndex, memberRaw) = parseIndexedValue(raw),
           let memberIndex = Int(memberRaw),
           session.store.trackGroups.indices.contains(groupIndex) {
            session.removeDrumPart(
                groupID: session.store.trackGroups[groupIndex].id,
                memberIndex: memberIndex
            )
        }
    }

    /// Parse `<idx>:<on|off>` (also accepts true/false/1/0).
    private static func parseIndexedToggle(_ raw: String) -> (index: Int, value: Bool)? {
        guard let (index, value) = parseIndexedValue(raw) else { return nil }
        switch value.lowercased() {
        case "on", "true", "1", "yes": return (index, true)
        case "off", "false", "0", "no": return (index, false)
        default: return nil
        }
    }

    /// Parse `<idx>:<rest>` where `rest` may itself contain `:`/`,`.
    private static func parseIndexedValue(_ raw: String) -> (index: Int, value: String)? {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let index = Int(parts[0].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (index, parts[1].trimmingCharacters(in: .whitespaces))
    }

    private static func nativeTrackInsert(_ kind: String) -> TrackFXInsert? {
        switch kind {
        case "native-filter", "filter": return .filter()
        case "native-bitcrusher", "bitcrusher": return .bitcrusher()
        default: return nil
        }
    }

    private static func nativeMasterInsert(_ kind: String) -> MasterBusInsert? {
        switch kind {
        case "native-filter", "filter": return .filter()
        case "native-bitcrusher", "bitcrusher": return .bitcrusher()
        default: return nil
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

    /// Per-track / per-bus level + post-condition readback for the
    /// routing-stress gate. The summed master meter hides a single dead track
    /// under the drone, and "didn't hang" is not "took effect" — so the gate
    /// needs per-track levels (channel meter taps) AND document/graph state
    /// read back after each op. Emitted as `trackN<field>=` and `busN<field>=`
    /// lines so the bash gate can assert EXPECTED deltas + post-conditions.
    /// Peak-HOLD of master maxSampleDelta across status writes. The status file
    /// is rewritten every ~100 ms but the meter resets its discontinuity metric
    /// every 60 Hz publish, so a single 100 ms snapshot usually samples a low
    /// inter-transient value and misses a sparse drum-hit spike. Holding the max
    /// across writes (reset via the `resetClickHold` command before each gated
    /// op) lets the gate read the true peak discontinuity in any window.
    private static var masterMaxSampleDeltaHold: Double = 0

    static func resetMasterMaxSampleDeltaHold() {
        masterMaxSampleDeltaHold = 0
    }

    /// Positive-control hook: force the hold to a known value so the gate can
    /// verify the metric→status→gate path and that the click floor is reachable.
    static func injectMasterMaxSampleDeltaHold(_ value: Double) {
        masterMaxSampleDeltaHold = max(masterMaxSampleDeltaHold, value)
    }

    /// A track/bus gain at or below this counts as "effectively muted" by the
    /// ENGINE (mute ramps the gain to 0; a tiny epsilon absorbs ramp residue).
    private static let appliedMuteGainEpsilon: Float = 0.001

    static func routingStressStatusLines(
        session: SequencerDocumentSession,
        engineController: EngineController
    ) -> String {
        let tracks = session.store.tracks
        let buses = session.store.buses
        masterMaxSampleDeltaHold = max(
            masterMaxSampleDeltaHold,
            engineController.masterMeterPublisher.displayState.maxSampleDelta
        )
        // Document-derived mute (the OLD self-fulfilling source) is still
        // emitted as `track<N>DocMuted` for diagnostics, but the gate's
        // post-condition (`track<N>EffectiveMuted`) is now ENGINE-derived from
        // the applied output gain — so it cannot pass on a parse-only no-op.
        let docMuteState = EngineController.effectiveMixerMuteState(
            tracks: tracks,
            buses: buses
        )
        var lines: [String] = []
        for (index, track) in tracks.enumerated() {
            let meter = engineController
                .channelMeterPublisher(for: .track(track.id))
                .displayState
            let peak = max(meter.leftPeakDBFS, meter.rightPeakDBFS)
            let destination = session.store.resolvedDestination(for: track.id)

            // ENGINE-TRUTH: applied output gain (works for sample AND AU now).
            let appliedGain = engineController.trackAppliedOutputGainForTesting(trackID: track.id)
            // ENGINE-TRUTH: which bus the graph actually routed this track to.
            let appliedBus = engineController.trackAppliedOutputBusIDForTesting(trackID: track.id)
            // ENGINE-TRUTH: installed insert NODE count in the live graph.
            let installedInserts = engineController.trackInstalledInsertNodeCountForTesting(trackID: track.id)

            // EffectiveMuted from the engine: gain reads ~0. When no gain stage
            // is exposed yet (host not loaded), fall back to the doc value so a
            // not-yet-prepared track does not read a spurious "audible".
            let engineMuted: Bool
            if let appliedGain {
                engineMuted = appliedGain <= appliedMuteGainEpsilon
            } else {
                engineMuted = docMuteState.mutedTrackIDs.contains(track.id)
            }

            // OutputBus name from the ENGINE record. Outer-nil (no engine
            // record) falls back to the document so a not-yet-prepared track is
            // not flagged; inner-nil = master.
            let busName: String
            switch appliedBus {
            case let .some(busIDOrNil):
                busName = busIDOrNil
                    .flatMap { id in buses.first { $0.id == id }?.name } ?? "master"
            case .none:
                busName = track.outputBusID
                    .flatMap { id in buses.first { $0.id == id }?.name } ?? "master"
            }

            lines.append("track\(index)Name=\(track.name)")
            lines.append("track\(index)Peak=\(peak)")
            lines.append("track\(index)MaxSampleDelta=\(meter.maxSampleDelta)")
            lines.append("track\(index)EffectiveMuted=\(engineMuted)")
            lines.append("track\(index)DocMuted=\(docMuteState.mutedTrackIDs.contains(track.id))")
            lines.append("track\(index)RawMuted=\(track.mix.isMuted)")
            lines.append("track\(index)AppliedGain=\(appliedGain.map { String($0) } ?? "n/a")")
            lines.append("track\(index)DestinationKind=\(destination.kindLabel)")
            lines.append("track\(index)OutputBus=\(busName)")
            lines.append("track\(index)Gain=\(appliedGain.map { String($0) } ?? "n/a")")
            lines.append("track\(index)FXInsertCount=\(installedInserts)")
            lines.append("track\(index)DocFXInsertCount=\(track.fxInserts.count)")

            // ENGINE-TRUTH applied send gains (live send-mixer node
            // outputVolume) + the document-configured levels. The gate asserts
            // send edits land on the live nodes exactly (e.g. a muted track's
            // send legs read ≈0 and unmute restores the configured levels).
            let appliedSends = engineController.trackAppliedSendLevelsForTesting(trackID: track.id)
            lines.append("track\(index)AppliedSendA=\(appliedSends.map { String($0.sendA) } ?? "n/a")")
            lines.append("track\(index)AppliedSendB=\(appliedSends.map { String($0.sendB) } ?? "n/a")")
            lines.append("track\(index)DocSendA=\(track.mix.sendA)")
            lines.append("track\(index)DocSendB=\(track.mix.sendB)")
        }
        lines.append("reconnectTrackOutputCount=\(engineController.reconnectTrackOutputCountForTesting)")
        lines.append("sendRampCount=\(engineController.sendRampCountForTesting)")
        lines.append("masterMaxSampleDeltaHold=\(masterMaxSampleDeltaHold)")
        for (index, bus) in buses.enumerated() {
            let meter = engineController
                .channelMeterPublisher(for: .bus(bus.id))
                .displayState
            let peak = max(meter.leftPeakDBFS, meter.rightPeakDBFS)
            // ENGINE-TRUTH bus mute: the bus mixer node's applied output gain.
            let appliedBusGain = engineController.busAppliedOutputGainForTesting(busID: bus.id)
            let engineBusMuted: Bool
            if let appliedBusGain {
                engineBusMuted = appliedBusGain <= appliedMuteGainEpsilon
            } else {
                engineBusMuted = docMuteState.mutedBusIDs.contains(bus.id)
            }
            lines.append("bus\(index)Name=\(bus.name)")
            lines.append("bus\(index)Peak=\(peak)")
            lines.append("bus\(index)EffectiveMuted=\(engineBusMuted)")
            lines.append("bus\(index)DocMuted=\(docMuteState.mutedBusIDs.contains(bus.id))")
            lines.append("bus\(index)RawMuted=\(bus.mix.isMuted)")
            lines.append("bus\(index)AppliedGain=\(appliedBusGain.map { String($0) } ?? "n/a")")
        }

        // Drum-group membership + per-member ENGINE-TRUTH node presence. After a
        // drumGroupAddPart the new member's track should be engine-connected
        // (applied output gain reads non-`n/a` because its sample mixer node is
        // attached); after drumGroupRemovePart the member is gone from the group
        // and its node is detached. Used by the routing-stress rig to assert the
        // structural edit landed in the live graph (not just the document).
        for (groupIndex, group) in session.store.trackGroups.enumerated() {
            lines.append("drumGroup\(groupIndex)MemberCount=\(group.memberIDs.count)")
            // Count members whose output node is actually present in the engine.
            let connectedMembers = group.memberIDs.filter { memberID in
                engineController.trackAppliedOutputGainForTesting(trackID: memberID) != nil
            }
            lines.append("drumGroup\(groupIndex)EngineConnectedMemberCount=\(connectedMembers.count)")
        }
        return lines.joined(separator: "\n")
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
        visualCommandID=\(lastAppliedVisualCommandID)
        visualCommandWindowNumber=\(commandChannelWindow?.windowNumber ?? -1)
        workspace=\(section.rawValue)
        workspaceMode=\(session.workspaceMode.rawValue)
        tracksMode=\(session.workspaceMode.tracksModeValue.rawValue)
        quantise=\(session.performQuantise.rawValue)
        performScopeCount=\(session.performTrackScope.count)
        tracksSelectionMode=\(session.tracksSelectionMode ? "on" : "off")
        tracksSelectionCount=\(session.tracksSelection.count)
        quantisePending=\(quantisePendingStatus(session: session, engineController: engineController))
        quantiseFillCueActive=\(quantiseFillCueActiveStatus(session: session, engineController: engineController))
        transport=\(engineController.isRunning ? "play" : "stop")
        bpm=\(engineController.currentBPM)
        swing=\(engineController.currentSwing)
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
        trackSourceEditorRenderedVisible=\(trackSourceEditorRenderedVisible)
        trackSourceEditorRenderedTab=\(trackSourceEditorRenderedTab)
        trackSourceGeneratorRenderedStage=\(trackSourceGeneratorRenderedStage)
        trackClipLayer=\(trackClipLayerState)
        trackClipLayerSwitcher=\(trackClipLayerSwitcherState)
        trackGeneratorStage=\(trackGeneratorStageState)
        trackGeneratorKind=\(trackGeneratorKindState)
        trackSourceAddSourceVisible=\(trackSourceAddSourceVisible(selectedPattern: selectedPattern, session: session))
        selectedTrackSceneMembership=\(session.store.selectedTrack.mix.sceneMembership.rawValue)
        selectedTrackSoundDestinationKind=\(selectedTrackSoundDestinationKind(session: session))
        slicerFixture=\(slicerFixtureState)
        slicerLayer=\(slicerLayerState)
        slicerLayerSwitcher=\(slicerLayerSwitcherState)
        slicerTab=\(slicerTabState)
        sliceSourceModal=\(sliceSourceModalState)
        slicerSampleName=\(selectedSlicer.sampleName)
        slicerSliceCount=\(selectedSlicer.sliceCount)
        slicerClipStepCount=\(selectedSlicer.clipStepCount)
        slicerClipActiveStepCount=\(selectedSlicer.activeStepCount)
        scenesMode=\(scenesModeStatus.rawValue)
        sceneEditorFixture=\(sceneEditorFixtureState)
        scenesAddFXModal=\(scenesAddFXModalState)
        scenesAddFXModalVisible=\(scenesAddFXModalState == "open")
        scenesSelectedInsertIndex=\(scenesSelectedInsertIndex)
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
        phraseSceneSelectVisible=\(phraseSceneSelectVisible)
        phraseSceneViewMode=\(phraseSceneViewModeState)
        phraseCaptureVisible=\(phraseCaptureVisible)
        tracksCreateTrackModalVisible=\(tracksCreateTrackModalVisible)
        tracksAddDrumGroupModalVisible=\(tracksAddDrumGroupModalVisible)
        tracksAddSliceTrackModalVisible=\(tracksAddSliceTrackModalVisible)
        tracksTrackSoundModalVisible=\(tracksTrackSoundModalVisible)
        masterGain=\(session.store.masterBus.masterOutputGain)
        firstTrackSendA=\(session.store.tracks.first?.mix.sendA ?? 0)
        firstTrackSendB=\(session.store.tracks.first?.mix.sendB ?? 0)
        trackCount=\(session.store.tracks.count)
        selectedTrackName=\(session.store.selectedTrack.name)
        selectedTrackType=\(session.store.selectedTrack.trackType.rawValue)
        selectedTrackGroupName=\(drumPartHeaderModel?.groupName ?? "none")
        drumPartHeaderVisible=\(drumPartHeaderModel != nil)
        drumTrackDefaultView=\(drumPartHeaderModel == nil ? "none" : "kitMatrix")
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
        drumKitMatrixRenderedKitTab=\(drumKitMatrixRenderedKitTab)
        drumKitMatrixRenderedCaptureOpen=\(drumKitMatrixRenderedCaptureOpen)
        drumKitMatrixRenderedKitFXChooserVisible=\(drumKitMatrixRenderedKitFXChooserVisible)
        drumKitMatrixRenderedSaveSlotPickerVisible=\(drumKitMatrixRenderedSaveSlotPickerVisible)
        drumKitMatrixRenderedRowExpanded=\(drumKitMatrixRenderedRowExpanded)
        drumKitMatrixRenderedExpandedPartIndex=\(drumKitMatrixRenderedExpandedPartIndex)
        drumKitMatrixRenderedExpandedRowTab=\(drumKitMatrixRenderedExpandedRowTab)
        drumKitMatrixRenderedExpandedSourceMode=\(drumKitMatrixRenderedExpandedSourceMode)
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
        drumKitMatrixPatternMismatch=false
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
        selectedTrackFillEngaged=\(selectedTrackFillEngagedStatus(session: session))
        trackRandomizeSheet=\(trackRandomizeSheetState)
        selectedTrackRandomizePersisted=\(selectedTrackRandomizePersistedStatus(session: session))
        selectedTrackRandomizeLastSeed=\(selectedTrackRandomizeLastSeedStatus(session: session))
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
        masterPeak=\(max(meterState.leftPeakDBFS, meterState.rightPeakDBFS))
        masterMaxSampleDelta=\(meterState.maxSampleDelta)
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
        \(routingStressStatusLines(session: session, engineController: engineController))
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
              command["phraseDensityValue"] != nil ||
              command["phraseGlobalApplyTrackSelector"] != nil ||
              command["phraseGlobalApplySelect"] != nil ||
              command["phraseSceneSelect"] != nil ||
              command["phraseSceneViewMode"] != nil ||
              command["phraseSceneMembershipFixture"] != nil ||
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

        // WS6 capture vocabulary (row 06c): spread the tracks across the three
        // scene memberships through the normal setTrackMix path so the scenes
        // membership readout renders a non-degenerate split.
        if command["phraseSceneMembershipFixture"] == "split" {
            let cycle = TrackMixSettings.SceneMembership.allCases
            for (index, track) in session.store.tracks.enumerated() {
                var mix = track.mix
                mix.sceneMembership = cycle[index % cycle.count]
                session.setTrackMix(trackID: track.id, mix: mix)
            }
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

        // WS5 capture vocabulary (rows 10a/10b): write a density value into
        // every track's phrase cell on the selected phrase, through the
        // normal setPhraseCell path (snapshot install → revision bump — the
        // generation-affecting route).
        if let rawDensity = command["phraseDensityValue"],
           let density = Double(rawDensity),
           let densityLayer = session.store.layers.first(where: { $0.target == .macroRow("density") }) {
            let trackIDs = session.store.tracks.map(\.id)
            if !trackIDs.isEmpty {
                session.setPhraseCell(
                    .single(.scalar(min(max(density, densityLayer.minValue), densityLayer.maxValue))),
                    layerID: densityLayer.id,
                    trackIDs: trackIDs,
                    phraseID: session.store.selectedPhraseID
                )
            }
        }

        switch command["phraseGlobalApplyTrackSelector"] {
        case "open", "visible", "true":
            posts.append("global-apply-track-selector:open")
        case "close", "hidden", "false":
            posts.append("global-apply-track-selector:close")
        default:
            break
        }

        // QA: preselect the first N tracks in the global-apply scope so a
        // capture shows accent-selected cells.
        if let rawSelect = command["phraseGlobalApplySelect"],
           let count = Int(rawSelect) {
            posts.append("global-apply-select:\(count)")
        }

        // Macros | Slots view mode on the SCENES perform surface (the
        // perform-bar segmented pill from the scenes-in-phrases work).
        if let rawSceneViewMode = command["phraseSceneViewMode"],
           PhraseSceneViewMode(rawValue: rawSceneViewMode) != nil {
            posts.append("scene-view-mode:\(rawSceneViewMode)")
        }

        switch command["phraseSceneSelect"] {
        case "a", "slot-a", "open", "visible", "true":
            posts.append("scene-select:a")
        case "b", "slot-b":
            posts.append("scene-select:b")
        case "close", "hidden", "false":
            posts.append("scene-select:close")
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

    /// Drives the tracks-navigator creation flow (`TracksMatrixView`'s single
    /// `createTrackStep` sheet) from the capture harness. Mirrors the
    /// phrase-matrix command shape: navigate to the tracks page, then post a
    /// notification TracksMatrixView observes to set the flow step. The
    /// rendered visibility is reported back via .tracksMatrixRenderedVisualState.
    private static func applyTracksMatrixModalCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>
    ) {
        guard command["tracksCreateTrackModal"] != nil ||
              command["tracksAddDrumGroupModal"] != nil ||
              command["tracksAddSliceTrackModal"] != nil ||
              command["tracksTrackSoundModal"] != nil
        else { return }

        section.wrappedValue = .tracks

        var posts: [String] = []

        // The creation surfaces are STEPS of one flow sheet now, so opening
        // one closes the others by construction; the status mirrors that
        // mutually exclusive state. These vars are set authoritatively
        // here — the render round-trip then confirms the sheet actually mounted.
        switch command["tracksCreateTrackModal"] {
        case "open", "visible", "true":
            tracksCreateTrackModalVisible = true
            tracksAddDrumGroupModalVisible = false
            tracksAddSliceTrackModalVisible = false
            tracksTrackSoundModalVisible = false
            posts.append("create-track-modal:open")
        case "close", "hidden", "false":
            tracksCreateTrackModalVisible = false
            posts.append("create-track-modal:close")
        default:
            break
        }

        switch command["tracksAddDrumGroupModal"] {
        case "open", "visible", "true":
            tracksAddDrumGroupModalVisible = true
            tracksCreateTrackModalVisible = false
            tracksAddSliceTrackModalVisible = false
            tracksTrackSoundModalVisible = false
            posts.append("add-drum-group-modal:open")
        case "close", "hidden", "false":
            tracksAddDrumGroupModalVisible = false
            posts.append("add-drum-group-modal:close")
        default:
            break
        }

        switch command["tracksAddSliceTrackModal"] {
        case "open", "visible", "true":
            tracksAddSliceTrackModalVisible = true
            tracksCreateTrackModalVisible = false
            tracksAddDrumGroupModalVisible = false
            tracksTrackSoundModalVisible = false
            posts.append("add-slice-track-modal:open")
        case "close", "hidden", "false":
            tracksAddSliceTrackModalVisible = false
            posts.append("add-slice-track-modal:close")
        default:
            break
        }

        // The mono/poly at-creation sound step (Blank / Sampler / AU list).
        switch command["tracksTrackSoundModal"] {
        case "open", "visible", "true":
            tracksTrackSoundModalVisible = true
            tracksCreateTrackModalVisible = false
            tracksAddDrumGroupModalVisible = false
            tracksAddSliceTrackModalVisible = false
            posts.append("track-sound-modal:open")
        case "close", "hidden", "false":
            tracksTrackSoundModalVisible = false
            posts.append("track-sound-modal:close")
        default:
            break
        }

        // The command may arrive in the same runloop tick that switches the
        // workspace to .tracks, before TracksMatrixView has subscribed to the
        // notification. Keep the batch pending so the view drains it from
        // onAppear; live views still react via the notifications.
        pendingTracksMatrixCommands = posts
        for post in posts {
            NotificationCenter.default.post(name: .tracksMatrixVisualCommand, object: post)
        }
    }

    /// Pending tracks-matrix visual commands for a TracksMatrixView that mounts
    /// after the command was applied (workspace-switch race). Drained in onAppear.
    static var pendingTracksMatrixCommands: [String] = []

    static func drainPendingTracksMatrixCommands() -> [String] {
        let pending = pendingTracksMatrixCommands
        pendingTracksMatrixCommands = []
        return pending
    }

    /// Pending kit-matrix visual commands for a DrumKitMatrixView that mounts
    /// after the command was applied (open-kit-view / dive-in race). Drained in
    /// onAppear. Live views still react via the notification.
    static var pendingDrumKitMatrixCommands: [String] = []

    static func drainPendingDrumKitMatrixCommands() -> [String] {
        let pending = pendingDrumKitMatrixCommands
        pendingDrumKitMatrixCommands = []
        return pending
    }

    /// Generation counter for kit-matrix row switches. Bumped whenever a row
    /// re-opens the kit view (`drumPartHeaderOpenKitView=true`). The async
    /// re-post Tasks below capture the epoch at schedule time and abandon any
    /// further posts once a newer row has started — otherwise a prior row's
    /// late, fire-and-forget posts (e.g. 29d's `open-kit-fx-chooser` re-asserts,
    /// which run for ~1.5s) land on the persisted, live matrix view AFTER the
    /// next row's synchronous close ran, resurrecting a sheet the new row closed
    /// (29e/29f/29g showing a stray Add Kit FX chooser). Clearing the pending
    /// drain queue alone does not stop these — they arrive via the
    /// `.drumKitMatrixVisualCommand` notification the live view subscribes to.
    static var drumKitMatrixCommandEpoch: Int = 0

    /// Pending track-source-editor visual commands (e.g. `select-tab:sound`) for
    /// a TrackSourceEditorView that mounts after the command was applied — e.g.
    /// the sound tab post racing the dive-in part-editor mount. Drained in
    /// onAppear; live views still react via the notification.
    static var pendingTrackSourceEditorCommands: [String] = []
    static var trackRandomizeSheetState = "closed"

    static func drainPendingTrackSourceEditorCommands() -> [String] {
        let pending = pendingTrackSourceEditorCommands
        pendingTrackSourceEditorCommands = []
        return pending
    }

    /// Append a pending editor command once, preserving arrival order for the
    /// onAppear drain (select-tab first, then stage selection).
    private static func queuePendingTrackSourceEditorCommand(_ command: String) {
        guard !pendingTrackSourceEditorCommands.contains(command) else { return }
        pendingTrackSourceEditorCommands.append(command)
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
        // Comma-separated sequence of kit visual commands the view already
        // understands (e.g. `open-capture,history-save-open`). Posted in order
        // because the command-file payload is a dictionary — a single
        // `drumKitMatrixCommand` key cannot carry two ordered commands. The
        // first command repeats (mount safety — the matrix view may mount after
        // the open-kit-view navigation tick); the rest are posted once each
        // after a settle delay so a later command (e.g. row-tab-sound) is not
        // clobbered by a re-post of an earlier one (e.g. expand-part:0, which
        // resets the row tab to its default on every apply).
        if let rawSequence = command["drumKitMatrixCommands"] {
            let tokens = rawSequence
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && DrumKitVisualCommand(rawValue: $0) != nil }
            // Stash the WHOLE ordered sequence for the onAppear drain: when the
            // kit matrix view (and its expanded-row detail panel) mounts after
            // the open-kit-view tick, the live posts below can be lost
            // (29g expand-part:0,row-tab-sound race). The drain replays them in
            // order on mount.
            if !tokens.isEmpty {
                pendingDrumKitMatrixCommands.append(contentsOf: tokens)
            }
            if let first = tokens.first {
                postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: first)
            }
            if tokens.count > 1 {
                let rest = Array(tokens.dropFirst())
                let last = tokens.last
                // Capture the epoch this row scheduled under. If a later row
                // re-opens the kit view it bumps the epoch; we then abandon any
                // remaining posts so they don't land on the next row's live view
                // (e.g. 29d's late `open-kit-fx-chooser` re-asserts re-opening
                // the chooser after 29e closed it).
                let epoch = drumKitMatrixCommandEpoch
                Task { @MainActor in
                    // Wait out the first command's repeated re-posts (~600ms).
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard epoch == drumKitMatrixCommandEpoch else { return }
                    for token in rest {
                        NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: token)
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard epoch == drumKitMatrixCommandEpoch else { return }
                    }
                    // Re-assert the FINAL command (e.g. row-tab-sound) several
                    // more times, late: when the kit matrix / expanded-row mounts
                    // after the open-kit-view tick, an in-flight expand-part:N
                    // re-post can reset the row tab to its default AFTER the first
                    // row-tab post, so 29g flips between sound and stepsClip
                    // standalone. These late re-asserts let the tab win
                    // deterministically (paired with the longer 29g settle).
                    if let last {
                        for delay in [200, 350, 500, 700] as [UInt64] {
                            try? await Task.sleep(nanoseconds: delay * 1_000_000)
                            guard epoch == drumKitMatrixCommandEpoch else { return }
                            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: last)
                        }
                    }
                }
            }
        }

        guard command["drumKitMatrixCommand"] != nil ||
              command["drumKitMatrixCommands"] != nil ||
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
            // The kit matrix view mounts after the open-kit-view navigation
            // tick, so a single live post races the mount and the routing sheet
            // never opens (31-drum-kit-routing). Stash for the onAppear drain
            // and re-post so it lands whether the view is already up or not.
            pendingDrumKitMatrixCommands.append("open-routing")
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: "open-routing")
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
            } else if DrumKitVisualCommand(rawValue: rawCommand) != nil {
                // Generic pass-through for the kit-matrix visual commands the
                // view already understands (tab-fx/tab-macros/tab-mixer,
                // open-capture, history-save-open, open-kit-fx-chooser,
                // expand-part:N, row-tab-*, etc.). Posted repeatedly because the
                // matrix view may mount after the open-kit-view navigation tick.
                pendingDrumKitMatrixCommands.append(rawCommand)
                postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: rawCommand)
            }
        case nil:
            break
        }

        // Matrix-wide step layer (steps / velocity / chance). Posted
        // repeatedly because the matrix view may mount after open-kit-view.
        if let rawLayer = command["drumKitMatrixLayer"],
           DrumKitMatrixLayer(rawValue: rawLayer) != nil {
            let visualCommand = "layer:\(rawLayer)"
            pendingDrumKitMatrixCommands.append(visualCommand)
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: visualCommand)
        }

        // Group pattern row selection (1-based slot number in the command).
        if let rawPattern = command["drumKitMatrixPattern"],
           let slotNumber = Int(rawPattern),
           (1...TrackPatternBank.slotCount).contains(slotNumber) {
            let visualCommand = "pattern:\(slotNumber - 1)"
            pendingDrumKitMatrixCommands.append(visualCommand)
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: visualCommand)
        }

        switch command["drumKitMatrixTemplateChooser"] {
        case "open", "visible", "true":
            pendingDrumKitMatrixCommands.append("open-template-chooser")
            postRepeatedVisualCommand(name: .drumKitMatrixVisualCommand, object: "open-template-chooser")
        case "close", "hidden", "false":
            pendingDrumKitMatrixCommands.append("close-template-chooser")
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-template-chooser")
        default:
            break
        }

        if let rawMembership = command["drumKitSceneMembership"],
           let membership = TrackMixSettings.SceneMembership(rawValue: rawMembership),
           let model = currentDrumKitMatrixModel(session: session) {
            let memberIDs = Set(model.rows.map(\.memberID))
            for track in session.store.tracks where memberIDs.contains(track.id) {
                var mix = track.mix
                mix.sceneMembership = membership
                session.setTrackMix(trackID: track.id, mix: mix)
            }
        }

        if let mutation = command["drumKitMatrixMutation"] {
            applyDrumKitMatrixMutation(mutation, session: session)
        }
        if let routingState = command["drumGroupRoutingEditorState"] {
            // Normalise the shorthand mode values used in the QA table to the
            // command strings the routing editor understands (it expects
            // routing-per-note / routing-per-channel / routing-individual).
            let normalized: String = {
                switch routingState {
                case "channel", "per-channel", "perChannel": return "per-channel"
                case "note", "per-note", "perNote": return "per-note"
                case "individual": return "individual"
                default: return routingState
                }
            }()
            // The routing editor sheet mounts after the kit matrix, so a single
            // live post races its subscription. Re-post so the mode lands once
            // the sheet is up.
            postRepeatedVisualCommand(
                name: .drumGroupRoutingEditorVisualCommand,
                object: "routing-\(normalized)"
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

        // Kit-first: a drum-group track ALWAYS shows the kit matrix (per-part
        // editing lives inline in the matrix's expanded-row accordion), so
        // reflect the matrix as the visible view and seed the model-backed
        // status keys whenever a kit fixture is selected.
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
            // Reset any kit sheets/sub-surfaces a PRIOR row left open on the
            // live (persisted) matrix view — `open-kit-view` does not always
            // recreate the view, so its @State (FX chooser, capture, expanded
            // row) can otherwise bleed into this row's screenshot.
            // Reset any pending kit-matrix drain a PRIOR row queued so its
            // stale open-routing / row-tab does not bleed into this row's
            // freshly-mounted matrix. The current row's kit commands are
            // appended after this reset (applyDrumKitMatrixCommand runs later).
            pendingDrumKitMatrixCommands = []
            // Invalidate any still-in-flight async re-post Tasks a PRIOR row
            // scheduled (29d's `open-kit-fx-chooser` re-asserts run for ~1.5s
            // and would otherwise re-open the chooser AFTER the close below).
            // applyDrumKitMatrixCommand (called later this apply) captures the
            // bumped epoch for THIS row's own re-posts.
            drumKitMatrixCommandEpoch += 1
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-routing")
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-kit-fx-chooser")
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "close-capture")
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "collapse-row")
            NotificationCenter.default.post(name: .drumKitMatrixVisualCommand, object: "tab-matrix")
            drumKitMatrixRoutingEditorVisualState = false
            drumKitMatrixRenderedRoutingEditorState = false
            drumGroupRoutingEditorRenderedState = false
            drumGroupRoutingEditorMode = "none"
            drumKitMatrixRenderedKitFXChooserVisible = false
            drumKitMatrixRenderedCaptureOpen = false
            drumKitMatrixRenderedSaveSlotPickerVisible = false
            drumKitMatrixRenderedRowExpanded = false
            drumKitMatrixRenderedExpandedRowTab = "none"
            drumKitMatrixRenderedExpandedSourceMode = "none"
            drumKitMatrixRenderedKitTab = "none"
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

    /// Drives the Steps/Clip/Sound/FX/Macros/Mixer tab on the track editor
    /// without coordinate clicks. Posts repeatedly because the editor view may
    /// not exist yet right after the section switch. The ROUTING tab is
    /// setup-only; the editor's own guard ignores a `routing` selection while
    /// the workspace is in perform mode.
    /// Drives the Sound tab's SOUND SOURCE well into a chosen destination
    /// state. `empty` clears the destination so the accent "Add Sound Source"
    /// add card renders (TrackDestinationEditor.unsetState).
    private static func applyTrackSoundSourceCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard let rawState = command["trackSoundSource"] else { return }
        section.wrappedValue = .track
        let trackID = session.store.selectedTrackID
        switch rawState {
        case "empty", "none", "unset":
            session.setEditedDestination(.none, for: trackID)
        case "sample", "sampler":
            if let sample = AudioSampleLibrary.shared.firstSample(in: .kick)
                ?? AudioSampleLibrary.shared.samples.first {
                session.setEditedDestination(.sample(sampleID: sample.id, settings: .default), for: trackID)
            }
        default:
            break
        }
    }

    private static func selectedTrackSoundDestinationKind(session: SequencerDocumentSession) -> String {
        switch session.store.resolvedDestination(for: session.store.selectedTrackID) {
        case .none: return "none"
        case .midi: return "midi"
        case .auInstrument: return "auInstrument"
        case .internalSampler: return "internalSampler"
        case .sample: return "sample"
        case .slicer: return "slicer"
        case .inheritGroup: return "inheritGroup"
        }
    }

    private static func trackSourceAddSourceVisible(
        selectedPattern: TrackPatternSlot,
        session: SequencerDocumentSession
    ) -> String {
        switch selectedPattern.sourceRef.mode {
        case .clip:
            return session.store.clipEntry(id: selectedPattern.sourceRef.clipID) == nil ? "true" : "false"
        case .generator:
            return session.store.generatorEntry(id: selectedPattern.sourceRef.generatorID) == nil ? "true" : "false"
        }
    }

    private static func applyTrackSourceTabCommand(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        // QA: select a step in the Steps/Clip grid so the step-edit rotary
        // cluster (StepLayerRotaryRow / StepLayerRotaryDial) renders in
        // ClipContentPreview. Posted repeatedly because the editor may mount
        // after the section switch.
        if let rawStep = command["trackSelectStep"], let step = Int(rawStep), step >= 0 {
            section.wrappedValue = .track
            trackSourceTabState = "steps-clip"
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-step:\(step)")
        }

        if let rawLayer = command["trackClipLayer"],
           ClipEditorLayer(rawValue: rawLayer) != nil {
            section.wrappedValue = .track
            trackSourceTabState = "steps-clip"
            trackClipLayerState = rawLayer
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "clip-layer:\(rawLayer)")
        }

        switch command["trackClipLayerSwitcher"] {
        case "open", "true", "on":
            section.wrappedValue = .track
            trackSourceTabState = "steps-clip"
            trackClipLayerSwitcherState = "open"
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "clip-layer-switcher:open")
        case "close", "closed", "false", "off":
            trackClipLayerSwitcherState = "closed"
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "clip-layer-switcher:close")
        default:
            break
        }

        // WS4 generator-editor vocabulary: drive the TRIGGER|PITCH stage tab,
        // the header mode switch (stable-identity switchGeneratorKind), and
        // the FOLLOWING chord sidechain from capture rows 22e-22h.
        if let rawStage = command["trackGeneratorStage"],
           ["trigger", "pitch"].contains(rawStage) {
            section.wrappedValue = .track
            trackSourceTabState = "source"
            trackGeneratorStageState = rawStage
            queuePendingTrackSourceEditorCommand("select-tab:source")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:source")
            // The stage view mounts inside the source tab; the repeated posts
            // (now / +250ms / +600ms) cover the late mount like 22c's
            // clip-layer command does.
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "generator-stage:\(rawStage)")
        }

        if let rawKind = command["trackGeneratorKind"],
           let kind = GeneratorKind(rawValue: rawKind),
           let generatorID = session.store.selectedPattern(for: session.store.selectedTrackID).sourceRef.generatorID {
            section.wrappedValue = .track
            trackSourceTabState = "source"
            trackGeneratorKindState = rawKind
            _ = session.switchGeneratorKind(id: generatorID, to: kind)
            queuePendingTrackSourceEditorCommand("select-tab:source")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:source")
        }

        if let rawFollowing = command["trackGeneratorFollowing"],
           let generatorID = session.store.selectedPattern(for: session.store.selectedTrackID).sourceRef.generatorID {
            let sidechain: HarmonicSidechainSource
            switch rawFollowing {
            case "chord", "project", "projectChordContext":
                sidechain = .projectChordContext
            default:
                sidechain = .none
            }
            section.wrappedValue = .track
            trackSourceTabState = "source"
            _ = session.mutateGenerator(id: generatorID) { entry in
                entry.params = entry.params.withFirstPitchSidechain(sidechain)
            }
            queuePendingTrackSourceEditorCommand("select-tab:source")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:source")
        }

        // WS6 capture vocabulary (row 22ba): set the selected track's scene
        // membership through the normal setTrackMix path and land on the mixer
        // tab where the routing selector renders.
        if let rawMembership = command["trackSceneMembership"],
           let membership = TrackMixSettings.SceneMembership(rawValue: rawMembership) {
            section.wrappedValue = .track
            trackSourceTabState = "mixer"
            var mix = session.store.selectedTrack.mix
            mix.sceneMembership = membership
            session.setTrackMix(trackID: session.store.selectedTrackID, mix: mix)
            queuePendingTrackSourceEditorCommand("select-tab:mixer")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:mixer")
        }

        guard let rawTab = command["trackSourceTab"],
              TrackSourceEditorTab.tab(forVisualCommand: rawTab) != nil
        else { return }

        section.wrappedValue = .track
        trackSourceTabState = rawTab
        // Stash for the onAppear drain: the source editor may mount AFTER a
        // drum-part dive-in, so a live post can be lost (28a/29g race).
        let tabCommand = "select-tab:\(rawTab)"
        if !pendingTrackSourceEditorCommands.contains(tabCommand) {
            pendingTrackSourceEditorCommands.insert(tabCommand, at: 0)
        }
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
              command["slicerLayer"] != nil ||
              command["slicerLayerSwitcher"] != nil ||
              command["slicerSelectStep"] != nil ||
              command["sliceSourceModal"] != nil
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

        switch command["slicerLayerSwitcher"] {
        case "open", "true", "on":
            slicerLayerSwitcherState = "open"
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "layer-switcher:open")
        case "close", "closed", "false", "off":
            slicerLayerSwitcherState = "closed"
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "layer-switcher:close")
        default:
            break
        }

        // QA: select a slicer step so the step-edit rotary cluster renders.
        // Posted repeatedly because the slice workspace view may mount after the
        // section switch / fixture population.
        if let rawStep = command["slicerSelectStep"],
           let step = Int(rawStep), step >= 0 {
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "selectStep:\(step)")
        }

        if let rawTab = command["slicerTab"],
           ["steps", "source", "slice", "fx", "macros", "mixer"].contains(rawTab) {
            slicerTabState = rawTab
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "tab:\(rawTab)")
        }

        switch command["sliceSourceModal"] {
        case "open", "visible", "true":
            sliceSourceModalState = "open"
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "sliceModal:open")
        case "close", "hidden", "false":
            sliceSourceModalState = "closed"
            postRepeatedVisualCommand(name: .sliceTrackWorkspaceVisualCommand, object: "sliceModal:close")
        default:
            break
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
        guard command["scenesMode"] != nil ||
              command["sceneEditorFixture"] != nil ||
              command["scenesAddFXModal"] != nil ||
              command["scenesSelectInsert"] != nil
        else { return }

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
           ["empty", "content", "browse-content"].contains(rawFixture) {
            session.workspaceMode = .setup
            sceneEditorFixtureState = rawFixture
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "mode:\(ScenesWorkspaceMode.browseEdit.rawValue)")
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "fixture:\(rawFixture)")
        }

        // QA: select an insert (e.g. the bitcrusher at index 1 in the content
        // fixture) so its NativeInsertParameterEditor renders. The fixture
        // command (above) re-posts for ~600ms and resets the selected insert to
        // the filter on each apply, so this MUST land after those settle —
        // delay the posts past the fixture's repeat window, then re-post so the
        // bitcrusher selection sticks.
        if let rawIndex = command["scenesSelectInsert"],
           let index = Int(rawIndex), index >= 0 {
            scenesSelectedInsertIndex = "\(index)"
            Task { @MainActor in
                // Land just after the fixture's last repeat (~600ms) but before
                // the capture settle (~800ms after the final payload write).
                try? await Task.sleep(nanoseconds: 650_000_000)
                NotificationCenter.default.post(name: .scenesWorkspaceVisualCommand, object: "selectInsert:\(index)")
            }
        }

        // QA: drive the add-FX (add-insert) picker sheet for capture coverage.
        switch command["scenesAddFXModal"] {
        case "open", "visible", "true":
            scenesAddFXModalState = "open"
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "addFX:open")
        case "close", "hidden", "false":
            scenesAddFXModalState = "closed"
            postRepeatedVisualCommand(name: .scenesWorkspaceVisualCommand, object: "addFX:close")
        default:
            break
        }
    }

    private static func postRepeatedVisualCommand(name: Notification.Name, object: String) {
        NotificationCenter.default.post(name: name, object: object)
        // Kit-matrix re-posts are scoped to the row that scheduled them: a later
        // row that re-opens the kit view bumps the epoch, after which the
        // remaining async posts are abandoned so a prior row's command (e.g. the
        // first token of 29d's `tab-fx,open-kit-fx-chooser`) cannot land on the
        // next row's persisted, live matrix view. Other surfaces are unaffected.
        let isKitMatrix = (name == .drumKitMatrixVisualCommand)
        let epoch = drumKitMatrixCommandEpoch
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if isKitMatrix, epoch != drumKitMatrixCommandEpoch { return }
            NotificationCenter.default.post(name: name, object: object)
            try? await Task.sleep(nanoseconds: 350_000_000)
            if isKitMatrix, epoch != drumKitMatrixCommandEpoch { return }
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
              command["trackFillEngaged"] != nil ||
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

        switch command["trackFillEngaged"] {
        case "on", "active", "true":
            setSelectedTrackFillEngaged(true, session: session)
        case "off", "clear", "inactive", "false":
            setSelectedTrackFillEngaged(false, session: session)
        default:
            break
        }
    }

    private static func applyTrackRandomizeFixture(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession
    ) {
        guard command["trackRandomizeSheet"] != nil ||
              command["trackRandomizeRoll"] != nil
        else { return }

        section.wrappedValue = .track
        applyTrackFillSource("clip", session: session)
        trackSourceTabState = "source"
        pendingTrackSourceEditorCommands = ["select-tab:source"]
        postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "select-tab:source")

        switch command["trackRandomizeSheet"] {
        case "open", "true", "on":
            trackRandomizeSheetState = "open"
            pendingTrackSourceEditorCommands.append("randomize-sheet:open")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "randomize-sheet:open")
        case "close", "closed", "false", "off":
            trackRandomizeSheetState = "closed"
            pendingTrackSourceEditorCommands.append("randomize-sheet:close")
            postRepeatedVisualCommand(name: .trackSourceEditorVisualCommand, object: "randomize-sheet:close")
        default:
            break
        }

        switch command["trackRandomizeRoll"] {
        case "on", "roll", "true":
            let settings = selectedTrackRandomizeSettings(session: session)
            let seed = deterministicTrackRandomizeSeed(session: session)
            _ = session.bakeRandomizedSelectedClip(
                trackID: session.store.selectedTrackID,
                settings: settings,
                seed: seed
            )
            trackRandomizeSheetState = "closed"
        default:
            break
        }
    }

    private static func setSelectedTrackFillEngaged(_ engaged: Bool, session: SequencerDocumentSession) {
        guard let fillLayer = session.store.layers.first(where: {
            if case .macroRow("fill-flag") = $0.target {
                return true
            }
            return false
        }) else { return }

        session.setPhraseCell(
            .single(.bool(engaged)),
            layerID: fillLayer.id,
            trackIDs: [session.store.selectedTrackID],
            phraseID: session.store.selectedPhraseID
        )
    }

    private static func selectedTrackFillEngagedStatus(session: SequencerDocumentSession) -> Bool {
        guard let fillLayer = session.store.layers.first(where: {
            if case .macroRow("fill-flag") = $0.target {
                return true
            }
            return false
        }) else { return false }

        let value = session.store.selectedPhrase.resolvedValue(
            for: fillLayer,
            trackID: session.store.selectedTrackID,
            stepIndex: 0
        )
        if case let .bool(engaged) = value {
            return engaged
        }
        return false
    }

    private static func selectedTrackRandomizeSettings(session: SequencerDocumentSession) -> ClipRandomizeSettings {
        let pattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        guard let clipID = pattern.sourceRef.clipID,
              let settings = session.store.clipEntry(id: clipID)?.randomizeSettings
        else {
            return ClipRandomizeSettings()
        }
        return settings
    }

    private static func selectedTrackRandomizePersistedStatus(session: SequencerDocumentSession) -> Bool {
        let pattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        guard let clipID = pattern.sourceRef.clipID else { return false }
        return session.store.clipEntry(id: clipID)?.randomizeSettings != nil
    }

    private static func selectedTrackRandomizeLastSeedStatus(session: SequencerDocumentSession) -> String {
        let pattern = session.store.selectedPattern(for: session.store.selectedTrackID)
        guard let clipID = pattern.sourceRef.clipID,
              let lastSeed = session.store.clipEntry(id: clipID)?.randomizeSettings?.lastSeed
        else {
            return "none"
        }
        return "\(lastSeed)"
    }

    private static func deterministicTrackRandomizeSeed(session: SequencerDocumentSession) -> UInt64 {
        let slotIndex = session.store.selectedPatternIndex(for: session.store.selectedTrackID)
        return 0x5EED_0000 ^ session.revision ^ UInt64(slotIndex &+ 1)
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
              let window = commandChannelWindow
                ?? NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first(where: { $0.isVisible })
                ?? NSApplication.shared.windows.first
        else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
        let trackID = ensureSelectedAudioInputTrack(section: section, session: session)
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

        // The QA rows keep the transport stopped (`transport=stop`), which
        // arms the post-stop tick suppression — but the arm/record states
        // below are driven by manually pumped `processTick` calls. Lift the
        // suppression so those fixture ticks are processed (otherwise
        // armed -> recording never fires and row 26 times out).
        engineController.resumeManualTickProcessingForFixtures()

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

private extension GeneratorParams {
    /// QA vocabulary helper (row 22h): set the FIRST pitch lane's harmonic
    /// sidechain in place — the chord sidechain is a pitch-pool filter only,
    /// so this never touches the trigger stage.
    func withFirstPitchSidechain(_ sidechain: HarmonicSidechainSource) -> GeneratorParams {
        switch self {
        case let .mono(trigger, pitch, shape):
            return .mono(
                trigger: trigger,
                pitch: .native(PitchStage(algo: pitch.pitchStage.algo, harmonicSidechain: sidechain)),
                shape: shape
            )
        case let .poly(trigger, pitches, shape):
            guard !pitches.isEmpty else {
                return self
            }
            var nextPitches = pitches
            nextPitches[0] = .native(PitchStage(algo: nextPitches[0].pitchStage.algo, harmonicSidechain: sidechain))
            return .poly(trigger: trigger, pitches: nextPitches, shape: shape)
        default:
            return self
        }
    }
}
