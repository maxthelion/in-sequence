import SwiftUI

struct TrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    @State private var editingTrackID: UUID?
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
        }
    }

    private var isEditingSelectedTrackName: Bool {
        editingTrackID == track.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            trackHeader

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    TrackSourceEditorView(document: $document, accent: sourceAccent)
                        .frame(minWidth: 760, maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)

                    destinationColumn
                        .frame(width: 320, alignment: .topLeading)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 18) {
                    TrackSourceEditorView(document: $document, accent: sourceAccent)
                    destinationColumn
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
