import SwiftUI

struct SequencerDocumentRootView: View {
    @Binding var document: SeqAIDocument
    @State private var session: SequencerDocumentSession

    init(document: Binding<SeqAIDocument>) {
        self._document = document
        self._session = State(initialValue: SequencerDocumentSession(document: document))
    }

    var body: some View {
        ContentView(document: $document)
            .environment(session.engineController)
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
