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
                        SidebarRow(
                            title: track.name,
                            systemImage: track.id == document.model.selectedTrackID ? "pianokeys.inverse" : "pianokeys",
                            trailingText: "\(track.stepPattern.filter { $0 }.count)",
                            isSelected: track.id == document.model.selectedTrackID && section == .trackEditor
                        )
                    }
                    .buttonStyle(.plain)
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
            SidebarRow(
                title: title,
                systemImage: systemImage,
                isSelected: section == sectionValue
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
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
