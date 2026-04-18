import SwiftUI

struct SidebarView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection

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
                        section = .trackEditor
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
                globalRow(title: "Mixer", systemImage: "slider.vertical.3", sectionValue: .mixer)
                globalRow(title: "Perform", systemImage: "dot.radiowaves.left.and.right", sectionValue: .perform)
                globalRow(title: "Library", systemImage: "books.vertical", sectionValue: .library)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SequencerAI")
    }

    @ViewBuilder
    private func globalRow(title: String, systemImage: String, sectionValue: WorkspaceSection) -> some View {
        Button {
            section = sectionValue
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(section == sectionValue ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SidebarPreview()
}

private struct SidebarPreview: View {
    @State private var document = SeqAIDocument()
    @State private var section: WorkspaceSection = .trackEditor

    var body: some View {
        SidebarView(document: $document, section: $section)
    }
}
