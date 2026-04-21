import SwiftUI

@main
struct SequencerAIApp: App {
    @NSApplicationDelegateAdaptor(SequencerAIAppDelegate.self) private var appDelegate
    @State private var engineController = EngineController(
        audioOutput: AudioInstrumentHost(),
        audioOutputFactory: { AudioInstrumentHost() }
    )

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
        DocumentGroup(newDocument: SeqAIDocument()) { file in
            configuredContentView(for: file)
        }
        .defaultSize(width: 1500, height: 960)

        Settings {
            PreferencesView()
        }
    }

    @MainActor
    private func configuredContentView(
        for file: FileDocumentConfiguration<SeqAIDocument>
    ) -> some View {
        appDelegate.engineController = engineController
        return ContentView(document: file.$document)
            .environment(engineController)
    }
}
