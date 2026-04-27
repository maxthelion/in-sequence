import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void
    let onOpenScenes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Mixer", eyebrow: "Track strips active now", accent: StudioTheme.cyan) {
                MixerView(document: $document, onEditTrack: onSelectTrack)
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Scenes", eyebrow: "Master bus scene slots and macros", accent: StudioTheme.amber) {
                    VStack(alignment: .leading, spacing: 12) {
                        ScenesSummary()
                        Button {
                            onOpenScenes()
                        } label: {
                            Label("Open Scenes", systemImage: "square.stack.3d.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.amber)
                    }
                }

                StudioPanel(title: "Voice Routes", eyebrow: "Future drum and sliced-loop mixer coverage", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Tagged Voices", detail: "Drum and slice tracks")
                        StudioPlaceholderTile(title: "Per-Voice Treatment", detail: "Mute, bus, FX, and gain")
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct ScenesSummary: View {
    @Environment(SequencerDocumentSession.self) private var session

    private var masterBus: MasterBusState {
        session.store.masterBus
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(StudioTheme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(masterBus.activeScene.name)
                    .studioText(.bodyEmphasis)
                    .foregroundStyle(StudioTheme.text)
                Text(summary)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
    }

    private var summary: String {
        if let selection = masterBus.abSelection,
           let sceneA = masterBus.scene(id: selection.sceneAID),
           let sceneB = masterBus.scene(id: selection.sceneBID)
        {
            return "\(sceneA.name) / \(sceneB.name) - \(Int((selection.crossfader * 100).rounded()))%"
        }
        return "\(masterBus.scenes.count) scenes"
    }
}
