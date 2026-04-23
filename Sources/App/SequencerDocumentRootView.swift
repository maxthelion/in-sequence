import SwiftUI

struct SequencerDocumentRootView: View {
    @Binding var document: SeqAIDocument
    let engineController: EngineController
    @State private var session: SequencerDocumentSession

    init(
        document: Binding<SeqAIDocument>,
        engineController: EngineController
    ) {
        self._document = document
        self.engineController = engineController
        self._session = State(initialValue: SequencerDocumentSession(document: document, engineController: engineController))
    }

    var body: some View {
        ContentView(document: $document)
            .environment(engineController)
            .environment(session)
            .onAppear {
                session.activate()
            }
            .onChange(of: document.project) { _, newProject in
                session.ingestExternalDocumentChange(newProject)
            }
            .onDisappear {
                session.flushToDocument()
            }
    }
}
