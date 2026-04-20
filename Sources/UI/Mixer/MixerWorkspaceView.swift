import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Mixer", eyebrow: "Track strips active now, buses and sends planned", accent: StudioTheme.cyan) {
                MixerView(document: $document, onEditTrack: onSelectTrack)
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Main / Alt Bus", eyebrow: "Planned from the phrase concrete rows", accent: StudioTheme.amber) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Bus Routing", detail: "Main and alt bus destinations will move here once the phrase macro rows land.")
                        StudioPlaceholderTile(title: "Send A / Send B", detail: "Per-track sends are called out in the spec and need visible homes in the mixer.")
                    }
                }

                StudioPanel(title: "Voice Routes", eyebrow: "Future drum and sliced-loop mixer coverage", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Tagged Voices", detail: "Drum and slice tracks will expose one strip per routed voice destination.")
                        StudioPlaceholderTile(title: "Per-Voice Treatment", detail: "Mute, bus, FX, and gain for kick/snare/hat or slice-tag destinations.")
                    }
                }
            }
        }
        .padding(20)
    }
}
