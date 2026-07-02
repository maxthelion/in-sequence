import SwiftUI

// MARK: - MacroKnobRowViewModel

/// Pure model logic for the live macro knob row in `LiveWorkspaceView`.
///
/// A knob drag writes to `layer.defaults[trackID]` in the project — it does NOT
/// overwrite existing per-step cells. This keeps arrangement automation intact
/// while letting Live view feel like a live performance controller.
///
/// This is testable in isolation without SwiftUI.
struct MacroKnobRowViewModel {

    /// Returns the current resolved double value for a macro binding on a track.
    /// Resolution order (live view, no step context):
    ///   1. Layer default (what the knob writes to).
    ///   2. Descriptor default.
    func currentValue(
        binding: TrackMacroBinding,
        trackID: UUID,
        layers: [PhraseLayerDefinition]
    ) -> Double {
        let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
        guard let layer = layers.first(where: { $0.id == layerID }) else {
            return binding.descriptor.defaultValue
        }
        switch layer.defaults[trackID] {
        case let .scalar(v): return v
        default: return binding.descriptor.defaultValue
        }
    }

    /// Convenience overload accepting a `Project` — kept for test backwards compatibility.
    func currentValue(
        binding: TrackMacroBinding,
        trackID: UUID,
        project: Project
    ) -> Double {
        currentValue(binding: binding, trackID: trackID, layers: project.layers)
    }

    /// Write a live knob value into the phrase layer default.
    ///
    /// Does NOT modify phrase cells — caller is responsible for applying the
    /// updated project to the engine.
    func applyLiveValue(
        _ value: Double,
        binding: TrackMacroBinding,
        trackID: UUID,
        project: inout Project
    ) {
        project.setMacroLayerDefault(
            value: value,
            bindingID: binding.id,
            trackID: trackID,
            phraseID: project.selectedPhraseID
        )
    }
}

// MARK: - MacroKnobRow

/// A horizontal strip of macro knobs for the currently selected track.
/// Shown in Live view below the pattern grid.
/// Each knob writes to the phrase layer default on drag commit.
struct MacroKnobRow: View {
    @Binding var document: SeqAIDocument
    let trackID: UUID
    @Environment(SequencerDocumentSession.self) private var session

    private var viewModel: MacroKnobRowViewModel { MacroKnobRowViewModel() }

    private var track: StepSequenceTrack? {
        session.store.tracks.first(where: { $0.id == trackID })
    }

    private var macros: [TrackMacroBinding] {
        (track?.macros ?? []).sorted { $0.slotIndex < $1.slotIndex }
    }

    var body: some View {
        if macros.isEmpty {
            EmptyView()
        } else {
            let layers = session.store.layers
            VStack(alignment: .leading, spacing: 8) {
                Text("MACROS")
                    .studioText(.eyebrow)
                    .tracking(0.9)
                    .foregroundStyle(StudioTheme.mutedText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(macros, id: \.id) { binding in
                            MacroKnob(
                                binding: binding,
                                value: viewModel.currentValue(
                                    binding: binding,
                                    trackID: trackID,
                                    layers: layers
                                )
                            ) { newValue in
                                session.setMacroLayerDefault(
                                    value: newValue,
                                    bindingID: binding.id,
                                    trackID: trackID
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - MacroKnob

/// A single macro knob with label: a thin wrapper that routes the shared
/// `StudioRotaryKnob` template through the macro descriptor's range and
/// short-value formatting.
private struct MacroKnob: View {
    let binding: TrackMacroBinding
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        StudioRotaryKnob(
            title: binding.displayName,
            value: value,
            range: binding.descriptor.minValue...binding.descriptor.maxValue,
            size: StudioMetrics.ControlSize.knob,
            format: { MacroValueText.short($0, maxValue: binding.descriptor.maxValue) },
            onChange: onChange
        )
    }
}
