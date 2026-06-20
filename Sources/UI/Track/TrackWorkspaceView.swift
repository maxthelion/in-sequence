import AVFoundation
import SwiftUI

struct TrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var editingTrackID: UUID?
    @State private var stepGridWorkspaceModel = TrackStepGridWorkspaceModel()
    @State private var draftTrackName = ""
    // Slice 6a "kit view first": a drum-group track now lands on the kit matrix
    // by default. The single-part editor is the dive-in, reached by selecting a
    // part from the matrix; `divedInPartID` records which part the user drilled
    // into (matched against the currently selected track). When `nil`, a drum
    // track shows the matrix; when it equals the selected drum part, that part's
    // editor is shown. Non-drum tracks ignore this entirely.
    @State private var divedInPartID: UUID?
    @FocusState private var trackNameFieldFocused: Bool

    private var track: StepSequenceTrack {
        session.store.selectedTrack
    }

    private var drumPartHeaderModel: DrumPartWorkspaceHeaderModel? {
        DrumPartWorkspaceHeaderModel(
            selectedTrack: track,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups
        )
    }

    /// The kit matrix navigation state to show, or `nil` when the per-part
    /// editor should be shown instead. A drum-group track defaults to the
    /// matrix (kit-first) and only shows the part editor once the user has
    /// dived into the currently selected part.
    private var kitNavigationState: DrumKitWorkspaceNavigationState? {
        guard let headerModel = drumPartHeaderModel else { return nil }
        if divedInPartID == headerModel.currentPartID {
            return nil
        }
        return DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: headerModel)
    }

    private var outboundRouteCount: Int {
        session.store.routesSourced(from: track.id).count
    }

    private var sourceAccent: Color {
        switch track.trackType {
        case .monoMelodic, .polyMelodic:
            return StudioTheme.cyan
        case .slice:
            return StudioTheme.violet
        case .audioInput:
            return StudioTheme.success
        }
    }

    private var isEditingSelectedTrackName: Bool {
        editingTrackID == track.id
    }

    var body: some View {
        workspaceContent
            .onChange(of: isEditingSelectedTrackName) {
                if isEditingSelectedTrackName {
                    trackNameFieldFocused = true
                }
            }
            .onChange(of: track.id) {
                if let editingTrackID, editingTrackID != track.id {
                    self.editingTrackID = nil
                    draftTrackName = ""
                }
                // Selecting a different track resets the dive-in: a newly opened
                // drum track lands on the kit matrix (kit-first), and a non-drum
                // track is unaffected. We only keep the dive-in when the matrix
                // itself drilled into a specific part (handled in onSelectPart).
                if divedInPartID != track.id {
                    divedInPartID = nil
                }
                stepGridWorkspaceModel.reset()
            }
            .onChange(of: kitNavigationState) {
                if kitNavigationState == nil {
                    NotificationCenter.default.post(
                        name: .drumKitMatrixRenderedVisualState,
                        object: nil,
                        userInfo: [
                            "visible": false,
                            "routingEditorVisible": false,
                            "displayStepCount": 16,
                            "groupName": "none",
                            "memberCount": 0,
                        ]
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .drumPartWorkspaceHeaderVisualCommand)) { notification in
                guard let command = notification.object as? String else { return }

                switch command {
                case "rename-on":
                    editingTrackID = track.id
                    draftTrackName = track.name
                    trackNameFieldFocused = true
                case "rename-off":
                    editingTrackID = nil
                    draftTrackName = ""
                    trackNameFieldFocused = false
                case "open-kit-view":
                    // Kit-first: the matrix is the default home. From the
                    // part-editor dive-in this dives back out to the matrix by
                    // clearing the dived-in part.
                    divedInPartID = nil
                case "dive-into-part":
                    // Drill from the kit matrix into the currently selected
                    // part's editor (the dive-in). Mirrors selecting a part row.
                    if let drumPartHeaderModel {
                        divedInPartID = drumPartHeaderModel.currentPartID
                    }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if let kitNavigationState {
            DrumKitMatrixView(
                document: $document,
                navigationState: kitNavigationState,
                // Kit-first: the matrix is the track editor's home, so there is
                // no "back" target above it — the back affordance is hidden.
                showsBackButton: false,
                onBack: {},
                onSelectPart: { partID in
                    // Dive into the selected part: keep it as the selected track
                    // and remember the dive-in so its part editor is shown.
                    session.setSelectedTrackID(partID)
                    divedInPartID = partID
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 18) {
                trackHeader

                if track.trackType == .audioInput {
                    AudioInputRuntimePanel(
                        document: $document,
                        track: track,
                        runtime: engineController.audioInputRuntime(for: track.id),
                        accent: sourceAccent
                    )
                } else if track.trackType == .slice {
                    SliceTrackWorkspaceView(
                        document: $document,
                        accent: sourceAccent,
                        stepGridWorkspaceModel: stepGridWorkspaceModel
                    )
                } else {
                    // The permanent right-hand destination column is gone: the
                    // destination + sends path now lives in the ROUTING tab of
                    // the track editor (wireframe SS8), so the editor — and the
                    // surfaces touched constantly — get the full width.
                    TrackSourceEditorView(
                        document: $document,
                        accent: sourceAccent,
                        stepGridWorkspaceModel: stepGridWorkspaceModel
                    )
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)

                    // Cross-track project routes remain a distinct concern from
                    // the audio destination; surface them full-width only when
                    // the track actually sources outbound routes.
                    if outboundRouteCount > 0 {
                        StudioPanel(
                            title: "Project Routes",
                            eyebrow: "\(outboundRouteCount) outbound project route\(outboundRouteCount == 1 ? "" : "s")",
                            accent: StudioTheme.violet
                        ) {
                            RoutesListView(document: $document)
                        }
                    }
                }
            }
            .padding(StudioMetrics.Spacing.section)
        }
    }

    @ViewBuilder
    private var trackHeader: some View {
        if let drumPartHeaderModel {
            DrumPartWorkspaceHeader(
                model: drumPartHeaderModel,
                title: { trackNameEditor },
                onSelectPart: { session.setSelectedTrackID($0) },
                onOpenKitView: {
                    // Dive back out of the part editor to the kit matrix home.
                    divedInPartID = nil
                }
            )
        } else {
            defaultTrackHeader
        }
    }

    private var defaultTrackHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                trackNameEditor
            }

            Spacer()

            if track.trackType == .monoMelodic || track.trackType == .polyMelodic {
                TrackFillPreviewControl(
                    presentation: fillPreviewPresentation,
                    accent: StudioTheme.amber,
                    toggle: toggleFillPreview
                )
            }
        }
    }

    private var fillPreviewPresentation: TrackFillPreviewHeaderPresentation {
        let pattern = session.store.selectedPattern(for: track.id)
        return TrackFillPreviewHeaderPresentation.resolve(
            sourceMode: pattern.sourceRef.mode,
            currentClip: session.store.clipEntry(id: pattern.sourceRef.clipID),
            selectedTrackID: track.id,
            previewState: session.trackFillPreviewState
        )
    }

    private func toggleFillPreview() {
        guard fillPreviewPresentation.isEnabled else {
            return
        }
        if fillPreviewPresentation.isActive {
            session.disableTrackFillPreview(for: track.id)
        } else {
            session.enableSelectedTrackFillPreview()
        }
    }

    @ViewBuilder
    private var trackNameEditor: some View {
        let nameStyle: StudioTypography = (track.trackType == .audioInput || track.trackType == .slice) ? .title : .display
        if isEditingSelectedTrackName {
            TextField("Track Name", text: $draftTrackName)
                .textFieldStyle(.roundedBorder)
                .focused($trackNameFieldFocused)
                .studioText(nameStyle)
                .onSubmit {
                    commitTrackName()
                }
        } else {
            Text(track.name)
                .studioText(nameStyle)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) {
                    editingTrackID = track.id
                    draftTrackName = track.name
                }
        }
    }

    private func commitTrackName() {
        guard let editingTrackID else {
            draftTrackName = ""
            return
        }
        let trimmed = draftTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            session.mutateTrack(id: editingTrackID) { track in
                track.name = trimmed
            }
        }
        self.editingTrackID = nil
        draftTrackName = ""
    }
}

