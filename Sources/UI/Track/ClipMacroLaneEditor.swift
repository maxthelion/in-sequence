import SwiftUI

// MARK: - ClipMacroLaneEditor

/// A collapsible section inside the clip editor showing one lane per track macro binding.
///
/// Each lane is a horizontal strip of per-step cells. A cell with a non-nil value shows
/// that value as a clip-local override; a nil cell defers to the phrase-layer / descriptor
/// default and displays the fallback in muted text.
///
/// Interaction:
///   - Tap a cell to open a scalar scrubber that sets the cell's override value.
///   - Long-press a cell to clear the override (set to nil).
struct ClipMacroLaneEditor: View {
    /// The clip being edited.
    let clipID: UUID
    /// The macros on the owning track.
    let macros: [TrackMacroBinding]
    /// Current lanes keyed by binding descriptor id.
    let macroLanes: [UUID: MacroLane]
    /// Phrase-layer resolved fallback value per binding (descriptor default if not set).
    let phraseLayerValues: [UUID: Double]
    /// Called when a cell value changes or is cleared.
    let onUpdate: ([UUID: MacroLane]) -> Void

    @State private var isExpanded = true
    @State private var editingCell: EditingCell?

    private struct EditingCell: Identifiable {
        let id = UUID()
        let bindingID: UUID
        let stepIndex: Int
        let descriptor: TrackMacroDescriptor
        var currentValue: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            expandToggle

            if isExpanded && !macros.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(macros, id: \.id) { binding in
                        macroLaneRow(for: binding)
                    }
                }
            } else if isExpanded {
                Text("No macros on this track.")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .sheet(item: $editingCell) { cell in
            ScalarCellScrubber(
                title: cell.descriptor.displayName,
                value: cell.currentValue,
                minValue: cell.descriptor.minValue,
                maxValue: cell.descriptor.maxValue
            ) { newValue in
                setLaneValue(newValue, bindingID: cell.bindingID, stepIndex: cell.stepIndex)
            }
            .presentationDetents([.height(220)])
        }
    }

    // MARK: - Expand toggle

    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.cyan)

                Text("MACRO LANES")
                    .studioText(.eyebrow)
                    .tracking(0.9)
                    .foregroundStyle(StudioTheme.mutedText)

                if !macros.isEmpty {
                    Text("\(macros.count)")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.cyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(StudioTheme.cyan.opacity(0.12), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lane row

    private func macroLaneRow(for binding: TrackMacroBinding) -> some View {
        let lane = macroLanes[binding.id]
        let stepCount = lane?.values.count ?? 0
        let fallback = phraseLayerValues[binding.id] ?? binding.descriptor.defaultValue

        return VStack(alignment: .leading, spacing: 4) {
            Text(binding.displayName)
                .studioText(.label)
                .foregroundStyle(StudioTheme.text)

            if stepCount == 0 {
                Text("Lane not initialized — clip has no steps.")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(0..<stepCount, id: \.self) { stepIndex in
                            let cellValue = lane?.values[stepIndex]
                            MacroLaneCell(
                                value: cellValue,
                                fallback: fallback,
                                descriptor: binding.descriptor
                            )
                            .onTapGesture {
                                let resolvedValue = cellValue ?? fallback
                                editingCell = EditingCell(
                                    bindingID: binding.id,
                                    stepIndex: stepIndex,
                                    descriptor: binding.descriptor,
                                    currentValue: resolvedValue
                                )
                            }
                            .onLongPressGesture {
                                clearLaneValue(bindingID: binding.id, stepIndex: stepIndex)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Mutations

    private func setLaneValue(_ value: Double, bindingID: UUID, stepIndex: Int) {
        var updatedLanes = macroLanes
        var lane = updatedLanes[bindingID] ?? MacroLane(stepCount: 0)
        guard lane.values.indices.contains(stepIndex) else { return }
        lane.values[stepIndex] = value
        updatedLanes[bindingID] = lane
        onUpdate(updatedLanes)
    }

    private func clearLaneValue(bindingID: UUID, stepIndex: Int) {
        var updatedLanes = macroLanes
        var lane = updatedLanes[bindingID] ?? MacroLane(stepCount: 0)
        guard lane.values.indices.contains(stepIndex) else { return }
        lane.values[stepIndex] = nil
        updatedLanes[bindingID] = lane
        onUpdate(updatedLanes)
    }
}

// MARK: - MacroLaneCell

/// A single step cell in a macro lane.
///
/// Shows the override value when set; falls back to a muted display of the
/// phrase-layer default to help the user understand what value will be used.
private struct MacroLaneCell: View {
    let value: Double?
    let fallback: Double
    let descriptor: TrackMacroDescriptor

    private let cellSize: CGFloat = 28
    private var isOverride: Bool { value != nil }
    private var displayValue: Double { value ?? fallback }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOverride ? StudioTheme.cyan.opacity(0.18) : Color.white.opacity(StudioOpacity.subtleFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isOverride ? StudioTheme.cyan.opacity(0.5) : StudioTheme.border.opacity(0.3), lineWidth: 1)
                )

            Text(formatValue(displayValue))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(isOverride ? StudioTheme.cyan : StudioTheme.mutedText.opacity(0.6))
                .lineLimit(1)
        }
        .frame(width: cellSize, height: cellSize)
    }

    private func formatValue(_ val: Double) -> String {
        let range = descriptor.maxValue - descriptor.minValue
        if range > 10 {
            return "\(Int(val.rounded()))"
        }
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        return fmt.string(from: NSNumber(value: val)) ?? "\(val)"
    }
}

// MARK: - ScalarCellScrubber

/// A minimal sheet for setting a scalar macro override value.
///
/// Shows a slider between descriptor min and max with a numeric readout.
private struct ScalarCellScrubber: View {
    let title: String
    @State private var value: Double
    let minValue: Double
    let maxValue: Double
    let onCommit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    init(title: String, value: Double, minValue: Double, maxValue: Double, onCommit: @escaping (Double) -> Void) {
        self.title = title
        self._value = State(initialValue: value)
        self.minValue = minValue
        self.maxValue = maxValue
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                Spacer()
                Button("Done") {
                    onCommit(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.success)
            }

            Slider(value: $value, in: minValue...max(minValue + 0.001, maxValue))

            Text(formattedValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.cyan)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
    }

    private var formattedValue: String {
        let range = maxValue - minValue
        if range > 10 {
            return "\(Int(value.rounded()))"
        }
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 2
        fmt.minimumFractionDigits = 0
        return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
