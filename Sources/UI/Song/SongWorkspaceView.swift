import SwiftUI

struct SongWorkspaceView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Song", eyebrow: "Phrase refs, repeats, and arrangement flow", accent: StudioTheme.violet) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        SongPhraseRefCard(title: "A", repeats: 2, detail: "Main phrase")
                        SongPhraseRefCard(title: "A Fill", repeats: 1, detail: "Conditional lift")
                        SongPhraseRefCard(title: "B", repeats: 4, detail: "Contrast section")
                        SongPhraseRefCard(title: "Outro", repeats: 1, detail: "Stop / tail")
                    }

                    Text("Planned from the north-star song layer: phrase-ref chain, per-ref overrides, conditional swaps, and arrangement timing. This is a placeholder shell so the future Song editor has a real home in the main studio surface.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Coverage", eyebrow: "Sub-spec 3 placeholder", accent: StudioTheme.cyan) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Phrase Ref Chain", detail: "Ordered list of phrase refs with repeats, offsets, and alternate occurrences.")
                        StudioPlaceholderTile(title: "Overrides", detail: "Per-ref macro row offsets like intensity lifts or transpose changes.")
                        StudioPlaceholderTile(title: "Conditions", detail: "Every-8th replacement, fill-only substitutions, and jump logic.")
                    }
                }

                StudioPanel(title: "Transport Story", eyebrow: "What the Song layer controls", accent: StudioTheme.amber) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Global Timeline", detail: "Absolute step, bar, phrase repeat count, and phrase transitions.")
                        StudioPlaceholderTile(title: "Scene Pacing", detail: "How long each phrase stays active and when the next ref takes over.")
                        StudioPlaceholderTile(title: "Future View", detail: "Arranger lanes, phrase blocks, jump markers, and automation summaries.")
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct SongPhraseRefCard: View {
    let title: String
    let repeats: Int
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(StudioTheme.text)

            Text("×\(repeats)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.cyan)

            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
