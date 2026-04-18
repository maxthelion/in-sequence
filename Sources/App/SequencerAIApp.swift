import SwiftUI

@main
struct SequencerAIApp: App {
    @State private var engineController = EngineController(audioOutput: AudioInstrumentHost())

    init() {
        do {
            let root = try AppSupportBootstrap.appSupportRoot()
            try AppSupportBootstrap.ensureLibraryStructure(root: root)
        } catch {
            // Non-fatal: the app can run without the library directory, it just won't find presets.
            // Logging only; UI will surface the issue via the Library view (future task).
            NSLog("AppSupportBootstrap failed: \(error)")
        }

        // Touch the shared session so MIDI is initialized at app launch.
        _ = MIDISession.shared
    }

    var body: some Scene {
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            ContentView(document: file.$document)
                .environment(engineController)
        }

        Settings {
            PreferencesView()
        }
    }
}
