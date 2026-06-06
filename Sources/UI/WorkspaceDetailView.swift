import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @Binding var tracksMode: TracksWorkspaceMode
    var scenesResetToken: Int = 0
    var visualPhraseControlsOpenIndex: Binding<Int?> = .constant(nil)
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
    }

    @ViewBuilder
    private var workspace: some View {
        switch section {
        case .phrase:
            PhraseWorkspaceView(
                document: $document,
                visualControlsOpenIndex: visualPhraseControlsOpenIndex
            )
                .padding(10)
        case .tracks:
            TracksWorkspaceView(document: $document, mode: $tracksMode, selectedLayerID: $liveLayerID) {
                section = .track
            }
        case .track:
            TrackWorkspaceView(document: $document)
        case .mixer:
            MixerWorkspaceView(document: $document) { trackID in
                session.setSelectedTrackID(trackID)
                section = .track
            }
        case .scenes:
            ScenesWorkspaceView(document: $document, resetToken: scenesResetToken)
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
    @State private var tracksMode: TracksWorkspaceMode = .edit

    var body: some View {
        WorkspaceDetailView(document: $document, section: $section, tracksMode: $tracksMode)
            .padding()
            .background(StudioTheme.background)
            .environment(EngineController(client: nil, endpoint: nil))
    }
}
