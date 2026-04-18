import SwiftUI

@main
struct SequencerAIApp: App {
    init() {
        do {
            let root = try AppSupportBootstrap.appSupportRoot()
            try AppSupportBootstrap.ensureLibraryStructure(root: root)
        } catch {
            // Non-fatal: the app can run without the library directory, it just won't find presets.
            // Logging only; UI will surface the issue via the Library view (future task).
            NSLog("AppSupportBootstrap failed: \(error)")
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            ContentView(document: file.$document)
        }

        Settings {
            PreferencesView()
        }
    }
}
