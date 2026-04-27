import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Mixer", eyebrow: "Track strips active now", accent: StudioTheme.cyan) {
                MixerView(document: $document, onEditTrack: onSelectTrack)
            }

            StudioPanel(title: "Voice Routes", eyebrow: "Future drum and sliced-loop mixer coverage", accent: StudioTheme.violet) {
                VStack(spacing: 12) {
                    StudioPlaceholderTile(title: "Tagged Voices", detail: "Drum and slice tracks")
                    StudioPlaceholderTile(title: "Per-Voice Treatment", detail: "Mute, bus, FX, and gain")
                }
            }
        }
        .padding(20)
    }
}
