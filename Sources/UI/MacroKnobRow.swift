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
        project: Project
    ) -> Double {
        let layerID = "macro-\(trackID.uuidString)-\(binding.id.uuidString)"
        guard let layer = project.layers.first(where: { $0.id == layerID }) else {
            return binding.descriptor.defaultValue
        }
        switch layer.defaults[trackID] {
        case let .scalar(v): return v
        default: return binding.descriptor.defaultValue
        }
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
    @Environment(EngineController.self) private var engineController

    private var viewModel: MacroKnobRowViewModel { MacroKnobRowViewModel() }

    private var track: StepSequenceTrack? {
        document.project.tracks.first(where: { $0.id == trackID })
    }

    private var macros: [TrackMacroBinding] {
        track?.macros ?? []
    }

    var body: some View {
        if macros.isEmpty {
            EmptyView()
        } else {
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
                                    project: document.project
                                )
                            ) { newValue in
                                viewModel.applyLiveValue(
                                    newValue,
                                    binding: binding,
                                    trackID: trackID,
                                    project: &document.project
                                )
                                engineController.apply(documentModel: document.project)
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

/// A single macro knob with label.
private struct MacroKnob: View {
    let binding: TrackMacroBinding
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    private let knobSize: CGFloat = 40
    private let dragSensitivity: Double = 200

    init(binding: TrackMacroBinding, value: Double, onChange: @escaping (Double) -> Void) {
        self.binding = binding
        self.value = value
        self.onChange = onChange
        self._displayValue = State(initialValue: value)
    }

    private var normalized: Double {
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        guard range > 0 else { return 0 }
        return (displayValue - binding.descriptor.minValue) / range
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border, lineWidth: 2)
                    .frame(width: knobSize, height: knobSize)

                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * normalized)
                    .stroke(StudioTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: knobSize - 6, height: knobSize - 6)
                    .rotationEffect(.degrees(-90))

                Text(shortLabel(displayValue))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil {
                            dragStartValue = displayValue
                        }
                        let delta = -drag.translation.height / dragSensitivity
                        let range = binding.descriptor.maxValue - binding.descriptor.minValue
                        let newValue = (dragStartValue ?? displayValue) + delta * range
                        displayValue = min(max(newValue, binding.descriptor.minValue), binding.descriptor.maxValue)
                    }
                    .onEnded { _ in
                        dragStartValue = nil
                        onChange(displayValue)
                    }
            )

            Text(binding.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: knobSize + 12)
        }
        .onChange(of: value) { _, newValue in
            if dragStartValue == nil {
                displayValue = newValue
            }
        }
    }

    private func shortLabel(_ val: Double) -> String {
        if binding.descriptor.maxValue > 10 {
            return "\(Int(val.rounded()))"
        }
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        return fmt.string(from: NSNumber(value: val)) ?? "\(val)"
    }
}
