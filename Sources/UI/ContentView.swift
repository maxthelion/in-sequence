import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            DetailView()
        } detail: {
            InspectorView()
        }
    }
}
