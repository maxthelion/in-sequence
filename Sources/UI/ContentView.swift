import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    var body: some View {
        NavigationSplitView {
            SidebarView(document: $document)
        } content: {
            DetailView(document: $document)
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
