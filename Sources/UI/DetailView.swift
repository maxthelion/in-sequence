import SwiftUI

struct DetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @Environment(EngineController.self) private var engineController
    @State private var liveLayerID = "pattern"
    @State private var isEditingTrackName = false
    @FocusState private var trackNameFieldFocused: Bool

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var phrase: PhraseModel {
        document.model.selectedPhrase
    }

    private var selectedPatternIndex: Int {
        document.model.selectedPatternIndex(for: track.id)
    }

    private var occupiedPatternSlots: Set<Int> {
        Set(
            document.model.phrases.map { phrase in
                phrase.patternIndex(for: track.id, layers: document.model.layers)
            }
        )
    }

    private var outboundRouteCount: Int {
        document.model.routesSourced(from: track.id).count
    }

    private var sourceAccent: Color {
        switch track.trackType {
        case .monoMelodic, .polyMelodic:
            return StudioTheme.cyan
        case .slice:
            return StudioTheme.violet
        }
    }

    private var sourceEyebrow: String {
        "\(phrase.name) • P\(selectedPatternIndex + 1)"
    }

    var body: some View {
        ScrollView {
            workspace
                .padding(6)
        }
        .background(StudioTheme.stageFill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var workspace: some View {
        switch section {
        case .song:
            songWorkspace
        case .phrase:
            phraseWorkspace
        case .tracks:
            tracksWorkspace
        case .track:
            trackWorkspace
        case .mixer:
            mixerWorkspace
        case .live:
            liveWorkspace
        case .library:
            libraryWorkspace
        }
    }

    private var songWorkspace: some View {
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

    private var phraseWorkspace: some View {
        PhraseWorkspaceView(document: $document)
            .padding(10)
    }

    private var tracksWorkspace: some View {
        TracksMatrixView(document: $document) {
            section = .track
        }
        .padding(20)
    }

    private var trackWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            trackWorkspaceHeader

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    trackSourceColumn
                        .frame(minWidth: 640, maxWidth: .infinity, alignment: .topLeading)

                    trackDestinationColumn
                        .frame(width: 360, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    trackSourceColumn
                    trackDestinationColumn
                }
            }
        }
        .padding(20)
        .onChange(of: isEditingTrackName) {
            if isEditingTrackName {
                trackNameFieldFocused = true
            }
        }
    }

    private var trackSourceColumn: some View {
        TrackSourceEditorView(document: $document, accent: sourceAccent)
    }

    private var trackDestinationColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Destination", eyebrow: "Current sink and routing target", accent: StudioTheme.success) {
                TrackDestinationEditor(document: $document)
            }

            if outboundRouteCount > 0 {
                StudioPanel(
                    title: "Routing",
                    eyebrow: "\(outboundRouteCount) outbound project route\(outboundRouteCount == 1 ? "" : "s")",
                    accent: StudioTheme.violet
                ) {
                    RoutesListView(document: $document)
                }
            }
        }
    }

    private var trackWorkspaceHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if isEditingTrackName {
                    TextField("Track Name", text: trackNameBinding)
                        .textFieldStyle(.roundedBorder)
                        .focused($trackNameFieldFocused)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .onSubmit {
                            isEditingTrackName = false
                        }
                } else {
                    Text(track.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .onTapGesture(count: 2) {
                            isEditingTrackName = true
                        }
                }
            }

            Spacer()
        }
    }

    private var mixerWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Mixer", eyebrow: "Track strips active now, buses and sends planned", accent: StudioTheme.cyan) {
                MixerView(document: $document) { trackID in
                    document.model.selectTrack(id: trackID)
                    section = .track
                }
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

    private var liveWorkspace: some View {
        StudioPanel(
            title: "Live",
            eyebrow: "Current phrase cells under direct transport control",
            accent: StudioTheme.amber
        ) {
            LiveWorkspaceView(document: $document, selectedLayerID: $liveLayerID)
        }
        .padding(20)
    }

    private var libraryWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Library", eyebrow: "App-support folders and future browsing surface", accent: StudioTheme.violet) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(libraryTiles, id: \.title) { tile in
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

    private var trackNameBinding: Binding<String> {
        Binding(
            get: { document.model.selectedTrack.name },
            set: { document.model.selectedTrack.name = $0 }
        )
    }

    private var libraryTiles: [(title: String, body: String, accent: Color)] {
        [
            ("Templates", "Tagged rhythmic starting points for tracks and future drum voices.", StudioTheme.cyan),
            ("Voice Presets", "Per-track interpretation maps and generator identities.", StudioTheme.success),
            ("Fill Presets", "Reusable performance and phrase-level modulation packs.", StudioTheme.amber),
            ("Takes", "Captured generated material that can be frozen into clips later.", StudioTheme.violet),
            ("Chord Presets", "Reusable chord-gen and harmonic context sources.", StudioTheme.cyan),
            ("Slice Sets", "Future audio slicing metadata and tagged loop content.", StudioTheme.amber),
            ("Phrases", "Reusable phrase-level macro and pipeline definitions.", StudioTheme.violet)
        ]
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

private struct MacroRowPlaceholder: View {
    let name: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("AUTHORED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(accent)
            }

            HStack(spacing: 8) {
                ForEach(0..<16, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(step % 4 == 0 ? accent.opacity(0.82) : accent.opacity(0.35))
                        .frame(height: CGFloat(14 + (step % 5) * 8))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
    }
}

private struct PhrasePipelineNode: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(StudioTheme.cyan)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PerformPad: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [StudioTheme.amber.opacity(0.75), StudioTheme.cyan.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 88)
                .overlay(alignment: .topLeading) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.text)
                        .padding(12)
                }

            Text("momentary / latch")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}

#Preview {
    DetailPreview()
}

private struct DetailPreview: View {
    @State private var document = SeqAIDocument()
    @State private var section: WorkspaceSection = .track

    var body: some View {
        DetailView(document: $document, section: $section)
            .padding()
            .background(StudioTheme.background)
            .environment(EngineController(client: nil, endpoint: nil))
    }
}
