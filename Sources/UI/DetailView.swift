import SwiftUI

struct DetailView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @Environment(EngineController.self) private var engineController
    @State private var liveLayerID = "pattern"

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

    private var selectedPattern: TrackPatternSlot {
        document.model.selectedPattern(for: track.id)
    }

    private var selectedSourceMode: TrackSourceMode {
        selectedPattern.sourceRef.mode
    }

    private var outboundRouteCount: Int {
        document.model.routesSourced(from: track.id).count
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
            .padding(20)
    }

    private var tracksWorkspace: some View {
        TracksMatrixView(document: $document) {
            section = .track
        }
        .padding(20)
    }

    private var trackWorkspace: some View {
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
        .padding(20)
    }

    private var trackSourceColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Source", eyebrow: sourceEyebrow, accent: sourceAccent) {
                VStack(alignment: .leading, spacing: 16) {
                    PatternSlotPalette(
                        selectedSlot: selectedPatternIndexBinding,
                        occupiedSlots: occupiedPatternSlots
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SOURCE")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)

                        SourceModePalette(trackType: track.trackType, selectedSource: selectedPatternSourceModeBinding)
                    }

                    TextField("Pattern Name", text: patternNameBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if track.trackType == .monoMelodic && selectedSourceMode == .generator {
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
            } else if track.trackType == .monoMelodic || track.trackType == .polyMelodic {
                StudioPanel(title: selectedSourceMode.label, eyebrow: "Pattern-slot placeholder", accent: sourceAccent) {
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
    }

    private var trackDestinationColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Destination", eyebrow: "Project-scoped identity and current sink", accent: StudioTheme.success) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Track Name", text: trackNameBinding)
                        .textFieldStyle(.roundedBorder)

                    Picker("Track Type", selection: trackTypeBinding) {
                        ForEach(TrackType.allCases, id: \.self) { trackType in
                            Text(trackType.label).tag(trackType)
                        }
                    }
                    .pickerStyle(.segmented)

                    TrackDestinationEditor(document: $document)
                }
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

    private var selectedPatternIndexBinding: Binding<Int> {
        Binding(
            get: { document.model.selectedPatternIndex(for: track.id) },
            set: { document.model.setSelectedPatternIndex($0, for: track.id) }
        )
    }

    private var selectedPatternSourceModeBinding: Binding<TrackSourceMode> {
        Binding(
            get: { document.model.selectedSourceMode(for: track.id) },
            set: { newValue in
                document.model.setPatternSourceMode(newValue, for: track.id, slotIndex: selectedPatternIndex)
            }
        )
    }

    private var patternNameBinding: Binding<String> {
        Binding(
            get: { selectedPattern.name ?? "" },
            set: { newValue in
                document.model.setPatternName(newValue, for: track.id, slotIndex: selectedPatternIndex)
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
        case .monoMelodic:
            return []
        case .polyMelodic:
            return [
                ("Poly Source", "Poly tracks will author multi-note events instead of the current monophonic step lane.", StudioTheme.cyan),
                ("Chord-Aware Editing", "This is where chord clips, voiced generators, and held-note editing will land.", StudioTheme.violet),
                ("Shared Destination Story", "Poly tracks still route into the same destination model on the right.", StudioTheme.amber)
            ]
        case .slice:
            return [
                ("Slice Trigger Source", "A sliced loop behaves like a tagged note source where slices are the voices.", StudioTheme.violet),
                ("Planned Editor", "Waveform, slice boundaries, tags, and slice-trigger lanes will live here once the audio-side plans land.", StudioTheme.cyan),
                ("Shared Destination Story", "Slice tags route through the same future voice-route destination model as grouped mono tracks.", StudioTheme.amber)
            ]
        }
    }

    private var instrumentSourcePlaceholderTiles: [(title: String, detail: String, accent: Color)] {
        switch selectedSourceMode {
        case .generator:
            return []
        case .clip:
            return [
                ("Clip Reader", "This slot points at a shared clip-pool entry instead of a generator instance.", StudioTheme.violet),
                ("Shared Pool Semantics", "Editing the clip entry will affect every pattern slot and phrase that references it.", StudioTheme.cyan),
                ("Current Gap", "The pattern bank now persists clip slots; the actual clip editor and freeze flow are still ahead.", StudioTheme.amber)
            ]
        }
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

private struct SourceModePalette: View {
    let trackType: TrackType
    @Binding var selectedSource: TrackSourceMode

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TrackSourceMode.available(for: trackType), id: \.self) { source in
                Button {
                    selectedSource = source
                } label: {
                    HStack(spacing: 8) {
                        Text(source.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        if !source.isImplemented {
                            Text("Planned")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(accent(for: source))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
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
        }
    }

    private func fill(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.14) : Color.white.opacity(0.03)
    }

    private func stroke(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.52) : StudioTheme.border
    }
}

private struct PatternSlotPalette: View {
    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PATTERN BANK")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 6) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                    Button {
                        selectedSlot = slotIndex
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(slotIndex + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)

                            Circle()
                                .fill(indicatorFill(for: slotIndex))
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(backgroundFill(for: slotIndex))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(borderColor(for: slotIndex), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func backgroundFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.2)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.08)
        }
        return Color.white.opacity(0.03)
    }

    private func borderColor(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.7)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.28)
        }
        return StudioTheme.border
    }

    private func indicatorFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.6)
        }
        return Color.white.opacity(0.08)
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
