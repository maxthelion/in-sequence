import SwiftUI

struct SidebarView: View {
    @Binding var document: SeqAIDocument

    var body: some View {
        List {
            Section("Arrangement") {
                Text("Song").tag("song")
                Text("Phrase").tag("phrase")
            }
            Section("Tracks") {
                Label(document.model.primaryTrack.name, systemImage: "pianokeys")
                Text("\(document.model.primaryTrack.stepPattern.count) steps")
                    .foregroundStyle(.secondary)
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
