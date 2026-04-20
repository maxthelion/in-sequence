import SwiftUI

struct TrackWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @State private var editingTrackID: UUID?
    @State private var draftTrackName = ""
    @FocusState private var trackNameFieldFocused: Bool

    private var track: StepSequenceTrack {
        document.project.selectedTrack
    }

    private var outboundRouteCount: Int {
        document.project.routesSourced(from: track.id).count
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
                        .frame(minWidth: 640, maxWidth: .infinity, alignment: .topLeading)

                    destinationColumn
                        .frame(width: 360, alignment: .topLeading)
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
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .onSubmit {
                            commitTrackName()
                        }
                } else {
                    Text(track.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
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
        guard let editingTrackID,
              let index = document.project.tracks.firstIndex(where: { $0.id == editingTrackID })
        else {
            self.editingTrackID = nil
            draftTrackName = ""
            return
        }

        document.project.tracks[index].name = draftTrackName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? document.project.tracks[index].name
            : draftTrackName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.editingTrackID = nil
        draftTrackName = ""
    }
}
