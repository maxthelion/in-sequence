import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @State private var section: WorkspaceSection = .tracks
    @State private var scenesResetToken = 0
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    private var sectionBinding: Binding<WorkspaceSection> {
        Binding(
            get: { section },
            set: { newSection in
                if newSection == .scenes {
                    scenesResetToken += 1
                }
                section = newSection
            }
        )
    }

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                StudioTopBar(section: sectionBinding, document: $document)
                WorkspaceDetailView(document: $document, section: sectionBinding, scenesResetToken: scenesResetToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        .task {
            await VisualScenarioCommandRunner.runIfConfigured(
                section: sectionBinding,
                session: session,
                engineController: engineController
            )
        }
    }
}
