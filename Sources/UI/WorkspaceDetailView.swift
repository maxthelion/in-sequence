import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @State private var liveLayerID = "pattern"
    @Environment(SequencerDocumentSession.self) private var session

    var body: some View {
        ScrollView {
            workspace
                .padding(6)
        }
        .background(StudioTheme.stageFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.workspace, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.workspace, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
                .allowsHitTesting(false)
        )
        #if DEBUG
        .background {
            WorkspaceHitTestDiagnostics(label: "WorkspaceDetailView", section: section)
        }
        #endif
    }

    @ViewBuilder
    private var workspace: some View {
        switch section {
        case .phrase:
            PhraseWorkspaceView(document: $document)
                .padding(10)
        case .tracks:
            TracksMatrixView(document: $document) {
                section = .track
            }
            .padding(20)
        case .track:
            TrackWorkspaceView(document: $document)
        case .mixer:
            MixerWorkspaceView(document: $document) { trackID in
                session.setSelectedTrackID(trackID)
                section = .track
            }
        case .live:
            StudioPanel(
                title: "Live",
                eyebrow: "Current phrase cells under direct transport control",
                accent: StudioTheme.amber
            ) {
                LiveWorkspaceView(document: $document, selectedLayerID: $liveLayerID)
            }
            .padding(20)
        case .library:
            LibraryWorkspaceView()
        }
    }
}

#Preview {
    WorkspaceDetailPreview()
}

private struct WorkspaceDetailPreview: View {
    @State private var document = SeqAIDocument()
    @State private var section: WorkspaceSection = .track

    var body: some View {
        WorkspaceDetailView(document: $document, section: $section)
            .padding()
            .background(StudioTheme.background)
            .environment(EngineController(client: nil, endpoint: nil))
    }
}
