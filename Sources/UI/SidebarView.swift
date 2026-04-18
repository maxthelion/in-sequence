import SwiftUI

struct SidebarView: View {
    @Binding var document: SeqAIDocument

    private var selectedTrackID: Binding<UUID> {
        Binding(
            get: { document.model.selectedTrackID },
            set: { document.model.selectTrack(id: $0) }
        )
    }

    var body: some View {
        List {
            Section("Arrangement") {
                Text("Song").tag("song")
                Text("Phrase").tag("phrase")
            }
            Section("Tracks") {
                ForEach(document.model.tracks, id: \.id) { track in
                    Button {
                        document.model.selectTrack(id: track.id)
                    } label: {
                        HStack {
                            Label(track.name, systemImage: track.id == document.model.selectedTrackID ? "pianokeys.inverse" : "pianokeys")
                            Spacer()
                            Text("\(track.stepPattern.filter { $0 }.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }

                HStack(spacing: 8) {
                    Button("Add Track") {
                        document.model.appendTrack()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove") {
                        document.model.removeSelectedTrack()
                    }
                    .buttonStyle(.bordered)
                    .disabled(document.model.tracks.count <= 1)
                }
                .padding(.top, 4)
            }
            Section("Global") {
                Text("Mixer").tag("mixer")
                Text("Perform").tag("perform")
                Text("Library").tag("library")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SequencerAI")
    }
}

#Preview {
    SidebarPreview()
}

private struct SidebarPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        SidebarView(document: $document)
    }
}
