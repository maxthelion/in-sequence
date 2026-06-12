import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    var scenesResetToken: Int = 0
    var visualPhraseControlsOpenIndex: Binding<Int?> = .constant(nil)
    @State private var liveLayerID = "pattern"
    @Environment(SequencerDocumentSession.self) private var session

    var body: some View {
        ScrollView {
            workspace
                .padding(StudioMetrics.Spacing.tight)
        }
        // Bold-flat pass: the stage IS the window ground — no rounded stage
        // plate, no outline; controls sit directly on the one near-black
        // ground like the reference.
        .background(StudioTheme.stageFill)
    }

    @ViewBuilder
    private var workspace: some View {
        switch section {
        case .phrase:
            PhraseWorkspaceView(
                document: $document,
                visualControlsOpenIndex: visualPhraseControlsOpenIndex
            )
        case .tracks:
            TracksWorkspaceView(document: $document, selectedLayerID: $liveLayerID) {
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
