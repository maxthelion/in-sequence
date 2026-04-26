import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @State private var section: WorkspaceSection = .tracks

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()

            VStack(spacing: 14) {
                StudioTopBar(section: $section, document: $document)
                WorkspaceDetailView(document: $document, section: $section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        #if DEBUG
        .background {
            WorkspaceHitTestDiagnostics(label: "ContentView", section: section)
        }
        #endif
    }
}