struct DrumKitWorkspaceNavigationState: Equatable {
    var groupID: TrackGroupID
    var originatingPartID: UUID

    /// Slice 6a "kit view first": a drum-group/kit track opens directly on the
    /// kit matrix (all parts together), with the per-part editor as the
    /// dive-in. This returns the matrix navigation state a freshly opened drum
    /// track should default into, or `nil` for a non-drum track (which keeps
    /// its single-source editor and is unaffected).
    static func defaultForOpening(
        headerModel: DrumPartWorkspaceHeaderModel?
    ) -> DrumKitWorkspaceNavigationState? {
        guard let headerModel else { return nil }
        return DrumKitWorkspaceNavigationState(
            groupID: headerModel.groupID,
            originatingPartID: headerModel.currentPartID
        )
    }
}

struct DrumPartWorkspaceHeaderModel: Equatable {
    var groupID: TrackGroupID
    var groupName: String
    var groupColorHex: String
    var currentPartID: UUID
    var currentPartName: String
    var currentIndex: Int
    var memberCount: Int
    var previousPartID: UUID?
    var nextPartID: UUID?

    var positionLabel: String {
        "\(currentIndex + 1) of \(memberCount)"
    }

    init?(
        selectedTrack: StepSequenceTrack,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) {
        guard let groupID = selectedTrack.groupID,
              let group = trackGroups.first(where: { $0.id == groupID })
        else {
            return nil
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let orderedMembers = group.memberIDs.compactMap { tracksByID[$0] }
        guard let selectedIndex = orderedMembers.firstIndex(where: { $0.id == selectedTrack.id }) else {
            return nil
        }

        self.groupID = group.id
        groupName = group.name
        groupColorHex = group.color
        currentPartID = selectedTrack.id
        currentPartName = selectedTrack.name
        currentIndex = selectedIndex
        memberCount = orderedMembers.count
        previousPartID = selectedIndex > 0 ? orderedMembers[selectedIndex - 1].id : nil
        nextPartID = selectedIndex < orderedMembers.count - 1 ? orderedMembers[selectedIndex + 1].id : nil
    }
}

private struct DrumPartWorkspaceHeader<Title: View>: View {
    let model: DrumPartWorkspaceHeaderModel
    @ViewBuilder let title: () -> Title
    let onSelectPart: (UUID) -> Void
    let onOpenKitView: () -> Void

