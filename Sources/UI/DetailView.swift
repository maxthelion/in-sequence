import SwiftUI

struct DetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @Environment(EngineController.self) private var engineController

    private var track: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var phrase: PhraseModel {
        document.model.selectedPhrase
    }

    private var selectedSourceMode: TrackSourceMode {
        document.model.selectedSourceMode(for: track.id)
    }

    private var stepStates: [StepVisualState] {
        track.stepPattern.enumerated().map { index, isEnabled in
            guard isEnabled else {
                return .off
            }
            return track.stepAccents[index] ? .accented : .on
        }
    }

    private var sourceAccent: Color {
        switch track.trackType {
        case .instrument:
            return StudioTheme.cyan
        case .drumRack:
            return StudioTheme.amber
        case .sliceLoop:
            return StudioTheme.violet
        }
    }

    private var sourceEyebrow: String {
        "\(phrase.name) source • \(selectedSourceMode.label)"
    }

    private var sourceSummary: String {
        track.trackType == .instrument && selectedSourceMode.isImplemented ? "Live now" : "Planned"
    }

    private var destinationSummary: String {
        switch track.output {
        case .midiOut:
            return "MIDI sink"
        case .auInstrument:
            return "AU sink"
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
        PhraseWorkspaceView(document: $document)
            .padding(20)
    }

    private var trackWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: "Source", eyebrow: sourceEyebrow, accent: sourceAccent) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            StudioMetricPill(title: "Transport", value: engineController.transportPosition)
                            StudioMetricPill(title: "Phrase", value: phrase.name, accent: StudioTheme.success)
                            StudioMetricPill(title: "BPM", value: "\(Int(engineController.currentBPM.rounded()))", accent: StudioTheme.amber)
                            StudioMetricPill(title: "Type", value: track.trackType.shortLabel, accent: sourceAccent)
                            StudioMetricPill(title: "Source", value: selectedSourceMode.shortLabel, accent: sourceAccent)
                            StudioMetricPill(title: "Status", value: sourceSummary, accent: StudioTheme.violet)
                        }

                        TrackTypePalette(selectedTrackType: trackTypeBinding)
                        SourceModePalette(trackType: track.trackType, selectedSource: sourceModeBinding)

                        Text("The left side models how this track creates note material. Track type decides the editor shape; phrase-scoped source modes and transforms will later plug into that shape without forcing one giant persisted source enum.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }

                if track.trackType == .instrument && selectedSourceMode == .generator {
                    StudioPanel(title: track.name, eyebrow: engineController.statusSummary, accent: StudioTheme.cyan) {
                        VStack(alignment: .leading, spacing: 16) {
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

                            Text("This source is the current MVP note generator: one monophonic step pattern, one pitch cycle, and immediate velocity and gate controls.")
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

                    StudioPanel(title: "Generator", eyebrow: "Immediate controls for the manual mono source", accent: StudioTheme.amber) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Pitches")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)

                            TextField("Comma-separated MIDI notes", text: pitchesBinding)
                                .textFieldStyle(.roundedBorder)

                            ParameterSliderRow(title: "Velocity", value: Double(track.velocity), range: 1...127, accent: StudioTheme.amber) { newValue in
                                document.model.selectedTrack.velocity = Int(newValue.rounded())
                            }

                            ParameterSliderRow(title: "Gate Length", value: Double(track.gateLength), range: 1...16, accent: StudioTheme.violet) { newValue in
                                document.model.selectedTrack.gateLength = Int(newValue.rounded())
                            }
                        }
                    }
                } else if track.trackType == .instrument {
                    StudioPanel(title: selectedSourceMode.label, eyebrow: "Phrase-scoped source placeholder", accent: sourceAccent) {
                        VStack(spacing: 12) {
                            ForEach(instrumentSourcePlaceholderTiles, id: \.title) { tile in
                                StudioPlaceholderTile(title: tile.title, detail: tile.detail, accent: tile.accent)
                            }
                        }
                    }
                } else {
                    StudioPanel(title: track.trackType.label, eyebrow: "Planned source editor coverage", accent: sourceAccent) {
                        VStack(spacing: 12) {
                            ForEach(trackTypePlaceholderTiles, id: \.title) { tile in
                                StudioPlaceholderTile(title: tile.title, detail: tile.detail, accent: tile.accent)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: "Destination", eyebrow: "Project-scoped identity and current sink", accent: StudioTheme.success) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            StudioMetricPill(title: "Track", value: track.name, accent: StudioTheme.success)
                            StudioMetricPill(title: "Destination", value: destinationSummary, accent: StudioTheme.violet)
                        }

                        TextField("Track Name", text: trackNameBinding)
                            .textFieldStyle(.roundedBorder)

                        Picker("Track Type", selection: trackTypeBinding) {
                            ForEach(TrackType.allCases, id: \.self) { trackType in
                                Text(trackType.label).tag(trackType)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Output", selection: trackOutputBinding) {
                            ForEach(TrackOutputDestination.allCases, id: \.self) { destination in
                                Text(destination.label).tag(destination)
                            }
                        }
                        .pickerStyle(.segmented)

                        if document.model.selectedTrack.output == .auInstrument {
                            Picker("Instrument", selection: audioInstrumentBinding) {
                                ForEach(engineController.availableAudioInstruments, id: \.self) { instrument in
                                    Text(instrument.displayName).tag(instrument)
                                }
                            }
                        }
                    }
                }

                StudioPanel(title: "Routing", eyebrow: "Future sink-side controls and placeholders", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        ForEach(destinationPlaceholderTiles, id: \.title) { tile in
                            StudioPlaceholderTile(title: tile.title, detail: tile.detail, accent: tile.accent)
                        }
                    }
                }

                StudioPanel(title: "Track Contract", eyebrow: "What lives here versus elsewhere", accent: StudioTheme.amber) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Source Left / Destination Right", detail: "This track surface now treats note generation and note destination as separate concerns, matching the north-star pipeline model.", accent: StudioTheme.cyan)
                        StudioPlaceholderTile(title: "Mixer Lives In Mixer", detail: "Level, pan, mute, buses, sends, and per-voice strips stay in the Mixer workspace so the Track view can stay focused.", accent: StudioTheme.amber)
                        StudioPlaceholderTile(title: "Phrase Owns Graph Shape", detail: "The current shell is future-proofed for phrase-scoped pipelines: source placeholders on the left, sink placeholders on the right, graph details later in the Phrase workspace.", accent: StudioTheme.violet)
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

    private var trackNameBinding: Binding<String> {
        Binding(
            get: { document.model.selectedTrack.name },
            set: { document.model.selectedTrack.name = $0 }
        )
    }

    private var trackTypeBinding: Binding<TrackType> {
        Binding(
            get: { document.model.selectedTrack.trackType },
            set: { document.model.setSelectedTrackType($0) }
        )
    }

    private var trackOutputBinding: Binding<TrackOutputDestination> {
        Binding(
            get: { document.model.selectedTrack.output },
            set: { document.model.selectedTrack.output = $0 }
        )
    }

    private var audioInstrumentBinding: Binding<AudioInstrumentChoice> {
        Binding(
            get: { document.model.selectedTrack.audioInstrument },
            set: { document.model.selectedTrack.audioInstrument = $0 }
        )
    }

    private var sourceModeBinding: Binding<TrackSourceMode> {
        Binding(
            get: {
                document.model.selectedSourceMode(for: track.id)
            },
            set: { newValue in
                document.model.setSelectedPhraseSourceMode(newValue, for: track.id)
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

    private var trackTypePlaceholderTiles: [(title: String, detail: String, accent: Color)] {
        switch track.trackType {
        case .instrument:
            return []
        case .drumRack:
            return [
                ("Tagged Drum Source", "One logical source emits tagged notes for kick, snare, hats, and other voices.", StudioTheme.amber),
                ("Per-Voice Sequencing", "This is where multiple step lanes make sense: one row or lane per drum voice, not one monophonic pattern.", StudioTheme.cyan),
                ("Voice Route Link", "The destination side will eventually expose one sink route per voice tag.", StudioTheme.violet)
            ]
        case .sliceLoop:
            return [
                ("Slice Trigger Source", "A sliced loop behaves like a tagged note source where slices are the voices.", StudioTheme.violet),
                ("Planned Editor", "Waveform, slice boundaries, tags, and slice-trigger lanes will live here once the audio-side plans land.", StudioTheme.cyan),
                ("Shared Destination Story", "Slice tags route through the same future voice-route destination model as drums.", StudioTheme.amber)
            ]
        }
    }

    private var instrumentSourcePlaceholderTiles: [(title: String, detail: String, accent: Color)] {
        switch selectedSourceMode {
        case .generator:
            return []
        case .clip:
            return [
                ("Clip Reader", "Phrase-owned clip material with step annotations and later parameter locks.", StudioTheme.violet),
                ("Freeze / Stamp", "This source is where frozen generator output and hand-authored clips will land.", StudioTheme.cyan),
                ("Current Gap", "The phrase model now persists the source choice; the actual clip data/editor lands in the next block-focused slice.", StudioTheme.amber)
            ]
        case .template:
            return [
                ("Template Source", "Templates will stamp a starting point into the active phrase without changing the track's long-lived identity.", StudioTheme.amber),
                ("Library Link", "This mode will browse from the Templates library and preserve later phrase-specific edits.", StudioTheme.cyan),
                ("Current Gap", "Selection is now phrase-scoped and persisted; template asset loading is still to come.", StudioTheme.violet)
            ]
        case .midiIn:
            return [
                ("Live Feed", "External MIDI becomes a phrase-scoped source block rather than a global track setting.", StudioTheme.success),
                ("Capture + Monitor", "Planned controls include endpoint selection, thru, quantise, and capture behavior.", StudioTheme.cyan),
                ("Current Gap", "The phrase model now reserves this home; actual MIDI-in block plumbing is still ahead.", StudioTheme.amber)
            ]
        }
    }

    private var destinationPlaceholderTiles: [(title: String, detail: String, accent: Color)] {
        var tiles: [(title: String, detail: String, accent: Color)] = [
            ("Current Sink", track.output == .midiOut ? "The track currently targets a MIDI output endpoint." : "The track currently targets a hosted AU instrument through the app mixer.", StudioTheme.success),
            ("Bus / Sends", "Main-alt bus selection, send levels, and phrase concrete-row routing are planned here, not in the source editor.", StudioTheme.amber),
            ("FX / Treatment", "Per-track insert effects, AU MIDI processors, and destination-specific treatment belong on the sink side of the layout.", StudioTheme.violet)
        ]

        if track.trackType == .drumRack || track.trackType == .sliceLoop {
            tiles.append(("Voice Routes", "Tagged voices will each need their own route target so kick, snare, hats, or slices can hit different buses or instruments.", StudioTheme.cyan))
        } else {
            tiles.append(("Single Voice Route", "For non-tagged tracks this side stays simple: one source stream, one destination chain, optional transforms in between.", StudioTheme.cyan))
        }

        return tiles
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

private struct TrackTypePalette: View {
    @Binding var selectedTrackType: TrackType

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TrackType.allCases, id: \.self) { trackType in
                Button {
                    selectedTrackType = trackType
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trackType.label.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.9)
                            .foregroundStyle(StudioTheme.text)

                        Text(description(for: trackType))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(fill(for: trackType), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stroke(for: trackType), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func description(for trackType: TrackType) -> String {
        switch trackType {
        case .instrument:
            return "Single melodic voice with swappable phrase sources."
        case .drumRack:
            return "Tagged drum lanes and per-voice routing."
        case .sliceLoop:
            return "Slice triggers, waveform view, and routed slice voices."
        }
    }

    private func fill(for trackType: TrackType) -> Color {
        selectedTrackType == trackType ? accent(for: trackType).opacity(0.15) : Color.white.opacity(0.03)
    }

    private func stroke(for trackType: TrackType) -> Color {
        selectedTrackType == trackType ? accent(for: trackType).opacity(0.5) : StudioTheme.border
    }

    private func accent(for trackType: TrackType) -> Color {
        switch trackType {
        case .instrument:
            return StudioTheme.cyan
        case .drumRack:
            return StudioTheme.amber
        case .sliceLoop:
            return StudioTheme.violet
        }
    }
}

private struct SourceModePalette: View {
    let trackType: TrackType
    @Binding var selectedSource: TrackSourceMode

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            ForEach(TrackSourceMode.available(for: trackType), id: \.self) { source in
                Button {
                    selectedSource = source
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(source.label.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.9)
                                .foregroundStyle(StudioTheme.text)

                            Spacer(minLength: 8)

                            Text(source.isImplemented ? "LIVE" : "PLANNED")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.9)
                                .foregroundStyle(accent(for: source))
                        }

                        Text(source.detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(fill(for: source), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(stroke(for: source), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func accent(for source: TrackSourceMode) -> Color {
        switch source {
        case .generator:
            return StudioTheme.cyan
        case .clip:
            return StudioTheme.violet
        case .template:
            return StudioTheme.amber
        case .midiIn:
            return StudioTheme.success
        }
    }

    private func fill(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.14) : Color.white.opacity(0.03)
    }

    private func stroke(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.52) : StudioTheme.border
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
