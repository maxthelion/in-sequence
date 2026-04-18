import SwiftUI

struct DetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @Environment(EngineController.self) private var engineController

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var stepStates: [StepVisualState] {
        track.stepPattern.enumerated().map { index, isEnabled in
            guard isEnabled else {
                return .off
            }
            return track.stepAccents[index] ? .accented : .on
        }
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
        case .track:
            trackWorkspace
        case .mixer:
            mixerWorkspace
        case .perform:
            performWorkspace
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
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Phrase", eyebrow: "Macro grid and phrase-scoped pipeline graph", accent: StudioTheme.cyan) {
                VStack(spacing: 14) {
                    MacroRowPlaceholder(name: "Intensity", accent: StudioTheme.cyan)
                    MacroRowPlaceholder(name: "Density", accent: StudioTheme.success)
                    MacroRowPlaceholder(name: "Register", accent: StudioTheme.violet)
                    MacroRowPlaceholder(name: "Tension", accent: StudioTheme.amber)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Planned Phrase Surface", eyebrow: "Sub-spec 2 placeholder", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Abstract Rows", detail: "Intensity, density, register, tension, variance, and brightness over the phrase.")
                        StudioPlaceholderTile(title: "Concrete Rows", detail: "Mute, bus, send-A, send-B, fill flag, repeat amount, order preset, transpose, and swing.")
                        StudioPlaceholderTile(title: "Row Source Toggle", detail: "Authored rows can later switch to generated sources without moving screens.")
                    }
                }

                StudioPanel(title: "Pipeline Graph", eyebrow: "Blocks that will live under the phrase", accent: StudioTheme.amber) {
                    VStack(spacing: 12) {
                        PhrasePipelineNode(title: "Chord Context", detail: "Phrase-scoped chord generator feeding downstream tracks.")
                        PhrasePipelineNode(title: "Track Pipelines", detail: "Per-track source → transform → sink graph.")
                        PhrasePipelineNode(title: "Macro Writers", detail: "Generated rows that write back into macro coordinates.")
                    }
                }
            }
        }
        .padding(20)
    }

    private var trackWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: track.name, eyebrow: engineController.statusSummary, accent: StudioTheme.cyan) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            StudioMetricPill(title: "Transport", value: engineController.transportPosition)
                            StudioMetricPill(title: "BPM", value: "\(Int(engineController.currentBPM.rounded()))", accent: StudioTheme.amber)
                            StudioMetricPill(title: "Output", value: track.output == .midiOut ? "MIDI" : "AU", accent: StudioTheme.violet)
                        }

                        StepGridView(stepStates: stepStates) { index in
                            document.model.selectedTrack.cycleStep(at: index)
                        }

                        HStack(spacing: 10) {
                            Button("Accent Downbeats") {
                                document.model.selectedTrack.accentDownbeats()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(StudioTheme.amber)

                            Button("Clear Accents") {
                                document.model.selectedTrack.clearAccents()
                            }
                            .buttonStyle(.bordered)
                            .disabled(track.accentedStepCount == 0)
                        }

                        Text("The track surface owns the live pattern, note accents, voice routing, and generator controls. Phrase and song editing will stay separate so this view can stay focused and immediate.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                StudioPanel(title: "Pitch Cycle", eyebrow: "Selected pitches used by the note generator", accent: StudioTheme.violet) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(track.pitches.enumerated()), id: \.offset) { index, pitch in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("STEP \(index + 1)")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .tracking(0.8)
                                        .foregroundStyle(StudioTheme.mutedText)
                                    Text("\(pitch)")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(StudioTheme.text)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(StudioTheme.border, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: "Track Voice", eyebrow: "Project-scoped identity and sink", accent: StudioTheme.success) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Track Name", text: $document.model.selectedTrack.name)
                            .textFieldStyle(.roundedBorder)

                        Picker("Output", selection: $document.model.selectedTrack.output) {
                            ForEach(TrackOutputDestination.allCases, id: \.self) { destination in
                                Text(destination.label).tag(destination)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Pitches")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)

                        TextField("Comma-separated MIDI notes", text: pitchesBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                StudioPanel(title: "Generator", eyebrow: "Immediate note-gen controls", accent: StudioTheme.amber) {
                    VStack(spacing: 14) {
                        ParameterSliderRow(title: "Velocity", value: Double(track.velocity), range: 1...127, accent: StudioTheme.amber) { newValue in
                            document.model.selectedTrack.velocity = Int(newValue.rounded())
                        }

                        ParameterSliderRow(title: "Gate Length", value: Double(track.gateLength), range: 1...16, accent: StudioTheme.violet) { newValue in
                            document.model.selectedTrack.gateLength = Int(newValue.rounded())
                        }
                    }
                }

                StudioPanel(title: "Mixer", eyebrow: "Per-track level, pan, and mute", accent: StudioTheme.cyan) {
                    VStack(spacing: 14) {
                        ParameterSliderRow(title: "Level", value: track.mix.clampedLevel, range: 0...1, accent: StudioTheme.cyan) { newValue in
                            document.model.selectedTrack.mix.level = newValue
                        }

                        ParameterSliderRow(title: "Pan", value: track.mix.clampedPan, range: -1...1, accent: StudioTheme.violet) { newValue in
                            document.model.selectedTrack.mix.pan = newValue
                        }

                        Toggle(isOn: $document.model.selectedTrack.mix.isMuted) {
                            Text("Mute Track")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                        }
                        .toggleStyle(.switch)
                    }
                }
            }
            .frame(width: 320)
        }
        .padding(20)
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

    private var performWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Perform", eyebrow: "Non-destructive overlay inspired by Polyend Play", accent: StudioTheme.amber) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(["Fill", "Stutter", "Roll", "Mute", "Filter", "Scatter", "Reverse", "Recall"], id: \.self) { effect in
                        PerformPad(title: effect)
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Planned Coverage", eyebrow: "Spec-driven placeholder", accent: StudioTheme.cyan) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Track Selection", detail: "Choose a subset of tracks for momentary or latched performance actions.")
                        StudioPlaceholderTile(title: "Workspace Recall", detail: "Save/recall a known-good live state without mutating stored phrase content.")
                        StudioPlaceholderTile(title: "Punch-In Effects", detail: "Live order, repeat, density, bus, and macro overrides that revert on exit.")
                    }
                }

                StudioPanel(title: "Current Status", eyebrow: "What exists today", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Engine Routing", detail: "Track playback and transport are live, so this screen can grow into a true overlay instead of a mock app page.")
                        StudioPlaceholderTile(title: "Next Step", detail: "Wire perform actions into the command path once the phrase macro coordinator exists.")
                    }
                }
            }
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

    private var pitchesBinding: Binding<String> {
        Binding(
            get: {
                document.model.selectedTrack.pitches.map(String.init).joined(separator: ", ")
            },
            set: { newValue in
                let parsed = newValue
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (0...127).contains($0) }

                guard !parsed.isEmpty else {
                    return
                }

                document.model.selectedTrack.pitches = parsed
            }
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

private struct ParameterSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let onChange: (Double) -> Void

    @State private var draftValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.text)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            .tint(accent)
        }
    }

    private var formattedValue: String {
        if range.upperBound <= 1.0 && range.lowerBound >= 0 {
            return "\(Int((value * 100).rounded()))%"
        }
        if range.lowerBound == -1 && range.upperBound == 1 {
            if value < -0.05 {
                return "L\(Int(abs(value) * 100))"
            }
            if value > 0.05 {
                return "R\(Int(value * 100))"
            }
            return "C"
        }
        return "\(Int(value.rounded()))"
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
