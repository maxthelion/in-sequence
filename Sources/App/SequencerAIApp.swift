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
        return DocumentSessionRootView(
            document: file.$document,
            engineController: engineController
        )
    }
}

private struct DocumentSessionRootView: View {
    @Binding var document: SeqAIDocument
    let engineController: EngineController
    @State private var session: SequencerDocumentSession

    init(document: Binding<SeqAIDocument>, engineController: EngineController) {
        self._document = document
        self.engineController = engineController
        self._session = State(initialValue: SequencerDocumentSession(document: document, engineController: engineController))
    }

    var body: some View {
        ContentView(document: $document)
            .environment(engineController)
            .environment(session)
            .onChange(of: document.project) { _, newModel in
                session.handleDocumentProjectChange(newModel)
            }
            .onDisappear {
                session.flushToDocument()
            }
    }
}