    private var accent: Color {
        Color(hex: model.groupColorHex) ?? StudioTheme.success
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                StudioCircleIconButton(
                    systemName: "chevron.left",
                    size: StudioMetrics.ControlSize.large,
                    isEnabled: model.previousPartID != nil,
                    help: "Previous Part"
                ) {
                    if let targetID = model.previousPartID {
                        onSelectPart(targetID)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    title()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(model.positionLabel)
                        .studioText(.eyebrowBold)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                StudioCircleIconButton(
                    systemName: "chevron.right",
                    size: StudioMetrics.ControlSize.large,
                    isEnabled: model.nextPartID != nil,
                    help: "Next Part"
                ) {
                    if let targetID = model.nextPartID {
                        onSelectPart(targetID)
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accent)
                            .frame(width: 9, height: 9)

                        Text("Kit: \(model.groupName)")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 220, alignment: .trailing)

                    Button {
                        onOpenKitView()
                    } label: {
                        Label("Back to Kit", systemImage: "square.grid.3x3")
                            .studioText(.labelBold)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(StudioTheme.background)
                    .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .help("Dive back out to the kit matrix from \(model.currentPartName)")
                }
                .frame(maxWidth: 240, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(accent)
                .frame(height: 3)
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
    }

}

extension Notification.Name {
    static let drumPartWorkspaceHeaderVisualCommand = Notification.Name("SequencerAIDrumPartWorkspaceHeaderVisualCommand")
    static let drumKitMatrixVisualCommand = Notification.Name("SequencerAIDrumKitMatrixVisualCommand")
    static let drumKitMatrixRenderedVisualState = Notification.Name("SequencerAIDrumKitMatrixRenderedVisualState")
    /// Posted (object: TrackGroupID) when the kit-page Perform header button is
    /// pressed. The scoped phrase-perform surface is a later slice; this lets
    /// QA observe the intent for now (AC13/AC22 header wiring).
    static let drumKitPerformRequested = Notification.Name("SequencerAIDrumKitPerformRequested")
    /// Posted (object: UUID track id) when a single-track detail Perform header
    /// button is pressed (AC22). Consumed by the coordinator to enter the
    /// reused tracks-perform surface scoped to that one track.
    static let trackPerformRequested = Notification.Name("SequencerAITrackPerformRequested")
    static let drumGroupRoutingEditorVisualCommand = Notification.Name("SequencerAIDrumGroupRoutingEditorVisualCommand")
    static let drumGroupRoutingEditorRenderedVisualState = Notification.Name("SequencerAIDrumGroupRoutingEditorRenderedVisualState")
    static let phraseMatrixVisualCommand = Notification.Name("SequencerAIPhraseMatrixVisualCommand")
    static let phraseMatrixRenderedVisualState = Notification.Name("SequencerAIPhraseMatrixRenderedVisualState")
    static let trackSourceEditorVisualCommand = Notification.Name("SequencerAITrackSourceEditorVisualCommand")
    static let sliceTrackWorkspaceVisualCommand = Notification.Name("SequencerAISliceTrackWorkspaceVisualCommand")
    static let audioInputTrackWorkspaceVisualCommand = Notification.Name("SequencerAIAudioInputTrackWorkspaceVisualCommand")
    static let workspaceDetailVisualCommand = Notification.Name("SequencerAIWorkspaceDetailVisualCommand")
    static let scenesWorkspaceVisualCommand = Notification.Name("SequencerAIScenesWorkspaceVisualCommand")
}

private extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}

private enum AudioInputTrackDetailTab: String, CaseIterable, Identifiable {
    case source
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .fx: return "FX"
        case .macros: return "Macros"
        case .mixer: return "Mixer"
        }
    }

