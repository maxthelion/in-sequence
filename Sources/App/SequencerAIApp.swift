import SwiftUI

@main
struct SequencerAIApp: App {
    @NSApplicationDelegateAdaptor(SequencerAIAppDelegate.self) private var appDelegate

    init() {
        do {
            let root = try AppSupportBootstrap.appSupportRoot()
            try AppSupportBootstrap.ensureLibraryStructure(root: root)
        } catch {
            // Non-fatal: the app can run without the library directory, it just won't find presets.
            // Logging only; UI will surface the issue via the Library view (future task).
            NSLog("AppSupportBootstrap failed: \(error)")
        }

        do {
            _ = try SampleLibraryBootstrap.ensureLibraryInstalled()
        } catch {
            NSLog("[SequencerAIApp] sample library bootstrap failed: \(error)")
        }
        _ = AudioSampleLibrary.shared   // warm the singleton; subsequent reads are cheap

        // Touch the shared session so MIDI is initialized at app launch.
        _ = MIDISession.shared
    }

    var body: some Scene {
        DocumentGroup(newDocument: { SeqAIDocument() }) { file in
            // SeqAIDocument is a ReferenceFileDocument (class). The session and all
            // views receive a Binding<SeqAIDocument> whose getter returns the stable
            // reference. Mutations to `document.project` go directly to the class
            // instance; the binding setter is intentionally unused.
            let doc = file.document
            let binding = Binding<SeqAIDocument>(
                get: { doc },
                set: { _ in }
            )
            SequencerDocumentRootView(document: binding)
        }
        .defaultSize(width: 1500, height: 960)

        Settings {
            PreferencesView()
        }
    }
}
