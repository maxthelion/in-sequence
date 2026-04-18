import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Section("Arrangement") {
                Text("Song").tag("song")
                Text("Phrase").tag("phrase")
            }
            Section("Tracks") {
                Text("(no tracks yet)").foregroundStyle(.secondary)
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
    SidebarView()
}
