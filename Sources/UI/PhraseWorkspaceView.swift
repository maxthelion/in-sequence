import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @State private var selectedBarIndex = 0

    private var phrase: PhraseModel {
        document.model.selectedPhrase
    }

    private var currentBarIndex: Int {
        min(selectedBarIndex, max(0, phrase.lengthBars - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(title: "Phrase", eyebrow: "Persisted phrase state for macro rows and track pipelines", accent: StudioTheme.cyan) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        StudioMetricPill(title: "Phrase", value: phrase.name, accent: StudioTheme.cyan)
                        StudioMetricPill(title: "Bars", value: "\(phrase.lengthBars)", accent: StudioTheme.amber)
                        StudioMetricPill(title: "Steps", value: "\(phrase.stepCount)", accent: StudioTheme.violet)
                        StudioMetricPill(title: "Bar Page", value: "\(currentBarIndex + 1) / \(phrase.lengthBars)", accent: StudioTheme.success)
                    }

                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Phrase Name")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)

                            TextField("Phrase Name", text: phraseNameBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Length")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)

                            Stepper("\(phrase.lengthBars) bars", value: phraseBarCountBinding, in: 1...16)
                                .foregroundStyle(StudioTheme.text)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("Previous Bar") {
                                selectedBarIndex = max(0, currentBarIndex - 1)
                            }
                            .buttonStyle(.bordered)
                            .disabled(currentBarIndex == 0)

                            Button("Next Bar") {
                                selectedBarIndex = min(max(0, phrase.lengthBars - 1), currentBarIndex + 1)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(StudioTheme.cyan)
                            .disabled(currentBarIndex >= phrase.lengthBars - 1)
                        }
                    }

                    Text("This is the first real Sub-spec 2 surface: phrase-owned macro rows and phrase-owned track source selection are now persisted in the document instead of being hard-coded in the engine or implied by the UI.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            StudioPanel(title: "Abstract Rows", eyebrow: "Author 16 steps at a time across the selected bar page", accent: StudioTheme.violet) {
                VStack(spacing: 14) {
                    ForEach(PhraseAbstractKind.allCases, id: \.self) { kind in
                        PhraseAbstractRowEditor(
                            row: row(for: kind),
                            accent: accent(for: kind),
                            currentBarIndex: currentBarIndex,
                            stepsPerBar: phrase.stepsPerBar,
                            onCycleStep: { stepIndex in
                                var updatedPhrase = phrase
                                updatedPhrase.cycleAbstractValue(for: kind, at: stepIndex)
                                document.model.selectedPhrase = updatedPhrase
                            },
                            onChangeSourceMode: { mode in
                                var updatedPhrase = phrase
                                updatedPhrase.setAbstractRowSourceMode(mode, for: kind)
                                document.model.selectedPhrase = updatedPhrase
                            }
                        )
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                StudioPanel(title: "Track Pipelines", eyebrow: "Phrase-scoped source selection lives here", accent: StudioTheme.amber) {
                    VStack(spacing: 12) {
                        ForEach(document.model.tracks, id: \.id) { track in
                            PhraseTrackPipelineCard(
                                track: track,
                                sourceBinding: instrumentSourceBinding(for: track)
                            )
                        }
                    }
                }

                StudioPanel(title: "What’s Next", eyebrow: "Remaining Sub-spec 2 surface area", accent: StudioTheme.success) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Concrete Rows", detail: "Mute, bus, send, fill, repeat, transpose, swing, and crossfader rows need the same phrase-owned treatment as the abstract rows.", accent: StudioTheme.success)
                        StudioPlaceholderTile(title: "Graph Shape", detail: "Phrase track pipelines currently persist the primary instrument source only. Transform blocks and graph wiring are the next level down.", accent: StudioTheme.violet)
                        StudioPlaceholderTile(title: "Engine Lift", detail: "The engine still uses a hard-coded live pipeline. The next integration slice should teach EngineController to build from the selected phrase's pipeline state.", accent: StudioTheme.amber)
                    }
                }
            }
        }
    }

    private var phraseNameBinding: Binding<String> {
        Binding(
            get: {
                phrase.name
            },
            set: { newValue in
                var updatedPhrase = phrase
                updatedPhrase.name = newValue
                document.model.selectedPhrase = updatedPhrase
            }
        )
    }

    private var phraseBarCountBinding: Binding<Int> {
        Binding(
            get: {
                phrase.lengthBars
            },
            set: { newValue in
                var updatedPhrase = phrase
                updatedPhrase.lengthBars = max(1, newValue)
                updatedPhrase = updatedPhrase.synced(with: document.model.tracks)
                document.model.selectedPhrase = updatedPhrase
                selectedBarIndex = min(selectedBarIndex, max(0, updatedPhrase.lengthBars - 1))
            }
        )
    }

    private func row(for kind: PhraseAbstractKind) -> PhraseAbstractRow {
        phrase.abstractRows.first(where: { $0.kind == kind }) ?? PhraseAbstractRow(kind: kind, values: Array(repeating: 0, count: phrase.stepCount))
    }

    private func accent(for kind: PhraseAbstractKind) -> Color {
        switch kind {
        case .intensity, .density:
            return StudioTheme.cyan
        case .register, .brightness:
            return StudioTheme.violet
        case .tension, .variance:
            return StudioTheme.amber
        }
    }

    private func instrumentSourceBinding(for track: StepSequenceTrack) -> Binding<PhraseInstrumentSource>? {
        guard track.trackType == .instrument else {
            return nil
        }

        return Binding(
            get: {
                phrase.instrumentSource(for: track.id)
            },
            set: { newValue in
                var updatedPhrase = phrase
                updatedPhrase.setInstrumentSource(newValue, for: track.id)
                document.model.selectedPhrase = updatedPhrase
            }
        )
    }
}

