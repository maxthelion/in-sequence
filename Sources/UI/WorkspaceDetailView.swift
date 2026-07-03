import SwiftUI

struct WorkspaceDetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    var scenesResetToken: Int = 0
    var visualPhraseControlsOpenIndex: Binding<Int?> = .constant(nil)
    @State private var liveLayerID = "pattern"
    @Environment(SequencerDocumentSession.self) private var session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                workspace
                    .padding(StudioMetrics.Spacing.tight)
                    .id("workspace-top")
                Color.clear
                    .frame(height: 1)
                    .id("workspace-bottom")
            }
            // Stock scrollbar tracks are banned chrome (canon Rule 6, design
            // review 04/22d) — the workspace scroll hides its indicator.
            .scrollIndicators(.never)
            .onReceive(NotificationCenter.default.publisher(for: .workspaceDetailVisualCommand)) { notification in
                guard let command = notification.object as? String else { return }
                switch command {
                case "scroll-top":
                    proxy.scrollTo("workspace-top", anchor: .top)
                case "scroll-bottom":
                    proxy.scrollTo("workspace-bottom", anchor: .bottom)
                default:
                    break
                }
            }
            // Scoped Track/Kit Perform (AC22): a Perform button on a single
            // track or a kit posts here. We reuse the existing tracks-perform
            // surface — set the perform scope, flip to perform mode, and
            // navigate to the tracks page. No bespoke perform surface.
            .onReceive(NotificationCenter.default.publisher(for: .trackPerformRequested)) { notification in
                guard let trackID = notification.object as? UUID else { return }
                enterScopedPerform(trackIDs: [trackID])
            }
            .onReceive(NotificationCenter.default.publisher(for: .drumKitPerformRequested)) { notification in
                guard let groupID = notification.object as? TrackGroupID else { return }
                let memberIDs = session.store.tracksInGroup(groupID).map(\.id)
                guard !memberIDs.isEmpty else { return }
                enterScopedPerform(trackIDs: memberIDs)
            }
            // Tracks actions nav (By Track / By Value): when a pending
            // phrase-perform target is set, navigate to the Phrase workspace.
            // The phrase view consumes the tab + layer mode + scope and clears
            // the target.
            .onChange(of: session.pendingPhrasePerform) {
                if session.pendingPhrasePerform != nil {
                    section = .phrase
                }
            }
            // Bold-flat pass: the stage IS the window ground — no rounded stage
            // plate, no outline; controls sit directly on the one near-black
            // ground like the reference.
            .background(StudioTheme.stageFill)
        }
    }

    private func enterScopedPerform(trackIDs: [UUID]) {
        session.enterScopedPerform(trackIDs: trackIDs)
        section = .tracks
    }

    @ViewBuilder
    private var workspace: some View {
        switch section {
        case .song:
            SongWorkspaceView {
                section = .phrase
            }
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
            LibraryWorkspaceView(onOpenTrack: {
                section = .track
            })
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
