import SwiftUI

struct AUMacroSlot: Identifiable {
    let slotIndex: Int
    let binding: TrackMacroBinding?

    var id: Int { slotIndex }
}

struct AUMacroSlotKnob: View {
    let slotIndex: Int
    let binding: TrackMacroBinding?
    let value: Double?
    let onAssign: () -> Void
    let onChange: (Double) -> Void
    let onRemove: (() -> Void)?

    @State private var dragStartValue: Double?
    @State private var displayValue: Double

    private let knobSize: CGFloat = 40
    private let dragSensitivity: Double = 220

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
        _displayValue = State(initialValue: value ?? 0)
    }

    private var normalized: Double {
        guard let binding else {
            return 0
        }
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        guard range > 0 else { return 0 }
        return (displayValue - binding.descriptor.minValue) / range
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard let binding else {
                    return
                }
                let delta = -drag.translation.height / dragSensitivity
                let range = binding.descriptor.maxValue - binding.descriptor.minValue
                if dragStartValue == nil {
                    dragStartValue = displayValue
                }
                let nextValue = (dragStartValue ?? displayValue) + delta * range
                displayValue = min(max(nextValue, binding.descriptor.minValue), binding.descriptor.maxValue)
            }
            .onEnded { _ in
                guard binding != nil else {
                    return
                }
                dragStartValue = nil
                onChange(displayValue)
            }
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
                        binding == nil ? StudioTheme.border.opacity(0.7) : StudioTheme.border,
                        style: StrokeStyle(lineWidth: 2, dash: binding == nil ? [5, 4] : [])
                    )
                    .frame(width: knobSize, height: knobSize)

                if binding == nil {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                } else {
                    Circle()
                        .trim(from: 0.15, to: 0.15 + 0.7 * normalized)
                        .stroke(StudioTheme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: knobSize - 6, height: knobSize - 6)
                        .rotationEffect(.degrees(-90))

                    Text(shortLabel(displayValue))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture, including: binding == nil ? .none : .all)
            .onTapGesture {
                if binding == nil {
                    onAssign()
                }
            }

            Text(binding?.displayName ?? "Assign")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(binding == nil ? StudioTheme.mutedText : StudioTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: knobSize + 18)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
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
    }

    private static let shortValueFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    private func shortLabel(_ value: Double) -> String {
        guard let binding else {
            return ""
        }
        if binding.descriptor.maxValue > 10 {
            return "\(Int(value.rounded()))"
        }
        return Self.shortValueFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