private struct PhraseAbstractRowEditor: View {
    let row: PhraseAbstractRow
    let accent: Color
    let currentBarIndex: Int
    let stepsPerBar: Int
    let onCycleStep: (Int) -> Void
    let onChangeSourceMode: (PhraseRowSourceMode) -> Void

    private var barValues: ArraySlice<Double> {
        let start = currentBarIndex * stepsPerBar
        let end = min(row.values.count, start + stepsPerBar)
        return row.values[start..<end]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.kind.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                Spacer()

                Picker(
                    row.kind.label,
                    selection: Binding(
                        get: { row.sourceMode },
                        set: { onChangeSourceMode($0) }
                    )
                ) {
                    ForEach(PhraseRowSourceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(barValues.enumerated()), id: \.offset) { offset, value in
                    Button {
                        guard row.sourceMode == .authored else {
                            return
                        }
                        onCycleStep(currentBarIndex * stepsPerBar + offset)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(fill(for: value))
                                .frame(height: max(12, 18 + (value * 54)))
                                .frame(maxWidth: .infinity, alignment: .bottom)

                            Text("\(offset + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(row.sourceMode == .generated)
                }
            }
            .frame(height: 94, alignment: .bottom)

            Text(row.sourceMode == .authored ? "Tap steps to cycle the authored value for this bar page." : "Generated mode is reserved for future row-writer pipelines and is intentionally read-only for now.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func fill(for value: Double) -> LinearGradient {
        LinearGradient(
            colors: [accent.opacity(value == 0 ? 0.18 : 0.92), accent.opacity(0.35)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct PhraseTrackPipelineCard: View {
    let track: StepSequenceTrack
    var sourceBinding: Binding<PhraseInstrumentSource>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                    Text(track.trackType.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                Text(track.output == .midiOut ? "MIDI" : "AU")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if let sourceBinding {
                Picker("Source", selection: sourceBinding) {
                    ForEach(PhraseInstrumentSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text(track.trackType == .drumRack ? "Drum lanes and tagged routing land here next." : "Slice playback and slice-tag routing land here in the audio-side plans.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
