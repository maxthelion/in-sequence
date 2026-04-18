import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @State private var section: WorkspaceSection = .trackEditor

    var body: some View {
        NavigationSplitView {
            SidebarView(document: $document, section: $section)
        } content: {
            DetailView(document: $document, section: $section)
        } detail: {
            InspectorView(document: $document)
        }
        .onAppear {
            engineController.apply(documentModel: document.model)
        }
        .onChange(of: document.model) { _, newModel in
            engineController.apply(documentModel: newModel)
        }
    }
}
