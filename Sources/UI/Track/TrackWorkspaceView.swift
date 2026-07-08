import AVFoundation
import SwiftUI

struct TrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var editingTrackID: UUID?
    @State private var stepGridWorkspaceModel = TrackStepGridWorkspaceModel()
    @State private var draftTrackName = ""
    /// Drives the delete-track confirmation on the single-track detail header.
    @State private var isConfirmingTrackDelete = false
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

    /// The kit matrix navigation state to show, or `nil` for a non-drum track
    /// (which keeps its single-source editor). A drum-group track ALWAYS shows
    /// the kit matrix — per-part editing now lives inline in the matrix's
    /// expanded-row accordion, so there is no per-part dive-in.
    private var kitNavigationState: DrumKitWorkspaceNavigationState? {
        DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: drumPartHeaderModel)
    }

    private var outboundRouteCount: Int {
        session.store.routesSourced(from: track.id).count
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

    private var sourceAccent: Color {
        StudioTheme.trackAccent(for: track, groups: session.store.trackGroups)
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
                // The per-part dive-in is gone: per-part editing lives inline in
                // the matrix's expanded-row accordion. Selecting a part keeps it
                // as the selected track but does not navigate away from the kit.
                onSelectPart: { partID in
                    session.setSelectedTrackID(partID)
                }
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
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
                } else if track.trackType == .chord {
                    ChordTrackWorkspaceView(
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
                            accent: sourceAccent
                        ) {
                            RoutesListView(document: $document)
                        }
                    }
                }
            }
            .padding(StudioMetrics.Spacing.workspaceInset)
        }
    }

    // A drum-group track always renders the kit matrix (handled above), so the
    // workspace header here only ever covers the non-drum single-track surfaces.
    private var trackHeader: some View {
        defaultTrackHeader
    }

    private var defaultTrackHeader: some View {
        CompactTrackDetailHeader(accent: sourceAccent) {
            trackNameEditor
        } trailing: {
            HStack(spacing: 10) {
                if track.trackType == .monoMelodic || track.trackType == .polyMelodic {
                    TrackFillPreviewControl(
                        presentation: fillPreviewPresentation,
                        accent: sourceAccent,
                        toggle: toggleFillPreview
                    )

                    TrackPerformHeaderButton(trackID: track.id, accent: sourceAccent)
                }

                deleteTrackButton
            }
        } patternSlotControls: {
            TrackPatternSlotPalette(
                selectedSlot: selectedPatternIndexBinding,
                occupiedSlots: occupiedPatternSlots,
                bypassState: .notApplicable,
                onBypassToggle: { _ in },
                accent: sourceAccent
            )
        }
        .confirmationDialog(
            "Delete \(track.name)?",
            isPresented: $isConfirmingTrackDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Track", role: .destructive) {
                let removedID = track.id
                isConfirmingTrackDelete = false
                session.removeTrack(id: removedID)
            }
            Button("Cancel", role: .cancel) {
                isConfirmingTrackDelete = false
            }
        } message: {
            Text("This removes the track from the project. This cannot be undone.")
        }
    }

    /// Top-right delete affordance on the single-track detail header. Tapping it
    /// raises a confirmation before the track is removed via the session API.
    private var deleteTrackButton: some View {
        Button {
            isConfirmingTrackDelete = true
        } label: {
            // Neutral utility chrome: an amber outline here was a second
            // chrome accent on the track surface (State-colour fence — amber
            // never appears as an outline; the destructive intent is carried
            // by the confirm dialog).
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 34, height: 34)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Delete this track")
        .accessibilityIdentifier("track-detail-delete")
        .accessibilityLabel("Delete track")
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

/// Perform header button (AC22): posts `.trackPerformRequested` with the
/// track id. Shared by the compact track-detail headers so the melodic, slicer
/// and audio surfaces present an identical Perform affordance.
struct TrackPerformHeaderButton: View {
    let trackID: UUID
    let accent: Color

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .trackPerformRequested,
                object: trackID
            )
        } label: {
            Label("Perform", systemImage: "play.fill")
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.background)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .help("Perform: open the phrase perform UI scoped to this track")
        .accessibilityIdentifier("track-perform")
        .accessibilityLabel("Perform track")
    }
}

/// Shared compact top-header grammar for the three track-detail surfaces
/// (melodic track, slicer, audio input). Renders the track title, immediate
/// controls, and pattern slots inside one rounded shell matching the drum-kit
/// header grammar.
struct CompactTrackDetailHeader<Title: View, Trailing: View, PatternControls: View>: View {
    var accent: Color
    @ViewBuilder var title: () -> Title
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var patternSlotControls: () -> PatternControls

    init(
        accent: Color,
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder patternSlotControls: @escaping () -> PatternControls = { EmptyView() }
    ) {
        self.accent = accent
        self.title = title
        self.trailing = trailing
        self.patternSlotControls = patternSlotControls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                title()
                    .layoutPriority(1)

                Spacer(minLength: 12)

                trailing()
            }

