import SwiftUI

struct TrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController
    @State private var editingTrackID: UUID?
    @State private var stepGridWorkspaceModel = TrackStepGridWorkspaceModel()
    @State private var draftTrackName = ""
    @FocusState private var trackNameFieldFocused: Bool

    private var track: StepSequenceTrack {
        session.store.selectedTrack
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
        VStack(alignment: .leading, spacing: 18) {
            trackHeader

            if track.trackType == .audioInput {
                AudioInputRuntimePanel(
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
                HStack(alignment: .top, spacing: 18) {
                    TrackSourceEditorView(document: $document, accent: sourceAccent)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)

                    destinationColumn
                        .frame(width: 320, alignment: .topLeading)
                }
            }
        }
        .padding(20)
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
    }

    private var destinationColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Destination", eyebrow: "Current sink and routing target", accent: StudioTheme.success) {
                TrackDestinationEditor(document: $document)
            }

            if outboundRouteCount > 0 {
                StudioPanel(
                    title: "Routing",
                    eyebrow: "\(outboundRouteCount) outbound project route\(outboundRouteCount == 1 ? "" : "s")",
                    accent: StudioTheme.violet
                ) {
                    RoutesListView(document: $document)
                }
            }
        }
    }

    private var trackHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if isEditingSelectedTrackName {
                    TextField("Track Name", text: $draftTrackName)
                        .textFieldStyle(.roundedBorder)
                        .focused($trackNameFieldFocused)
                        .studioText(.display)
                        .onSubmit {
                            commitTrackName()
                        }
                } else {
                    Text(track.name)
                        .studioText(.display)
                        .foregroundStyle(StudioTheme.text)
                        .onTapGesture(count: 2) {
                            editingTrackID = track.id
                            draftTrackName = track.name
                        }
                }
            }

            Spacer()
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

private struct AudioInputRuntimePanel: View {
    @Environment(SequencerDocumentSession.self) private var session
    let track: StepSequenceTrack
    let runtime: EngineController.AudioInputTrackRuntime?
    let accent: Color

    private var armStateLabel: String {
        switch runtime?.armState ?? .idle {
        case .idle:
            return "Idle"
        case .armed:
            return "Armed"
        case .recording:
            return "Recording"
        case .hasLoop:
            return "Loop Ready"
        }
    }

    private var monitorMode: EngineController.AudioInputMonitorMode {
        runtime?.monitorMode ?? .input
    }

    private var routeLabel: String {
        guard let runtime else {
            return "Runtime unavailable"
        }
        return runtime.routeState == .available ? "Input route ready" : "Silent input route"
    }

    var body: some View {
        StudioPanel(title: "Audio Input", eyebrow: routeLabel, accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StudioMetricPill(title: "State", value: armStateLabel, accent: accent)
                    StudioMetricPill(title: "Monitor", value: monitorMode == .input ? "Input" : "Loop", accent: StudioTheme.amber)
                    StudioMetricPill(title: "Channel", value: (runtime?.selectedInputChannel ?? track.inputChannel).label, accent: StudioTheme.cyan)
                    Spacer()
                }

                HStack(spacing: 12) {
                    if runtime?.armState == .armed || runtime?.armState == .recording {
                        Button {
                            session.cancelAudioInputArm(trackID: track.id)
                        } label: {
                            Label("Cancel ARM", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            session.armAudioInputTrack(trackID: track.id)
                        } label: {
                            Label("ARM", systemImage: "record.circle")
                        }
                    }

                    Picker("Monitor", selection: monitorBinding) {
                        Text("Input").tag(EngineController.AudioInputMonitorMode.input)
                        Text("Loop").tag(EngineController.AudioInputMonitorMode.loop)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Picker("Input", selection: channelBinding) {
                        ForEach(AudioInputChannel.allCases, id: \.self) { channel in
                            Text(channel.label).tag(channel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .disabled(runtime == nil)

                StudioPlaceholderTile(
                    title: runtime?.isSilent == true ? "Silent" : "Ready",
                    detail: "Runtime commands are active. Audio tap wiring, bar-locked capture, loop playback, and waveform publication are still deferred.",
                    accent: runtime?.isSilent == true ? StudioTheme.mutedText : accent
                )
            }
        }
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
