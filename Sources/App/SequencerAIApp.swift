import SwiftUI

@main
struct SequencerAIApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            ContentView(document: file.$document)
        }

        Settings {
            PreferencesView()
        }
    }
}
