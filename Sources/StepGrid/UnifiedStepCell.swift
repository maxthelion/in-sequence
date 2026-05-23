import AppKit
import CoreGraphics
import SwiftUI

struct UnifiedStepCell: View {
    let visualState: StepVisualState
    let isPlaying: Bool
    let isSelected: Bool
    let content: StepCellContent
    let onTap: () -> Void
    let onDrag: ((Double) -> Void)?
    let onSelect: () -> Void

    @State private var hasActivatedDrag = false

    private static let geometry = UnifiedStepCellGeometry()
    private static let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundShape
                .fill(visualConfiguration.backgroundColor)

            valueBar

            contentView
        }
        .frame(width: Self.geometry.size.width, height: Self.geometry.size.height)
        .clipShape(backgroundShape)
        .overlay(borderLayer)
        .contentShape(backgroundShape)
        .gesture(stepGesture)
        .onLongPressGesture(minimumDuration: UnifiedStepCellGesturePolicy.selectionLongPressDuration) {
            onSelect()
        }
        .background {
            UnifiedStepCellRightClickProbe(onSelect: onSelect)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var visualConfiguration: UnifiedStepCellVisualConfiguration {
        UnifiedStepCellVisualConfiguration(
            visualState: visualState,
            isPlaying: isPlaying,
            isSelected: isSelected,
            content: content
        )
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var valueBar: some View {
        if let fraction = visualConfiguration.valueFraction {
            Rectangle()
                .fill(visualConfiguration.valueBarColor)
                .frame(height: Self.geometry.size.height * fraction)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .opacity(fraction > 0 ? 1 : 0)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .toggle:
            toggleMark

        case .valueBar:
            EmptyView()

        case let .sliceLabel(index, label):
            VStack(spacing: 2) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(visualConfiguration.secondaryContentColor)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(visualConfiguration.primaryContentColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .minimumScaleFactor(0.75)
            .lineLimit(1)

        case let .chordLabel(name):
            Text(name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(visualConfiguration.primaryContentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .optionLabel(text):
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(visualConfiguration.primaryContentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var toggleMark: some View {
        ZStack {
            Circle()
                .stroke(visualConfiguration.toggleStrokeColor, lineWidth: 1)
                .frame(width: 13, height: 13)

            if visualConfiguration.isActive {
                Circle()
                    .fill(visualConfiguration.toggleFillColor)
                    .frame(width: visualState == .accented ? 8 : 11, height: visualState == .accented ? 8 : 11)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var borderLayer: some View {
        backgroundShape
            .strokeBorder(visualConfiguration.outlineColor, lineWidth: 1)

        if isPlaying {
            backgroundShape
                .inset(by: visualConfiguration.playingBorderInset)
                .strokeBorder(StudioTheme.success.opacity(0.96), lineWidth: 1)
        }

        if isSelected {
            backgroundShape
                .strokeBorder(StudioTheme.amber.opacity(0.98), lineWidth: 2)
        }
    }

    private var stepGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let onDrag else { return }
                guard UnifiedStepCellGesturePolicy.hasExceededDragThreshold(value.translation) else { return }

                hasActivatedDrag = true
                onDrag(
                    UnifiedStepCellGesturePolicy.normalizedValue(
                        locationY: value.location.y,
                        height: Self.geometry.size.height
                    )
                )
            }
            .onEnded { value in
                let shouldTap = !hasActivatedDrag && !UnifiedStepCellGesturePolicy.hasExceededDragThreshold(value.translation)
                hasActivatedDrag = false

                if shouldTap {
                    onTap()
                }
            }
    }

    private var accessibilityLabel: String {
        switch content {
        case .toggle:
            return "Step"
        case .valueBar:
            return "Step value"
        case let .sliceLabel(_, label):
            return "Slice \(label)"
        case let .chordLabel(name):
            return "Chord \(name)"
        case let .optionLabel(text):
            return "Option \(text)"
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = [visualConfiguration.isActive ? "Active" : "Inactive"]
        if let valueFraction = visualConfiguration.valueFraction {
            parts.append("\(Int((valueFraction * 100).rounded())) percent")
        }
        if isPlaying {
            parts.append("Playing")
        }
        if isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }
}

struct UnifiedStepCellGeometry: Equatable {
    let size = CGSize(width: 40, height: 52)

    func size(for content: StepCellContent) -> CGSize {
        _ = content
        return size
    }
}

struct UnifiedStepCellVisualConfiguration {
    let isActive: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let valueFraction: Double?
    let backgroundColor: Color
    let valueBarColor: Color
    let primaryContentColor: Color
    let secondaryContentColor: Color
    let toggleStrokeColor: Color
    let toggleFillColor: Color
    let outlineColor: Color
    let playingBorderInset: CGFloat

    init(
        visualState: StepVisualState,
        isPlaying: Bool,
        isSelected: Bool,
        content: StepCellContent
    ) {
        self.isActive = visualState != .off
        self.isPlaying = isPlaying
        self.isSelected = isSelected
        self.valueFraction = Self.valueFraction(for: content)
        self.playingBorderInset = isSelected ? 3 : 0.5

        switch visualState {
        case .off:
            backgroundColor = Color.white.opacity(0.035)
            valueBarColor = StudioTheme.cyan.opacity(0.58)
            primaryContentColor = StudioTheme.mutedText
            secondaryContentColor = StudioTheme.mutedText.opacity(0.72)
            toggleStrokeColor = StudioTheme.border.opacity(0.8)
            toggleFillColor = .clear
            outlineColor = StudioTheme.border.opacity(0.8)

        case .on:
            backgroundColor = StudioTheme.cyan.opacity(0.34)
            valueBarColor = StudioTheme.cyan.opacity(0.86)
            primaryContentColor = StudioTheme.text
            secondaryContentColor = StudioTheme.text.opacity(0.74)
            toggleStrokeColor = StudioTheme.text.opacity(0.86)
            toggleFillColor = StudioTheme.text.opacity(0.88)
            outlineColor = StudioTheme.cyan.opacity(0.46)

        case .accented:
            backgroundColor = StudioTheme.amber.opacity(0.34)
            valueBarColor = StudioTheme.amber.opacity(0.88)
            primaryContentColor = StudioTheme.text
            secondaryContentColor = StudioTheme.text.opacity(0.74)
            toggleStrokeColor = StudioTheme.text.opacity(0.9)
            toggleFillColor = StudioTheme.text.opacity(0.92)
            outlineColor = StudioTheme.amber.opacity(0.5)
        }
    }

    var showsCompoundPlayingSelection: Bool {
        isPlaying && isSelected && playingBorderInset > 0.5
    }

    private static func valueFraction(for content: StepCellContent) -> Double? {
        guard case let .valueBar(fraction) = content else { return nil }
        return min(max(fraction, 0), 1)
    }
}

enum UnifiedStepCellGesturePolicy {
    static let dragThreshold: CGFloat = 4
    static let selectionLongPressDuration = 0.4

    static func hasExceededDragThreshold(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= dragThreshold
    }

    static func normalizedValue(locationY: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return 0 }
        return Double(min(max(1 - (locationY / height), 0), 1))
    }
}

private struct UnifiedStepCellRightClickProbe: NSViewRepresentable {
    let onSelect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.view = view
        context.coordinator.onSelect = onSelect
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onSelect = onSelect
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: Coordinator) {
        _ = nsView
        coordinator.removeMonitor()
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            _ = point
            return nil
        }
    }

    final class Coordinator {
        var onSelect: () -> Void
        weak var view: ProbeView?
        private var monitor: Any?

        init(onSelect: @escaping () -> Void) {
            self.onSelect = onSelect
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window
                else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(point) {
                    onSelect()
                }

                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        UnifiedStepCell(
            visualState: .off,
            isPlaying: false,
            isSelected: true,
            content: .toggle,
            onTap: {},
            onDrag: nil,
            onSelect: {}
        )
        UnifiedStepCell(
            visualState: .on,
            isPlaying: true,
            isSelected: true,
            content: .valueBar(fraction: 0.7),
            onTap: {},
            onDrag: { _ in },
            onSelect: {}
        )
        UnifiedStepCell(
            visualState: .accented,
            isPlaying: false,
            isSelected: false,
            content: .sliceLabel(index: 3, label: "S4"),
            onTap: {},
            onDrag: nil,
            onSelect: {}
        )
        UnifiedStepCell(
            visualState: .on,
            isPlaying: false,
            isSelected: false,
            content: .chordLabel(name: "Am7"),
            onTap: {},
            onDrag: nil,
            onSelect: {}
        )
        UnifiedStepCell(
            visualState: .off,
            isPlaying: true,
            isSelected: false,
            content: .optionLabel(text: "Run"),
            onTap: {},
            onDrag: nil,
            onSelect: {}
        )
    }
    .padding()
    .background(StudioTheme.background)
}