    var subtitle: String {
        switch self {
        case .source: return "live or playback"
        case .fx: return "insert chain"
        case .macros: return "M1-M8"
        case .mixer: return "bus + sends"
        }
    }
}

private struct AudioInputRuntimePanel: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    let track: StepSequenceTrack
    let runtime: EngineController.AudioInputTrackRuntime?
    let accent: Color

    @State private var selectedTab: AudioInputTrackDetailTab = .source
    @State private var recordQuantize: EngineController.AudioInputRecordQuantize = .bar
    @State private var micAccess = AVCaptureDevice.authorizationStatus(for: .audio)

    private var monitorMode: EngineController.AudioInputMonitorMode {
        runtime?.monitorMode ?? .input
    }

    private var canArmInput: Bool {
        runtime?.routeState == .available && micAccess != .denied && micAccess != .restricted
    }

    private var availableChannels: Int {
        engineController.audioInputAvailableChannels
    }

    private var recordBars: Int {
        runtime?.recordBarLength ?? track.recordBarLength
    }

    private var isArmedOrRecording: Bool {
        runtime?.armState == .armed || runtime?.armState == .recording
    }

    private var selectedPatternIndex: Int {
        session.store.selectedPatternIndex(for: track.id)
    }

    private var occupiedPatternSlots: Set<Int> {
        let bank = session.store.patternBank(for: track.id)
        return Set(bank.slots.compactMap { slot in
            guard let clip = session.store.clipEntry(id: slot.sourceRef.clipID),
                  !clipIsEmpty(clip.content)
            else {
                return nil
            }
            return slot.slotIndex
        })
    }

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { session.store.selectedPatternIndex(for: track.id) },
            set: { session.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    private var armButtonTitle: String {
        switch runtime?.armState ?? .idle {
        case .armed:
            return "Armed — next \(recordQuantize == .bar ? "bar" : "phrase")"
        case .recording:
            return "Recording — Cancel"
        case .idle, .hasLoop:
            return "ARM \(recordBars) bar\(recordBars == 1 ? "" : "s")"
        }
    }

    private var armHelp: String {
        if micAccess == .denied || micAccess == .restricted {
            return "Microphone access is denied in System Settings"
        }
        guard canArmInput || isArmedOrRecording else {
            return "Pick an input the interface provides to enable arming"
        }
        return "Records \(recordBars) bar\(recordBars == 1 ? "" : "s") starting at the next \(recordQuantize == .bar ? "bar" : "phrase")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioPanel(title: "Pattern", accent: accent, showsHeader: false) {
                TrackPatternSlotPalette(
                    selectedSlot: selectedPatternIndexBinding,
                    occupiedSlots: occupiedPatternSlots,
                    bypassState: .notApplicable,
                    onBypassToggle: { _ in }
                )
            }

            audioInputTabBar

            Group {
                switch selectedTab {
                case .source:
                    sourceTab
                case .fx:
                    fxTab
                case .macros:
                    macrosTab
                case .mixer:
                    mixerTab
                }
            }
        }
        .onAppear {
            refreshMicAccessStatus()
        }
        // The user grants/revokes in System Settings and comes back: TCC
        // state changed behind our back, so re-read it whenever the app
        // becomes active again (a cached "denied" otherwise sticks forever).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicAccessStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .audioInputTrackWorkspaceVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    private var audioInputTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AudioInputTrackDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.title.uppercased())
                            .studioText(.eyebrowBold)
                            .foregroundStyle(selectedTab == tab ? StudioTheme.text : StudioTheme.mutedText)
                        Text(tab.subtitle)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(selectedTab == tab ? accent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: selectedTab == tab ? 1.5 : 1)
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selectedTab == tab ? accent : Color.clear)
                            .frame(height: 2)
                            .padding(.horizontal, 10)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceTab: some View {
        StudioPanel(title: "Source", accent: accent, showsHeader: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    StudioSegmentedControl(
                        title: "Mode",
                        selection: monitorBinding,
                        segments: [
                            StudioSegment(title: "Live", value: .input),
                            StudioSegment(title: "Playback", value: .loop, isEnabled: runtime?.hasRecordedLoop == true),
                        ],
                        accent: accent
                    )
                    .frame(width: 210)

                    statusLabel

                    Spacer()
                }

                switch monitorMode {
                case .input:
                    liveSourceContent
                case .loop:
                    playbackSourceContent
                }
            }
        }
    }

    private var liveSourceContent: some View {
        HStack(alignment: .top, spacing: 14) {
            inputCard
                .frame(width: 300)

            recordCard
                .frame(minWidth: 0, maxWidth: .infinity)

            writeTargetCard
                .frame(width: 280)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Audio Channel")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Button("Configure") {}
                    .buttonStyle(.plain)
                    .studioText(.microEmphasis)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth))
                    .opacity(0.55)
                    .disabled(true)
                    .help("Project-wide audio channel configuration is not yet modeled.")
            }

            inputChannelPicker

            AudioInputLevelMeters(level: runtime?.liveLevel ?? .silent, accent: runtime?.isSilent == true ? StudioTheme.mutedText : accent)
                .frame(height: 92)
                .padding(10)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                        .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 10) {
                Button {
                    if isArmedOrRecording {
                        session.cancelAudioInputArm(trackID: track.id)
                    } else {
                        session.armAudioInputTrack(trackID: track.id, quantize: recordQuantize)
                    }
                } label: {
                    Label(armButtonTitle, systemImage: isArmedOrRecording ? "stop.circle.fill" : "record.circle")
                        .studioText(.labelBold)
                        .frame(minWidth: 112)
                }
                .buttonStyle(.borderedProminent)
                .tint(isArmedOrRecording ? StudioTheme.amber : accent)
                .disabled(!canArmInput && !isArmedOrRecording)
                .help(armHelp)
            }

            HStack(alignment: .top, spacing: 14) {
                StudioSegmentedControl(
                    title: "Start",
                    selection: $recordQuantize,
                    segments: [
                        StudioSegment(title: "Next Bar", value: .bar),
                        StudioSegment(title: "Next Phrase", value: .phrase),
                    ],
                    accent: accent
                )

                StudioSegmentedControl(
                    title: "Length",
                    selection: recordBarsBinding,
                    segments: StepSequenceTrack.allowedRecordBarLengths.sorted().map {
                        StudioSegment(title: "\($0)", value: $0)
                    },
                    accent: accent
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var writeTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write Target")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.mutedText)

            writeTargetOption(title: "Rolling capture", subtitle: "Replace the live buffer.", isSelected: true, isEnabled: true)
            writeTargetOption(title: "Replace saved buffer", subtitle: "Future saved take.", isSelected: false, isEnabled: false)
            writeTargetOption(title: "New saved buffer", subtitle: "Name after capture.", isSelected: false, isEnabled: false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func writeTargetOption(title: String, subtitle: String, isSelected: Bool, isEnabled: Bool) -> some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .studioText(.labelBold)
                    .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(0.55))
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? accent : StudioTheme.border.opacity(0.8), lineWidth: isSelected ? 1.5 : StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var playbackSourceContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(runtime?.hasRecordedLoop == true ? "Rolling capture" : "No captured buffer")
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                    Text("Selected pattern playback")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Button("Choose...") {}
                    .buttonStyle(.borderless)
                    .studioText(.microEmphasis)
                    .disabled(true)
                    .help("Saved buffer selection is not yet modeled.")
            }

            AudioInputSignalPanel(
                runtime: runtime,
                accent: runtime?.isSilent == true ? StudioTheme.mutedText : accent,
                showsTitle: false
            )
        }
    }

    private var fxTab: some View {
        StudioPanel(title: "FX", accent: StudioTheme.violet, showsHeader: false) {
            HStack(spacing: 12) {
                Button {
                } label: {
                    Label("+ FX", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(true)

                Text("Per-track audio channel inserts are reserved for the track-detail FX chain.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
    }

    private var macrosTab: some View {
        StudioPanel(title: "Macros", accent: StudioTheme.cyan, showsHeader: false) {
            if track.macros.isEmpty {
                StudioPlaceholderTile(title: "No Macros", detail: "Assign M1-M8 controls from routable parameters.", accent: StudioTheme.cyan)
            } else {
                MacroKnobRow(document: $document, trackID: track.id)
            }
        }
    }

    private var mixerTab: some View {
        StudioPanel(title: "Mixer", accent: StudioTheme.success, showsHeader: false) {
            audioChannelMixerContent
        }
    }

    private var audioChannelMixerContent: some View {
        HStack(alignment: .top, spacing: 14) {
            audioChannelLevelCard
                .frame(minWidth: 280, maxWidth: .infinity)

            audioChannelOutputCard
                .frame(width: 240)

            audioChannelSendsCard
                .frame(width: 220)
        }
        .padding(StudioMetrics.Spacing.standard)
    }

    private var audioChannelLevelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Channel")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                Button {
                    session.toggleTrackMute(trackID: track.id)
                } label: {
                    Label(track.mix.isMuted ? "Muted" : "Mute", systemImage: track.mix.isMuted ? "speaker.slash.fill" : "speaker.slash")
                }
                .buttonStyle(.bordered)
                .tint(StudioTheme.amber)

                Button {
                    session.setTrackSoloed(!track.mix.isSoloed, trackID: track.id)
                } label: {
                    Label(track.mix.isSoloed ? "Soloed" : "Solo", systemImage: "headphones")
                }
                .buttonStyle(.bordered)
                .tint(StudioTheme.amber)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LEVEL")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer()
                    Text(StudioLevelFormat.dBLabel(forLinear: track.mix.clampedLevel))
                        .studioText(.microEmphasis)
                        .foregroundStyle(StudioTheme.text)
                }

                Slider(value: mixBinding(\.level, range: 0...1), in: 0...1)
                    .tint(StudioTheme.cyan)
            }

            StudioSlideControl(
                value: track.mix.clampedPan,
                accent: StudioTheme.violet,
                leadingLabel: "PAN",
                trailingLabel: StudioSlideControlModel.panLabel(for: track.mix.clampedPan),
                help: "\(track.name) pan",
                onChange: { setMixValue(\.pan, value: $0, range: -1...1) },
                onEnd: {}
            )
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var audioChannelOutputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.mutedText)

            Menu {
                Button("Master") {
                    session.setTrackOutputBus(trackID: track.id, busID: nil)
                }
                ForEach(session.store.buses) { bus in
                    Button(bus.name) {
                        session.setTrackOutputBus(trackID: track.id, busID: bus.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioTheme.mutedText)
                    Text(MixerRoutingDisplayModel.outputTitle(for: track, buses: session.store.buses))
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var audioChannelSendsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sends")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 18) {
                audioChannelSendKnob(title: "A", value: track.mix.sendA, keyPath: \.sendA, accent: StudioTheme.cyan)
                audioChannelSendKnob(title: "B", value: track.mix.sendB, keyPath: \.sendB, accent: StudioTheme.violet)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func audioChannelSendKnob(
        title: String,
        value: Double,
        keyPath: WritableKeyPath<TrackMixSettings, Double>,
        accent: Color
    ) -> some View {
        StudioRotaryKnob(
            title: title,
            value: MixerSendDisplayModel.clamped(value),
            range: TrackMixSettings.sendRange,
            accent: accent,
            size: 42,
            format: { MixerSendDisplayModel.percentLabel(for: $0) },
            onChange: { setMixValue(keyPath, value: $0, range: TrackMixSettings.sendRange) },
            onLiveChange: { setMixValue(keyPath, value: $0, range: TrackMixSettings.sendRange) }
        )
    }

    private func mixBinding(
        _ keyPath: WritableKeyPath<TrackMixSettings, Double>,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: { track.mix[keyPath: keyPath] },
            set: { setMixValue(keyPath, value: $0, range: range) }
        )
    }

    private func setMixValue(
        _ keyPath: WritableKeyPath<TrackMixSettings, Double>,
        value: Double,
        range: ClosedRange<Double>
    ) {
        var mix = track.mix
        mix[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
        session.setTrackMix(trackID: track.id, mix: mix)
    }

    private func applyVisualCommand(_ command: String) {
        let tabPrefix = "tab:"
        if command.hasPrefix(tabPrefix),
           let tab = AudioInputTrackDetailTab(rawValue: String(command.dropFirst(tabPrefix.count))) {
            selectedTab = tab
        }
    }

    private func refreshMicAccessStatus() {
        let previous = micAccess
        micAccess = AVCaptureDevice.authorizationStatus(for: .audio)
        if micAccess == .authorized, previous != .authorized {
            engineController.microphoneAccessChanged()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if micAccess == .denied || micAccess == .restricted {
            HStack(spacing: 8) {
                Text("MIC ACCESS DENIED")
                    .studioText(.microEmphasis)
                    .tracking(0.6)
                    .foregroundStyle(StudioTheme.amber)
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .studioText(.micro)
            }
        } else if !canArmInput, !isArmedOrRecording, availableChannels == 0 {
            Text("NO INPUT DEVICE")
                .studioText(.microEmphasis)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.amber)
        }
    }

    private var channelRequirementLabel: String {
        let required = (runtime?.selectedInputChannel ?? track.inputChannel).requiredChannelCount
        return "\(required) CHANNEL\(required == 1 ? "" : "S")"
    }

    private var selectedChannel: AudioInputChannel {
        runtime?.selectedInputChannel ?? track.inputChannel
    }

    /// Channel (or pair) choices generated from the connected device's
    /// reported input count — generic over any interface.
    private var inputChannelPicker: some View {
        let options = selectedChannel.isStereo
            ? AudioInputChannel.stereoOptions(channelCount: availableChannels)
            : AudioInputChannel.monoOptions(channelCount: availableChannels)

        return VStack(alignment: .leading, spacing: 6) {
            Menu {
                if options.isEmpty {
                    Button("No inputs available") {}
                        .disabled(true)
                } else {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Button(option.label) {
                            session.setAudioInputChannel(trackID: track.id, channel: option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Channel A")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                        Text("\(selectedChannel.label) · \(channelRequirementLabel.lowercased())")
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.text.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.text.opacity(0.75))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(StudioTheme.border.opacity(0.95), lineWidth: StudioMetrics.borderWidth)
                )
            }
            .menuStyle(.borderlessButton)
            .help(options.isEmpty ? "The interface reports no usable inputs" : "Choose the device input")
        }
    }

    private var recordBarsBinding: Binding<Int> {
        Binding(
            get: { recordBars },
            set: { session.setTrackRecordBarLength($0, trackID: track.id) }
        )
    }

    private var monitorBinding: Binding<EngineController.AudioInputMonitorMode> {
        Binding(
            get: { monitorMode },
            set: { session.setAudioInputMonitorMode(trackID: track.id, mode: $0) }
        )
    }

    private var channelBinding: Binding<AudioInputChannel> {
        Binding(
            get: { runtime?.selectedInputChannel ?? track.inputChannel },
            set: { session.setAudioInputChannel(trackID: track.id, channel: $0) }
        )
    }
}

private struct AudioInputSignalPanel: View {
    let runtime: EngineController.AudioInputTrackRuntime?
    let accent: Color
    var showsTitle = true

    private var level: AudioInputLevelSnapshot {
        runtime?.liveLevel ?? .silent
    }

    private var progress: Double {
        runtime?.recordingProgress ?? 0
    }

    private var title: String {
        switch runtime?.armState ?? .idle {
        case .recording:
            return "Recording"
        case .hasLoop:
            return "Loop"
        case .armed:
            return "Armed"
        case .idle:
            return runtime?.isSilent == true ? "Silent" : "Input"
        }
    }

    private var waveformBuckets: [Float] {
        guard let runtime else { return [] }
        if runtime.armState == .recording {
            return runtime.captureWaveformBuckets
        }
        return runtime.waveformBuckets
    }

    /// Live input states (idle/armed with input monitoring) have no engine
    /// bucket stream, so the monitor builds a rolling waveform from the live
    /// level snapshots — the same visual grammar as the slicer and the
    /// recording/loop states.
    private var showsRollingLiveWaveform: Bool {
        guard let runtime else { return false }
        return waveformBuckets.isEmpty && runtime.activeMonitorMode == .input && !runtime.isSilent
    }

    @State private var liveBuckets: [Float] = []
    private static let liveBucketCount = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                HStack(spacing: 10) {
                    Text(title.uppercased())
                        .studioText(.eyebrow)
                        .foregroundStyle(StudioTheme.mutedText)

                    Spacer()

                    if runtime?.armState == .recording {
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .studioText(.eyebrow)
                            .foregroundStyle(accent)
                    }
                }
            }

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.subtleFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                    )

                if !waveformBuckets.isEmpty {
                    WaveformView(
                        buckets: waveformBuckets,
                        fillColor: accent,
                        inactiveColor: StudioTheme.border.opacity(0.7)
                    )
                    .padding(StudioMetrics.Spacing.standard)
                } else if showsRollingLiveWaveform {
                    HStack(alignment: .bottom, spacing: 12) {
                        WaveformView(
                            buckets: liveBuckets,
                            fillColor: accent,
                            inactiveColor: StudioTheme.border.opacity(0.7)
                        )

                        AudioInputLevelMeters(level: level, accent: accent)
                            .frame(width: 52)
                    }
                    .padding(StudioMetrics.Spacing.standard)
                } else {
                    AudioInputLevelMeters(level: level, accent: accent)
                        .padding(StudioMetrics.Spacing.standard)
                }

                if runtime?.armState == .recording {
                    // Colour identifies, it never floods (ux-canon rule 12):
                    // record progress is a neutral wash capped by a solid
                    // accent head line, not an accent flood.
                    GeometryReader { geo in
                        let progressWidth = geo.size.width * CGFloat(min(max(progress, 0), 1))
                        Rectangle()
                            .fill(Color.white.opacity(StudioOpacity.subtleFill))
                            .frame(width: progressWidth)
                            .frame(maxHeight: .infinity, alignment: .bottomLeading)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(accent)
                                    .frame(width: 2)
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
                }
            }
            .frame(height: 128)
        }
        .task(id: showsRollingLiveWaveform) {
            guard showsRollingLiveWaveform else {
                liveBuckets = []
                return
            }
            while !Task.isCancelled {
                let peak = max(level.leftPeak, level.rightPeak)
                liveBuckets.append(peak)
                if liveBuckets.count > Self.liveBucketCount {
                    liveBuckets.removeFirst(liveBuckets.count - Self.liveBucketCount)
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}

private struct AudioInputLevelMeters: View {
    let level: AudioInputLevelSnapshot
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 8) {
                meter(value: level.leftPeak, label: "L", height: geo.size.height)
                meter(value: level.rightPeak, label: "R", height: geo.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func meter(value: Float, label: String, height: CGFloat) -> some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .fill(StudioTheme.border.opacity(0.35))
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .fill(accent)
                    .frame(height: max(2, height * CGFloat(min(max(value, 0), 1))))
            }
            .frame(width: 18)

            Text(label)
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}

private struct StudioSegment<Value: Equatable> {
    let title: String
    let value: Value
    var isEnabled: Bool = true
}

private struct StudioSegmentedControl<Value: Equatable>: View {
    let title: String
    let selection: Binding<Value>
    let segments: [StudioSegment<Value>]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 4) {
                ForEach(segments.indices, id: \.self) { index in
                    segmentButton(segments[index])
                }
            }
            .padding(3)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
            )
        }
    }

    private func segmentButton(_ segment: StudioSegment<Value>) -> some View {
        let isSelected = selection.wrappedValue == segment.value

        return Button {
            selection.wrappedValue = segment.value
        } label: {
            Text(segment.title)
                .studioText(.labelBold)
                .foregroundStyle(segmentForeground(isSelected: isSelected, isEnabled: segment.isEnabled))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 8)
                // Colour identifies, it never floods (ux-canon rule 12): the
                // selected segment is a fully solid accent thumb.
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!segment.isEnabled)
        .help(segment.isEnabled ? "" : "The audio interface does not provide enough inputs for \(segment.title)")
        .accessibilityLabel("\(title) \(segment.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func segmentForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.4)
        }
        return isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78)
    }
}