            patternSlotControls()
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
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
    static let trackSourceEditorRenderedVisualState = Notification.Name("SequencerAITrackSourceEditorRenderedVisualState")
    static let trackSourceGeneratorRenderedVisualState = Notification.Name("SequencerAITrackSourceGeneratorRenderedVisualState")
    static let sliceTrackWorkspaceVisualCommand = Notification.Name("SequencerAISliceTrackWorkspaceVisualCommand")
    static let chordTrackWorkspaceVisualCommand = Notification.Name("SequencerAIChordTrackWorkspaceVisualCommand")
    static let chordTrackWorkspaceRenderedVisualState = Notification.Name("SequencerAIChordTrackWorkspaceRenderedVisualState")
    static let audioInputTrackWorkspaceVisualCommand = Notification.Name("SequencerAIAudioInputTrackWorkspaceVisualCommand")
    static let workspaceDetailVisualCommand = Notification.Name("SequencerAIWorkspaceDetailVisualCommand")
    static let scenesWorkspaceVisualCommand = Notification.Name("SequencerAIScenesWorkspaceVisualCommand")
    /// Drives the tracks-navigator creation modals from the capture harness
    /// (objects "create-track-modal:open" / "add-drum-group-modal:open").
    static let tracksMatrixVisualCommand = Notification.Name("SequencerAITracksMatrixVisualCommand")
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
    @State private var isPresentingInputPicker = false

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
            // Unified tab grammar (Variant D): the section pills float a small
            // gap above the accent-outlined well; tab content lives inside it.
            VStack(alignment: .leading, spacing: StudioTabWellGrammar.pillRowToWellGap) {
                sectionPills

                StudioTabWell(accent: accent) {
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

    private var sectionPills: some View {
        StudioSectionPills(
            pills: AudioInputTrackDetailTab.allCases.map { tab in
                StudioSectionPill(
                    section: tab,
                    title: tab.title,
                    accessibilityIdentifier: "audio-input-detail-tab-\(tab.rawValue)"
                )
            },
            selection: selectedTab,
            accent: accent,
            accessibilityIdentifier: "audio-input-detail-tabs",
            onSelect: { selectedTab = $0 }
        )
    }

    private var sourceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                StudioSegmentedControl(
                    title: nil,
                    selection: monitorBinding,
                    segments: [
                        StudioSegment(title: "Live", value: .input),
                        StudioSegment(
                            title: "Playback",
                            value: .loop,
                            isEnabled: runtime?.hasRecordedLoop == true,
                            help: runtime?.hasRecordedLoop == true ? nil : "The audio interface does not provide enough inputs for Playback"
                        ),
                    ],
                    accent: accent,
                    accessibilityLabel: { segment in "Input mode \(segment.title)" }
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

    /// Whether an input device is connected and offers a usable channel. When
    /// false the card shows the "+" empty state inviting the user to connect.
    private var hasSelectableInput: Bool {
        availableChannels > 0
    }

    @ViewBuilder
    private var inputCard: some View {
        Group {
            if hasSelectableInput {
                selectedInputElement
            } else {
                StudioAddCard(
                    label: "Add Audio Input",
                    accent: accent,
                    minHeight: 168,
                    help: "Choose the device input for this track."
                ) {
                    isPresentingInputPicker = true
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $isPresentingInputPicker) {
            AudioInputChannelPickerSheet(
                selectedChannel: selectedChannel,
                availableChannels: availableChannels,
                accent: accent,
                onSelect: { channel in
                    session.setAudioInputChannel(trackID: track.id, channel: channel)
                }
            )
        }
    }

    /// One big, colourful, tappable element representing the selected input
    /// with the live level meters integrated into the same surface. Tapping it
    /// opens the change-input modal.
    private var selectedInputElement: some View {
        Button {
            isPresentingInputPicker = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio Channel")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(StudioTheme.background.opacity(0.7))
                    Text(selectedChannel.label)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.background)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(channelRequirementLabel.lowercased())
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.background.opacity(0.7))
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                        Text("Change")
                            .studioText(.microEmphasis)
                    }
                    .foregroundStyle(StudioTheme.background.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AudioInputLevelMeters(
                    level: runtime?.liveLevel ?? .silent,
                    accent: StudioTheme.background
                )
                .frame(width: 64)
            }
            .padding(StudioMetrics.Spacing.comfortable)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Change the device input for this track.")
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
                .tint(isArmedOrRecording ? StudioTheme.warning : accent)
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
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.borderSubtle), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var writeTargetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Write Target")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.mutedText)

            writeTargetOption(
                title: "Capture Buffer",
                isSelected: true,
                isEnabled: true,
                help: "Each capture replaces the live buffer."
            )
            writeTargetOption(title: "Replace saved buffer", isSelected: false, isEnabled: false)
            writeTargetOption(title: "New saved buffer", isSelected: false, isEnabled: false)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.borderSubtle), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func writeTargetOption(title: String, isSelected: Bool, isEnabled: Bool, help: String? = nil) -> some View {
        Button {} label: {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(isSelected ? accent : accent.opacity(StudioOpacity.borderSubtle), lineWidth: isSelected ? 1.5 : StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help ?? "")
    }

    private var playbackSourceContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            AudioInputSignalPanel(
                runtime: runtime,
                accent: runtime?.isSilent == true ? StudioTheme.mutedText : accent,
                showsTitle: false
            )
        }
    }

    // One chrome accent per surface: the FX + macros tabs share the track
    // identity accent (no per-tab violet/cyan roulette).
    private var fxTab: some View {
        Button {
        } label: {
            Label("+ FX", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(true)
        .help("Per-track audio channel inserts are reserved for the track-detail FX chain.")
    }

    @ViewBuilder
    private var macrosTab: some View {
        if track.macros.isEmpty {
            StudioEmptyWell(
                title: "Macros",
                systemImage: "slider.horizontal.3",
                accent: accent,
                minHeight: 148,
                help: "Assign M1-M8 controls from routable parameters."
            )
                .help("Assign M1-M8 controls from routable parameters.")
        } else {
            MacroKnobRow(document: $document, trackID: track.id)
        }
    }

    private var mixerTab: some View {
        TrackRoutingTabContent(
            document: $document,
            summary: routingPathSummary,
            mode: .mixer,
            accent: accent
        )
    }

    private var routingPathSummary: TrackRoutingPathSummary {
        TrackRoutingPathSummary.make(
            destinationSummary: DestinationSummary.make(
                for: session.store.resolvedDestination(for: track.id),
                in: session.store,
                trackID: track.id
            ),
            outputTitle: MixerRoutingDisplayModel.outputTitle(for: track, buses: session.store.buses),
            mix: track.mix
        )
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
                    .foregroundStyle(StudioTheme.warning)
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .studioText(.micro)
            }
        }
    }

    private var channelRequirementLabel: String {
        let required = (runtime?.selectedInputChannel ?? track.inputChannel).requiredChannelCount
        return "\(required) CHANNEL\(required == 1 ? "" : "S")"
    }

    private var selectedChannel: AudioInputChannel {
        runtime?.selectedInputChannel ?? track.inputChannel
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
                    .fill(StudioTheme.subtleFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                    )

                if !waveformBuckets.isEmpty {
                    WaveformView(
                        buckets: waveformBuckets,
                        fillColor: accent,
                        inactiveColor: StudioTheme.border.opacity(0.7),
                        stepCount: 16,
                        barStepInterval: 16,
                        playheadFraction: runtime?.armState == .recording ? CGFloat(progress) : nil
                    )
                    .padding(StudioMetrics.Spacing.standard)
                } else if showsRollingLiveWaveform {
                    HStack(alignment: .bottom, spacing: 12) {
                        WaveformView(
                            buckets: liveBuckets,
                            fillColor: accent,
                            inactiveColor: StudioTheme.border.opacity(0.7),
                            stepCount: 16,
                            barStepInterval: 16
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
                            .fill(StudioTheme.subtleFill)
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
                    .fill(StudioTheme.borderSubtleOverlayFill)
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

/// Modal for changing which already-available input/channel the track taps.
/// Reuses the same mono/stereo option generation the inline picker used; it
/// only changes the existing selection (no device enumeration here).
private struct AudioInputChannelPickerSheet: View {
    let selectedChannel: AudioInputChannel
    let availableChannels: Int
    let accent: Color
    let onSelect: (AudioInputChannel) -> Void

    @Environment(\.dismiss) private var dismiss

    private var monoOptions: [AudioInputChannel] {
        AudioInputChannel.monoOptions(channelCount: availableChannels)
    }

    private var stereoOptions: [AudioInputChannel] {
        AudioInputChannel.stereoOptions(channelCount: availableChannels)
    }

    var body: some View {
        StudioModal(
            title: "Audio Input",
            accent: accent,
            minWidth: 420,
            onClose: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    optionGroup(title: "Stereo Pairs", options: stereoOptions)
                    optionGroup(title: "Mono Channels", options: monoOptions)

                    if monoOptions.isEmpty, stereoOptions.isEmpty {
                        Text("No usable inputs")
                            .studioText(.placeholderTitle)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }
            }
            .frame(maxHeight: 420)
        }
    }

    @ViewBuilder
    private func optionGroup(title: String, options: [AudioInputChannel]) -> some View {
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)

                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    StudioOptionButton(
                        title: option.label,
                        accent: option == selectedChannel ? accent : nil
                    ) {
                        onSelect(option)
                        dismiss()
                    }
                }
            }
        }
    }
}

// StudioSegmentedControl / StudioSegment were promoted to
// Sources/UI/Theme/StudioSegmentedControls.swift in W2.
