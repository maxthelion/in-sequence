import SwiftUI

struct LibraryWorkspaceView: View {
    private struct LibraryTile: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let accent: Color
    }

    private let libraryTiles: [LibraryTile] = [
        LibraryTile(title: "Templates", body: "Tagged rhythmic starting points for tracks and future drum voices.", accent: StudioTheme.cyan),
        LibraryTile(title: "Voice Presets", body: "Per-track interpretation maps and generator identities.", accent: StudioTheme.success),
        LibraryTile(title: "Fill Presets", body: "Reusable performance and phrase-level modulation packs.", accent: StudioTheme.amber),
        LibraryTile(title: "Takes", body: "Captured generated material that can be frozen into clips later.", accent: StudioTheme.violet),
        LibraryTile(title: "Chord Presets", body: "Reusable chord-gen and harmonic context sources.", accent: StudioTheme.cyan),
        LibraryTile(title: "Slice Sets", body: "Future audio slicing metadata and tagged loop content.", accent: StudioTheme.amber),
        LibraryTile(title: "Phrases", body: "Reusable phrase-level macro and pipeline definitions.", accent: StudioTheme.violet)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Library", eyebrow: "App-support folders and future browsing surface", accent: StudioTheme.violet) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(libraryTiles) { tile in
                        StudioPlaceholderTile(title: tile.title, detail: tile.body, accent: tile.accent)
                    }
                }
            }

            StudioPanel(title: "Why This Exists Now", eyebrow: "Planned state coverage", accent: StudioTheme.cyan) {
                Text("The app support bootstrap already creates the library folders. This placeholder keeps the destination visible in the shell now, so later plans can add preset browsers, phrase libraries, and sample/slice sets without another structural nav rewrite.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(20)
    }
}
