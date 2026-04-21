import SwiftUI

struct SidebarView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection

    var body: some View {
        List {
            Section("Arrangement") {
                globalRow(title: "Phrase", systemImage: "square.split.2x2", sectionValue: .phrase)
                globalRow(title: "Tracks", systemImage: "square.grid.3x3", sectionValue: .tracks)
            }
            Section("Tracks") {
                ForEach(document.project.tracks, id: \.id) { track in
                    Button {
                        document.project.selectTrack(id: track.id)
                        section = .track
                    } label: {
                        SidebarRow(
                            title: track.name,
                            systemImage: track.id == document.project.selectedTrackID ? "pianokeys.inverse" : "pianokeys",
                            trailingText: "\(track.stepPattern.filter { $0 }.count)",
                            isSelected: track.id == document.project.selectedTrackID && section == .track
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button("Add Track") {
                        document.project.appendTrack()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove") {
                        document.project.removeSelectedTrack()
                    }
                    .buttonStyle(.bordered)
                    .disabled(document.project.tracks.count <= 1)
                }
                .padding(.top, 4)
            }
            Section("Global") {
                globalRow(title: "Mixer", systemImage: "slider.vertical.3", sectionValue: .mixer)
                globalRow(title: "Live", systemImage: "sparkles", sectionValue: .live)
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
    @State private var section: WorkspaceSection = .track

    var body: some View {
        SidebarView(document: $document, section: $section)
    }
}
