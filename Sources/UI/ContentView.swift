import AppKit
import SwiftUI

struct ContentView: View {
    @Binding var document: SeqAIDocument
    @State private var section: WorkspaceSection = .tracks
    @State private var scenesResetToken = 0
    @State private var visualPhraseControlsOpenIndex: Int?
    @State private var visualScenarioWindow: NSWindow?
    @State private var visualScenarioCommandTask: Task<Void, Never>?
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    private var sectionBinding: Binding<WorkspaceSection> {
        Binding(
            get: { section },
            set: { newSection in
                let previousSection = section
                if newSection == .scenes {
                    scenesResetToken += 1
                }
                section = newSection
                if previousSection != newSection {
                    SequencerTimingProbe.viewSwitch(
                        from: previousSection.rawValue,
                        to: newSection.rawValue,
                        mode: session.workspaceMode.rawValue
                    )
                }
            }
        )
    }

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()

            VStack(spacing: 12) {
                StudioTopBar(section: sectionBinding, document: $document)
                WorkspaceDetailView(
                    document: $document,
                    section: sectionBinding,
                    scenesResetToken: scenesResetToken,
                    visualPhraseControlsOpenIndex: $visualPhraseControlsOpenIndex
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The rounded stage plate this gutter once framed is gone
                    // (bold-flat); keep just enough to clear the window edge.
                    .padding(.horizontal, StudioMetrics.Spacing.tight)
                    .padding(.bottom, StudioMetrics.Spacing.tight)
            }
        }
        .background(
            VisualScenarioWindowReader { window in
                visualScenarioWindow = window
            }
        )
        .onAppear {
            guard visualScenarioCommandTask == nil else { return }
            visualScenarioCommandTask = Task {
                await VisualScenarioCommandRunner.runIfConfigured(
                    section: sectionBinding,
                    visualPhraseControlsOpenIndex: $visualPhraseControlsOpenIndex,
                    session: session,
                    engineController: engineController,
                    owningWindow: { visualScenarioWindow }
                )
            }
        }
        .onDisappear {
            visualScenarioCommandTask?.cancel()
            visualScenarioCommandTask = nil
        }
    }
}

private struct VisualScenarioWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
