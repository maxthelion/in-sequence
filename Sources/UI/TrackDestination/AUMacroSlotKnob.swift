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
    let onAssign: () -> Void
    let onChange: (Double) -> Void
    let onRemove: (() -> Void)?

    init(
        slotIndex: Int,
        binding: TrackMacroBinding?,
        value: Double?,
        onAssign: @escaping () -> Void,
        onChange: @escaping (Double) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.slotIndex = slotIndex
        self.binding = binding
        self.value = value
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
    let onAssign: (() -> Void)?
    let onEdit: (() -> Void)?
    let onChange: (Double) -> Void
    let onRemove: (() -> Void)?

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    private let knobSize: CGFloat = 40

    init(
        slotIndex: Int,
        descriptor: MacroSlotKnobDescriptor?,
        value: Double?,
        accent: Color,
        emptyLabel: String = "Assign",
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
        self.onAssign = onAssign
        self.onEdit = onEdit
        self.onChange = onChange
        self.onRemove = onRemove
        _displayValue = State(initialValue: value ?? descriptor?.minValue ?? 0)
    }

    private var normalized: Double {
        guard let descriptor else { return 0 }
        let range = descriptor.maxValue - descriptor.minValue
        guard range > 0 else { return 0 }
        return (displayValue - descriptor.minValue) / range
    }

    // Only attached when a descriptor exists (see the .gesture including:
    // mask in body), so the fallback range never drives a live edit.
    private var dragGesture: some Gesture {
        StudioDrag.verticalValueGesture(
            value: $displayValue,
            dragStart: $dragStartValue,
            range: (descriptor?.minValue ?? 0)...(descriptor?.maxValue ?? 1),
            onCommit: onChange
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("M\(slotIndex + 1)")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            ZStack {
                Circle()
                    .stroke(
                        descriptor == nil ? StudioTheme.border.opacity(0.7) : StudioTheme.border,
                        style: StrokeStyle(lineWidth: 2, dash: descriptor == nil ? [5, 4] : [])
                    )
                    .frame(width: knobSize, height: knobSize)

                if descriptor == nil {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    Circle()
                        .trim(from: 0.15, to: 0.15 + 0.7 * normalized)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: knobSize - 6, height: knobSize - 6)
                        .rotationEffect(.degrees(-90))

                    Text(shortLabel(displayValue))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture, including: descriptor == nil ? .none : .all)
            .onTapGesture {
                if descriptor == nil {
                    onAssign?()
                }
            }

            // An empty label collapses entirely (callers pass "" when the
            // dashed "+" knob alone should carry the assign affordance).
            let footerLabel = descriptor?.displayName ?? emptyLabel
            if !footerLabel.isEmpty {
                Text(footerLabel)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(descriptor == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: knobSize + 18)
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
        .onChange(of: value) { _, newValue in
            guard let newValue else {
                return
            }
            if dragStartValue == nil {
                displayValue = newValue
            }
        }
        .onChange(of: descriptor) { _, newDescriptor in
            if dragStartValue == nil {
                displayValue = value ?? newDescriptor?.minValue ?? 0
            }
        }
    }

    private static let shortValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    private func shortLabel(_ value: Double) -> String {
        guard let descriptor else { return "" }
        if descriptor.maxValue > 10 {
            return "\(Int(value.rounded()))"
        }
        return Self.shortValueFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
