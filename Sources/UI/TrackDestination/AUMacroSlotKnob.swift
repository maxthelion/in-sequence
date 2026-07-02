import SwiftUI

struct MacroSlot: Identifiable, Equatable {
    let slotIndex: Int
    let binding: TrackMacroBinding?

    var id: Int { slotIndex }
}

struct MacroSlotKnobDescriptor: Equatable, Sendable {
    let displayName: String
    let minValue: Double
    let maxValue: Double

    init(displayName: String, valueRange: ClosedRange<Double>) {
        self.displayName = displayName
        self.minValue = valueRange.lowerBound
        self.maxValue = valueRange.upperBound
    }
}

struct AUMacroSlotKnob: View {
    let slotIndex: Int
    let binding: TrackMacroBinding?
    let value: Double?
    let knobSize: CGFloat
    let showSlotLabel: Bool
    let onAssign: () -> Void
    let onChange: (Double) -> Void
    let onRemove: (() -> Void)?

    init(
        slotIndex: Int,
        binding: TrackMacroBinding?,
        value: Double?,
        knobSize: CGFloat = StudioMetrics.ControlSize.knob,
        showSlotLabel: Bool = true,
        onAssign: @escaping () -> Void,
        onChange: @escaping (Double) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.slotIndex = slotIndex
        self.binding = binding
        self.value = value
        self.knobSize = knobSize
        self.showSlotLabel = showSlotLabel
        self.onAssign = onAssign
        self.onChange = onChange
        self.onRemove = onRemove
    }

    var body: some View {
        MacroSlotKnob(
            slotIndex: slotIndex,
            descriptor: binding.map {
                MacroSlotKnobDescriptor(
                    displayName: $0.displayName,
                    valueRange: $0.descriptor.minValue...$0.descriptor.maxValue
                )
            },
            value: value,
            accent: StudioTheme.cyan,
            knobSize: knobSize,
            showSlotLabel: showSlotLabel,
            onAssign: onAssign,
            onChange: onChange,
            onRemove: onRemove
        )
    }
}

struct MacroSlotKnob: View {
    let slotIndex: Int
    let descriptor: MacroSlotKnobDescriptor?
    let value: Double?
    let accent: Color
    let emptyLabel: String
    let knobSize: CGFloat
    let showSlotLabel: Bool
    let onAssign: (() -> Void)?
    let onEdit: (() -> Void)?
    let onChange: (Double) -> Void
    let onRemove: (() -> Void)?

    init(
        slotIndex: Int,
        descriptor: MacroSlotKnobDescriptor?,
        value: Double?,
        accent: Color,
        emptyLabel: String = "Assign",
        knobSize: CGFloat = StudioMetrics.ControlSize.knob,
        showSlotLabel: Bool = true,
        onAssign: (() -> Void)?,
        onEdit: (() -> Void)? = nil,
        onChange: @escaping (Double) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.slotIndex = slotIndex
        self.descriptor = descriptor
        self.value = value
        self.accent = accent
        self.emptyLabel = emptyLabel
        self.knobSize = knobSize
        self.showSlotLabel = showSlotLabel
        self.onAssign = onAssign
        self.onEdit = onEdit
        self.onChange = onChange
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 8) {
            if showSlotLabel {
                Text("M\(slotIndex + 1)")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if let descriptor {
                // Assigned slot: the shared rotary template carries the arc,
                // drag/scroll editing, value text, and the name underneath.
                StudioRotaryKnob(
                    title: descriptor.displayName,
                    value: value ?? descriptor.minValue,
                    range: descriptor.minValue...descriptor.maxValue,
                    accent: accent,
                    size: knobSize,
                    format: { MacroValueText.short($0, maxValue: descriptor.maxValue) },
                    onChange: onChange
                )
                // Reassigning the slot swaps the knob identity so its local
                // display state re-seeds from the new macro's value/range.
                .id(descriptor.displayName)
            } else {
                // Empty slot keeps its own chrome: dashed circle + plus,
                // tap to assign.
                ZStack {
                    Circle()
                        .stroke(
                            StudioTheme.border.opacity(0.7),
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                        .frame(width: knobSize, height: knobSize)

                    Image(systemName: "plus")
                        .font(.system(size: max(14, knobSize * 0.35), weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onAssign?()
                }

                // An empty label collapses entirely (callers pass "" when the
                // dashed "+" knob alone should carry the assign affordance).
                if !emptyLabel.isEmpty {
                    Text(emptyLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: knobSize + 18)
                }
            }
        }
        .frame(minWidth: knobSize + 18, maxWidth: .infinity, minHeight: 86, alignment: .top)
        .help(descriptor == nil ? "Assign a macro" : "")
        .contextMenu {
            if let onEdit {
                Button("Change Macro", action: onEdit)
            }
            if onEdit != nil, onRemove != nil {
                Divider()
            }
            if let onRemove {
                Button("Remove Macro", role: .destructive, action: onRemove)
            }
        }
    }
}

/// Short center-of-knob value formatting shared by the macro knob surfaces:
/// integers for wide ranges, up to two decimals for unit-ish ranges.
enum MacroValueText {
    private static let shortValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func short(_ value: Double, maxValue: Double) -> String {
        if maxValue > 10 {
            return "\(Int(value.rounded()))"
        }
        return shortValueFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
