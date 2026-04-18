import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @State private var section: WorkspaceSection = .track

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                StudioTopBar(section: $section, document: $document)
                TrackBankBar(document: $document, section: $section)
                DetailView(document: $document, section: $section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        .onAppear {
            engineController.apply(documentModel: document.model)
        }
        .onChange(of: document.model) { _, newModel in
            engineController.apply(documentModel: newModel)
        }
    }
}
