import SwiftUI

struct PitchAlgoEditor: View {
    let stage: PitchStage
    let inputClipChoices: [ClipPoolEntry]
    let harmonicSidechainClipChoices: [ClipPoolEntry]
    /// The one chrome accent of the hosting surface (track identity colour).
    var accent: Color = StudioTheme.cyan
    let onChange: (PitchStage) -> Void

    private var poolStage: PitchStage {
        PitchStage(
            algo: stage.algo.normalizedForPitchGrammar,
            harmonicSidechain: stage.harmonicSidechain
        )
    }

    var body: some View {
        if case let .pool(root, scale, spread, selection, deviation) = poolStage.algo {
            let normalizedSelection = selection.normalized
            let normalizedDeviation = deviation.normalized

            VStack(alignment: .leading, spacing: 12) {
                SourceParameterStepperRow(title: "Root", value: root, range: 0...127) {
                    onChange(PitchStage(
                        algo: .pool(root: $0, scale: scale, spread: spread, selection: normalizedSelection, deviation: normalizedDeviation),
                        harmonicSidechain: poolStage.harmonicSidechain
                    ))
                }
                scaleMenu(scale) {
                    onChange(PitchStage(
                        algo: .pool(root: root, scale: $0, spread: spread, selection: normalizedSelection, deviation: normalizedDeviation),
                        harmonicSidechain: poolStage.harmonicSidechain
                    ))
                }
                SourceParameterStepperRow(title: "Spread", value: spread, range: 0...36) {
                    onChange(PitchStage(
                        algo: .pool(root: root, scale: scale, spread: $0, selection: normalizedSelection, deviation: normalizedDeviation),
                        harmonicSidechain: poolStage.harmonicSidechain
                    ))
                }

                SourceParameterSliderRow(title: "Selection", value: (normalizedSelection.memory + 1) * 50, range: 0...100, accent: StudioTheme.violet) {
                    onChange(PitchStage(
                        algo: .pool(
                            root: root,
                            scale: scale,
                            spread: spread,
                            selection: PitchSelectionSettings(memory: ($0 / 50) - 1).normalized,
                            deviation: normalizedDeviation
                        ),
                        harmonicSidechain: poolStage.harmonicSidechain
                    ))
                }

                HStack(alignment: .top, spacing: 18) {
                    StudioRotaryKnob(
                        title: "Accidentals",
                        value: normalizedDeviation.accidentalChance * 100,
                        range: 0...100,
                        accent: StudioTheme.amber,
                        size: 56
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: spread,
                                selection: normalizedSelection,
                                deviation: PitchDeviationSettings(
                                    accidentalChance: $0 / 100,
                                    octaveSpan: normalizedDeviation.octaveSpan,
                                    leadingChance: normalizedDeviation.leadingChance
                                ).normalized
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Octaves",
                        value: Double(normalizedDeviation.octaveSpan),
                        range: 0...3,
                        accent: StudioTheme.cyan,
                        size: 56
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: spread,
                                selection: normalizedSelection,
                                deviation: PitchDeviationSettings(
                                    accidentalChance: normalizedDeviation.accidentalChance,
                                    octaveSpan: Int($0.rounded()),
                                    leadingChance: normalizedDeviation.leadingChance
                                ).normalized
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }

                    StudioRotaryKnob(
                        title: "Leading",
                        value: normalizedDeviation.leadingChance * 100,
                        range: 0...100,
                        accent: StudioTheme.violet,
                        size: 56
                    ) {
                        onChange(PitchStage(
                            algo: .pool(
                                root: root,
                                scale: scale,
                                spread: spread,
                                selection: normalizedSelection,
                                deviation: PitchDeviationSettings(
                                    accidentalChance: normalizedDeviation.accidentalChance,
                                    octaveSpan: normalizedDeviation.octaveSpan,
                                    leadingChance: $0 / 100
                                ).normalized
                            ),
                            harmonicSidechain: poolStage.harmonicSidechain
                        ))
                    }
                }
            }
        }
    }

    /// Shared themed Scale menu (four algo cases carry one).
    private func scaleMenu(_ scale: ScaleID, onSelect: @escaping (ScaleID) -> Void) -> some View {
        StudioMenuPicker(
            title: "Scale",
            selection: Binding(get: { scale }, set: onSelect),
            options: ScaleID.allCases.map { StudioMenuPickerOption(label: $0.displayName, value: $0) },
            help: "Scale"
        )
    }
}

// MARK: - Display names (canon Rule 3 corollary: raw model/enum names never
// appear on screen — "minorPentatonic" reads as "Minor Pentatonic").

extension ScaleID {
    var displayName: String {
        switch self {
        case .chromatic: return "Chromatic"
        case .major: return "Major"
        case .naturalMinor: return "Natural Minor"
        case .harmonicMinor: return "Harmonic Minor"
        case .melodicMinor: return "Melodic Minor"
        case .majorPentatonic: return "Major Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        case .blues: return "Blues"
        case .dorian: return "Dorian"
        case .phrygian: return "Phrygian"
        case .lydian: return "Lydian"
        case .mixolydian: return "Mixolydian"
        case .locrian: return "Locrian"
        case .wholeTone: return "Whole Tone"
        case .diminished: return "Diminished"
        case .augmented: return "Augmented"
        case .gypsy: return "Gypsy"
        case .hungarianMinor: return "Hungarian Minor"
        case .akebono: return "Akebono"
        }
    }
}

extension ChordID {
    var displayName: String {
        switch self {
        case .majorTriad: return "Major"
        case .minorTriad: return "Minor"
        case .augmentedTriad: return "Augmented"
        case .diminishedTriad: return "Diminished"
        case .major7th: return "Major 7th"
        case .minor7th: return "Minor 7th"
        case .dominant7th: return "Dominant 7th"
        case .diminished7th: return "Diminished 7th"
        case .augmented7th: return "Augmented 7th"
        case .halfDiminished7th: return "Half-Diminished 7th"
        case .major6th: return "Major 6th"
        case .minor6th: return "Minor 6th"
        case .major9th: return "Major 9th"
        case .minor9th: return "Minor 9th"
        case .major11th: return "Major 11th"
        case .minor11th: return "Minor 11th"
        }
    }
}

extension StyleProfileID {
    var displayName: String {
        switch self {
        case .vocal: return "Vocal"
        case .balanced: return "Balanced"
        case .jazz: return "Jazz"
        }
    }
}

private struct HarmonicSidechainPickerChoice: Hashable, Identifiable {
    let value: HarmonicSidechainSource
    let title: String

    var id: String {
        switch value {
        case .none:
            return "none"
        case .projectChordContext:
            return "project-chord-context"
        case let .clip(id):
            return "clip-\(id.uuidString)"
        }
    }

    init(_ value: HarmonicSidechainSource, clipChoices: [ClipPoolEntry] = []) {
        self.value = value
        switch value {
        case .none:
            self.title = "None"
        case .projectChordContext:
            self.title = "Chord Context"
        case let .clip(id):
            self.title = clipChoices.first(where: { $0.id == id })?.name ?? "Clip"
        }
    }

    static func choices(from clipChoices: [ClipPoolEntry]) -> [HarmonicSidechainPickerChoice] {
        [
            HarmonicSidechainPickerChoice(.none, clipChoices: clipChoices),
            HarmonicSidechainPickerChoice(.projectChordContext, clipChoices: clipChoices),
        ] + clipChoices.map { clip in
            HarmonicSidechainPickerChoice(.clip(clip.id), clipChoices: clipChoices)
        }
    }
}
