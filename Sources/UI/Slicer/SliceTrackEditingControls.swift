import AppKit
import SwiftUI

enum SliceTrackLane: String, CaseIterable, Identifiable {
    case normal
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .fill: return "Fill"
        }
    }
}

enum SliceTrackClipLayer: String, CaseIterable, Identifiable {
    // NOTE: the `steps`, `velocity`, `chance` raw values are load-bearing —
    // the QA visual scenarios (`slicerLayer=steps|velocity|chance`) and the
    // step-grid coordinator map onto them. `steps` is the slice-index layer.
    case steps
    case velocity
    case direction
    case noteRepeat
    case gate
    case chance

    var id: String { rawValue }

    /// The display label shown in the step-layer selector above the steps.
    var title: String {
        switch self {
        case .steps: return "Slice Index"
        case .velocity: return "Velocity"
        case .direction: return "Direction"
        case .noteRepeat: return "Note Repeat"
        case .gate: return "Length"
        case .chance: return "Chance"
        }
    }

    /// Layers whose per-step value is fully wired into the engine clip model
    /// (slice index, velocity, chance). The remaining layers are part of the
    /// step grammar but are not yet backed by a per-step engine parameter, so
    /// they render the strip read-only with a NOTE.
    var isEngineBacked: Bool {
        switch self {
        case .steps, .velocity, .gate, .chance:
            return true
        case .direction, .noteRepeat:
            return false
        }
    }
}

// The slicer step-layer selector is a VALUE selector, so it renders through
// the shared inset-track grammar (StudioSegmentedControl) inside the step
// well — see SliceTrackWorkspaceView.sliceLayerSelector. The bespoke
// capsule-pill SliceLayerTabRow this file used to own was deleted in the
// Variant D migration (docs/roadmap/track-view-ia/
// tab-unification-and-canon-creep.md → DECISION).

struct StepLayerQuickSwitchOption<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: Value
}

struct StepLayerQuickSwitch<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    @Binding var isOpen: Bool
    let options: [StepLayerQuickSwitchOption<Value>]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StepLayerQuickSwitchChip(
                title: title,
                selection: $selection,
                isOpen: $isOpen,
                options: options,
                accent: accent
            )

            if isOpen {
                StepLayerQuickSwitchOptions(
                    selection: $selection,
                    isOpen: $isOpen,
                    options: options,
                    accent: accent
                )
            }
        }
    }
}

struct StepLayerQuickSwitchChip<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    @Binding var isOpen: Bool
    let options: [StepLayerQuickSwitchOption<Value>]
    let accent: Color

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? "Layer"
    }

    var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    // ux-canon-allow: eyebrow captions are structural labels,
                    // not stateful chrome — mutedText is the caption token.
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(selectedTitle)
                        .studioText(.labelBold)
                        .foregroundStyle(isOpen ? StudioTheme.text : StudioTheme.background)
                        .lineLimit(1)

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isOpen ? StudioTheme.mutedText : StudioTheme.background)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .fixedSize()
                .background(
                    isOpen ? StudioTheme.subtleFill : accent,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        .stroke(isOpen ? StudioTheme.border : Color.clear, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title.isEmpty ? selectedTitle : "\(title) \(selectedTitle)")
        }
        .fixedSize()
    }
}

struct StepLayerQuickSwitchOptions<Value: Hashable>: View {
    @Binding var selection: Value
    @Binding var isOpen: Bool
    let options: [StepLayerQuickSwitchOption<Value>]
    let accent: Color

    var body: some View {
        StepLayerQuickSwitchFlowLayout(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                    isOpen = false
                } label: {
                    Text(option.title)
                        .studioText(.micro)
                        .foregroundStyle(option.value == selection ? StudioTheme.background : StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            option.value == selection ? accent : StudioTheme.subtleFill,
                            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                                .stroke(option.value == selection ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StepLayerQuickSwitchFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let layout = resolveLayout(
            maxWidth: proposal.width ?? CGFloat.greatestFiniteMagnitude,
            subviews: subviews
        )
        return CGSize(width: proposal.width ?? layout.width, height: layout.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func resolveLayout(maxWidth: CGFloat, subviews: Subviews) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                width = max(width, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        width = max(width, x > 0 ? x - spacing : 0)
        return CGSize(width: width, height: y + rowHeight)
    }
}

struct StepLayerRotaryRow: View {
    let controls: [StepGridRotaryControl]
    let activeLayer: StepGridLayer
    let suppressActiveLayerHighlight: Bool
    let accent: Color
    let onSelectLayer: (StepGridLayer) -> Void
    let onWriteValue: (StepGridLayer, Double) -> Void

    private let minimumRotaryWidth: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("STEP EDIT")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(accent)

                Text("\(controls.count) layer\(controls.count == 1 ? "" : "s")")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            if controls.count >= 5 {
                ZStack(alignment: .trailing) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            rotaryControls(fixedWidth: true)
                        }
                        .padding(.trailing, 20)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.text.opacity(0.8))
                        .padding(.horizontal, 4)
                        .frame(maxHeight: .infinity)
                        .background(
                            LinearGradient(
                                colors: [StudioTheme.background.opacity(0), StudioTheme.background.opacity(0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityHidden(true)
                }
                .frame(height: 94)
            } else {
                HStack(spacing: 8) {
                    rotaryControls(fixedWidth: false)
                }
            }
        }
    }

    @ViewBuilder
    private func rotaryControls(fixedWidth: Bool) -> some View {
        ForEach(controls) { control in
            StepLayerRotaryDial(
                control: control,
                isActiveLayer: !suppressActiveLayerHighlight && control.layer == activeLayer,
                accent: accent,
                onSelectLayer: {
                    onSelectLayer(control.layer)
                },
                onWriteValue: { value in
                    onWriteValue(control.layer, value)
                }
            )
            .frame(minWidth: minimumRotaryWidth)
            .frame(width: fixedWidth ? minimumRotaryWidth : nil)
            .frame(maxWidth: fixedWidth ? nil : .infinity)
        }
    }
}

struct StepLayerRotaryEmptyState: View {
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("STEP EDIT")
                .studioText(.eyebrowBold)
                .foregroundStyle(accent)

            Text("No editable layers")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44, alignment: .leading)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }
}

private struct StepLayerRotaryDial: View {
    let control: StepGridRotaryControl
    let isActiveLayer: Bool
    let accent: Color
    let onSelectLayer: () -> Void
    let onWriteValue: (Double) -> Void

    @State private var dragStartValue: Double?

    private let dragFullRange: CGFloat = 80
    private let dialSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border.opacity(0.55), lineWidth: 3)
                    .frame(width: dialSize, height: dialSize)

                StudioRotaryArc(progress: control.normalizedValue)
                    .stroke(accent.opacity(0.94), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: dialSize, height: dialSize)

                Text(control.displayValue)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: dialSize - 10)
            }

            Text(control.title)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .frame(minHeight: 84)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(isActiveLayer ? accent.opacity(0.95) : StudioTheme.border.opacity(0.8), lineWidth: isActiveLayer ? 2 : StudioMetrics.borderWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .onTapGesture(perform: onSelectLayer)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStartValue ?? control.normalizedValue
                    dragStartValue = start
                    let next = Self.clampedUnit(start - Double(value.translation.height / dragFullRange))
                    onWriteValue(next)
                }
                .onEnded { _ in
                    dragStartValue = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.title) rotary")
        .accessibilityValue(control.displayValue)
    }

    private static func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct SliceStepStrip: View {
    enum State: Equatable {
        case off
        case on(sliceIndex: Int, mode: SliceTriggerStepMode)
    }

    let stepStates: [State]
    let indexOffset: Int
    let playingStepIndex: Int?
    let selectedStepIndex: Int
    let selectedStepIndexes: Set<Int>
    let activeLayer: SliceTrackClipLayer
    let accent: Color
    let contentProvider: (Int, State) -> StepCellContent
    let onValueDrag: ((Int, Double) -> Void)?
    let onBackgroundTap: (() -> Void)?
    let onSelect: (Int) -> Void
    let onTap: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 16)

    init(
        stepStates: [State],
        indexOffset: Int,
        playingStepIndex: Int?,
        selectedStepIndex: Int,
        selectedStepIndexes: Set<Int>,
        activeLayer: SliceTrackClipLayer,
        accent: Color = StudioTheme.transportAccent,
        contentProvider: @escaping (Int, State) -> StepCellContent,
        onValueDrag: ((Int, Double) -> Void)?,
        onBackgroundTap: (() -> Void)? = nil,
        onSelect: @escaping (Int) -> Void,
        onTap: @escaping (Int) -> Void
    ) {
        self.stepStates = stepStates
        self.indexOffset = indexOffset
        self.playingStepIndex = playingStepIndex
        self.selectedStepIndex = selectedStepIndex
        self.selectedStepIndexes = selectedStepIndexes
        self.activeLayer = activeLayer
        self.accent = accent
        self.contentProvider = contentProvider
        self.onValueDrag = onValueDrag
        self.onBackgroundTap = onBackgroundTap
        self.onSelect = onSelect
        self.onTap = onTap
    }

    var body: some View {
        ZStack {
            if let onBackgroundTap {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(stepStates.enumerated()), id: \.offset) { localIndex, state in
                    let absoluteIndex = indexOffset + localIndex
                    VStack(spacing: 7) {
                        Text("\(absoluteIndex + 1)")
                            .studioText(.eyebrow)
                            .foregroundStyle(state == .off ? StudioTheme.mutedText : StudioTheme.text)

                        UnifiedStepCell(
                            visualState: visualState(for: state),
                            isPlaying: playingStepIndex == absoluteIndex,
                            isSelected: selectedStepIndexes.contains(absoluteIndex),
                            content: contentProvider(absoluteIndex, state),
                            accent: accent,
                            onTap: { onTap(absoluteIndex) },
                            onDrag: activeLayer == .steps ? nil : { value in
                                onValueDrag?(absoluteIndex, value)
                            },
                            onSelect: { onSelect(absoluteIndex) }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(isSelected(absoluteIndex) ? accent : Color.clear, lineWidth: 2)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Slice step \(absoluteIndex + 1)")
                }
            }
        }
    }

    private func visualState(for state: State) -> StepVisualState {
        switch state {
        case .off:
            return .off
        case let .on(_, mode):
            return mode == .runFromHere ? .accented : .on
        }
    }

    private func isSelected(_ absoluteIndex: Int) -> Bool {
        selectedStepIndexes.contains(absoluteIndex) || selectedStepIndex == absoluteIndex
    }
}

struct StepGridEscapeKeyHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.view = view
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEscape = onEscape
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEscape = onEscape
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
        var isEnabled: Bool
        var onEscape: () -> Void
        weak var view: ProbeView?
        private var monitor: Any?

        init(isEnabled: Bool, onEscape: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEscape = onEscape
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self,
                      isEnabled,
                      event.keyCode == 53,
                      let view,
                      event.window === view.window
                else {
                    return event
                }

                onEscape()
                return nil
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

struct SliceStepBatchActionBar: View {
    let isVisible: Bool
    let canPaste: Bool
    let onClear: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Clear", action: onClear)
            Button("Copy", action: onCopy)
            Button("Paste", action: onPaste)
                .disabled(!canPaste)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityLabel("Step batch actions")
    }
}

struct SliceTrackWaveformEditor: View {
    let buckets: [Float]
    let sliceSet: SliceSet
    let sampleLengthFrames: Int64
    let selectedMarkerID: UUID?
    let accent: Color
    let zoom: Double
    let scroll: Double
    let onSelectMarker: (UUID) -> Void
    // Tapping inside a slice region (not on a boundary handle) maps that slice
    // to the currently selected step. The Int is the slice index into
    // `sliceSet.markers` (0 == whole, 1...N == user slices).
    var onSelectSliceRegion: ((Int) -> Void)? = nil
    let onMoveWholeStart: (Int64) -> Void
    let onMoveWholeEnd: (Int64) -> Void
    let onMoveSliceBoundary: (UUID, Int64) -> Void

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(1, geo.size.width - 20)
            let contentHeight = max(1, geo.size.height - 20)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    WaveformView(
                        buckets: visibleBuckets,
                        fillColor: accent,
                        inactiveColor: StudioTheme.border.opacity(0.65),
                        stepCount: max(1, Int((sliceSet.bars ?? 1).rounded()) * 16),
                        barStepInterval: 16
                    )
                        .frame(width: contentWidth, height: contentHeight)

                    if let selectedMarker {
                        sliceRegion(marker: selectedMarker, width: contentWidth)
                    }

                    ForEach(sliceSet.markers.dropFirst()) { marker in
                        boundaryLine(marker: marker, width: contentWidth)
                    }

                    wholeHandle(frame: sliceSet.markers.first?.startFrame ?? 0, label: "S", width: contentWidth)
                    wholeHandle(frame: sliceSet.markers.first?.endFrame ?? sampleLengthFrames, label: "E", width: contentWidth)
                }
                .frame(width: contentWidth, height: contentHeight, alignment: .leading)
                .offset(x: 10, y: 10)
            }
            .contentShape(Rectangle())
            // Boundary drags take priority; a plain click that lands inside a
            // slice region (away from any handle) maps that slice to the
            // selected step.
            .gesture(dragGesture(width: contentWidth))
            .gesture(regionTapGesture(width: contentWidth))
        }
    }

    private var visibleFrameRange: ClosedRange<Int64> {
        guard sampleLengthFrames > 0 else {
            return 0...0
        }
        let resolvedZoom = min(max(zoom, 1), 8)
        let visibleLength = max(1, Int64((Double(sampleLengthFrames) / resolvedZoom).rounded()))
        let maxStart = max(0, sampleLengthFrames - visibleLength)
        let start = Int64((Double(maxStart) * min(max(scroll, 0), 1)).rounded())
        return start...min(sampleLengthFrames, start + visibleLength)
    }

    private var visibleBuckets: [Float] {
        guard !buckets.isEmpty, sampleLengthFrames > 0 else {
            return Array(repeating: 0, count: 64)
        }
        let range = visibleFrameRange
        let lower = Int((Double(range.lowerBound) / Double(sampleLengthFrames)) * Double(buckets.count))
        let upper = Int((Double(range.upperBound) / Double(sampleLengthFrames)) * Double(buckets.count))
        let clampedLower = min(max(lower, 0), buckets.count - 1)
        let clampedUpper = min(max(upper, clampedLower + 1), buckets.count)
        return Array(buckets[clampedLower..<clampedUpper])
    }

    private func boundaryLine(marker: SliceMarker, width: CGFloat) -> some View {
        let x = xPosition(for: marker.startFrame, width: width)
        return Rectangle()
            .fill(accent)
            .frame(width: marker.id == selectedMarkerID ? 3 : 2)
            .offset(x: x)
            .opacity(isVisible(marker.startFrame) ? 0.95 : 0)
            .onTapGesture {
                onSelectMarker(marker.id)
            }
    }

    @ViewBuilder
    private func sliceRegion(marker: SliceMarker, width: CGFloat) -> some View {
        if intersectsVisibleRange(marker) {
            let start = xPosition(for: marker.startFrame, width: width)
            let end = xPosition(for: marker.endFrame, width: width)
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                .fill(Color.clear)
                .frame(width: max(2, end - start))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                )
                .offset(x: start)
        }
    }

    private func wholeHandle(frame: Int64, label: String, width: CGFloat) -> some View {
        let x = xPosition(for: frame, width: width)
        return VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(accent, in: Capsule())
            Rectangle()
                .fill(accent)
                .frame(width: 3)
        }
        .offset(x: x)
        .opacity(isVisible(frame) ? 1 : 0)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onEnded { value in
                let localX = min(max(value.location.x - 10, 0), width)
                let frame = framePosition(for: localX, width: width)
                switch nearestHandle(to: localX, width: width) {
                case .wholeStart:
                    onMoveWholeStart(frame)
                case .wholeEnd:
                    onMoveWholeEnd(frame)
                case let .slice(markerID):
                    onMoveSliceBoundary(markerID, frame)
                case .none:
                    break
                }
            }
    }

    private func regionTapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard let onSelectSliceRegion else { return }
                let localX = min(max(value.location.x - 10, 0), width)
                // A tap that lands on a draggable handle is a boundary
                // interaction, not a region pick — ignore it so the two
                // gestures don't fight over the same spot.
                guard nearestHandle(to: localX, width: width) == nil else { return }
                guard let index = sliceIndex(forLocalX: localX, width: width) else { return }
                onSelectSliceRegion(index)
            }
    }

    // Resolves which slice region the x position falls in and returns its index
    // into `sliceSet.markers` (0 == whole). User-slice regions run from a
    // marker's startFrame up to the next marker's startFrame (boundaries are
    // shared), with the last region ending at the whole-sample end.
    private func sliceIndex(forLocalX x: CGFloat, width: CGFloat) -> Int? {
        guard !sliceSet.markers.isEmpty else { return nil }
        let frame = framePosition(for: x, width: width)
        let userMarkers = Array(sliceSet.markers.enumerated().dropFirst())
        guard !userMarkers.isEmpty else {
            // No user slices: only the whole sample exists.
            return 0
        }
        let wholeEnd = sliceSet.markers.first?.endFrame ?? sampleLengthFrames
        for position in userMarkers.indices {
            let marker = userMarkers[position].element
            let regionEnd = position + 1 < userMarkers.count
                ? userMarkers[position + 1].element.startFrame
                : wholeEnd
            if frame >= marker.startFrame, frame < regionEnd {
                return userMarkers[position].offset
            }
        }
        // Fell before the first user slice (inside the whole-sample lead-in) or
        // past the last region: clamp to the nearest user slice.
        if let first = userMarkers.first, frame < first.element.startFrame {
            return first.offset
        }
        return userMarkers.last?.offset
    }

    private func nearestHandle(to x: CGFloat, width: CGFloat) -> SliceTrackWaveformHandle? {
        var candidates: [(SliceTrackWaveformHandle, CGFloat)] = []
        if let whole = sliceSet.markers.first {
            candidates.append((.wholeStart, abs(xPosition(for: whole.startFrame, width: width) - x)))
            candidates.append((.wholeEnd, abs(xPosition(for: whole.endFrame, width: width) - x)))
        }
        for marker in sliceSet.markers.dropFirst() {
            candidates.append((.slice(marker.id), abs(xPosition(for: marker.startFrame, width: width) - x)))
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= 28 else {
            return nil
        }
        return nearest.0
    }

    private func xPosition(for frame: Int64, width: CGFloat) -> CGFloat {
        let range = visibleFrameRange
        let length = max(1, range.upperBound - range.lowerBound)
        let ratio = Double(frame - range.lowerBound) / Double(length)
        return CGFloat(min(max(ratio, 0), 1)) * width
    }

    private func framePosition(for x: CGFloat, width: CGFloat) -> Int64 {
        let range = visibleFrameRange
        let ratio = Double(min(max(x / max(width, 1), 0), 1))
        return range.lowerBound + Int64((Double(range.upperBound - range.lowerBound) * ratio).rounded())
    }

    private func isVisible(_ frame: Int64) -> Bool {
        visibleFrameRange.contains(frame)
    }

    private func intersectsVisibleRange(_ marker: SliceMarker) -> Bool {
        let range = visibleFrameRange
        return marker.endFrame >= range.lowerBound && marker.startFrame <= range.upperBound
    }

    private var selectedMarker: SliceMarker? {
        guard let selectedMarkerID else {
            return nil
        }
        return sliceSet.markers.first { $0.id == selectedMarkerID }
    }
}

private enum SliceTrackWaveformHandle: Equatable {
    case wholeStart
    case wholeEnd
    case slice(UUID)
}

enum SliceMarkerSelectionPolicy {
    static func assignableMarkerIndex(
        markerID: UUID,
        currentSliceSet: SliceSet?,
        analysisDraft: SliceSet?
    ) -> Int? {
        guard analysisDraft == nil,
              let currentSliceSet
        else {
            return nil
        }
        return currentSliceSet.markers.firstIndex { $0.id == markerID }
    }
}

enum SliceBoundaryEditing {
    static func moveSharedBoundary(
        markerID: UUID,
        to frame: Int64,
        in sliceSet: inout SliceSet,
        sampleLengthFrames: Int64
    ) {
        guard let index = sliceSet.markers.firstIndex(where: { $0.id == markerID }),
              index > 0
        else {
            return
        }

        let previousStart = sliceSet.markers[index - 1].startFrame
        let currentEnd = sliceSet.markers[index].endFrame
        let nextBoundary = index + 1 < sliceSet.markers.count
            ? sliceSet.markers[index + 1].startFrame
            : sampleLengthFrames
        let lowerBound = previousStart + 1
        let upperBound = max(lowerBound, min(currentEnd, nextBoundary) - 1)
        let boundary = min(max(frame, lowerBound), upperBound)

        sliceSet.markers[index - 1].endFrame = boundary
        sliceSet.markers[index].startFrame = boundary
    }
}

// MARK: - Lower tab bar (Steps · Source · Slice · FX · Macros · Mixer)

// STEPS is the first section (owner amendment, 2026-07-03 — see
// docs/roadmap/track-view-ia/tab-unification-and-canon-creep.md → Post-
// migration amendments): the lane/length/layer selectors + step grid + pager
// live INSIDE the section well, matching the melodic STEPS/CLIP precedent.
enum SliceTrackLowerTab: String, CaseIterable, Identifiable {
    case steps
    case source
    case slice
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .source: return "Source"
        case .slice: return "Slice"
        case .fx: return "FX"
        case .macros: return "Macros"
        case .mixer: return "Mixer"
        }
    }
}

// The lower tab bar is a SECTION switcher, so it renders through the shared
// D-pill grammar (StudioSectionPills) floating above the StudioTabWell — see
// SliceTrackWorkspaceView.sectionPills. The bespoke solid-fill SliceLowerTabBar
// this file used to own was deleted in the Variant D migration.

// MARK: - Source tab content (three states)

enum SliceSourceState: Equatable {
    case empty
    case unsliced
    case sliced
}

struct SliceSourceTabContent: View {
    let state: SliceSourceState
    let sampleName: String?
    let sliceCount: Int
    let accent: Color
    let onChooseSample: () -> Void
    let onRemoveSample: () -> Void
    let onOpenSliceModal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The Source tab pill already names this panel; omit the duplicate
            // section header (matches the showsHeader: false pattern elsewhere).
            switch state {
            case .empty:
                emptyState
            case .unsliced:
                unslicedState
            case .sliced:
                slicedState
            }
        }
    }

    // No-loop scenario: skip the verbose prose and show a single compact
    // add affordance (one clear "+"/Add Loop plus tile).
    private var emptyState: some View {
        StudioAddCard(
            label: "Add Loop",
            accent: accent,
            minHeight: 120,
            help: "Choose a break loop to slice"
        ) {
            onChooseSample()
        }
    }

    // The surrounding StudioTabWell owns the container chrome; this content
    // keeps only source state and actions.
    private var unslicedState: some View {
        VStack(alignment: .leading, spacing: 12) {
            sampleNameRow
            HStack(spacing: 10) {
                studioActionButton(
                    title: "Slice Sample",
                    systemImage: "scissors",
                    accent: accent,
                    action: onOpenSliceModal
                )
                Text("Unsliced")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var slicedState: some View {
        VStack(alignment: .leading, spacing: 12) {
            sampleNameRow
            HStack(spacing: 8) {
                Text("\(sliceCount) slice\(sliceCount == 1 ? "" : "s")")
                    .studioText(.labelBold)
                    .foregroundStyle(accent)
                Spacer()
            }
            HStack(spacing: 10) {
                studioActionButton(
                    title: "Edit Slices",
                    systemImage: "slider.horizontal.3",
                    accent: accent,
                    action: onOpenSliceModal
                )
                studioActionButton(
                    title: "Re-slice",
                    systemImage: "arrow.triangle.2.circlepath",
                    accent: nil,
                    action: onOpenSliceModal
                )
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sampleNameRow: some View {
        HStack(spacing: 10) {
            Text(sampleName ?? "Sample")
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
            Spacer()
            studioActionButton(
                title: "Remove Sample",
                systemImage: "trash",
                accent: nil,
                action: onRemoveSample
            )
        }
    }

    // Studio-styled action button matching the app's capsule/outline grammar:
    // neutral fill, accent lives in the outline.
    private func studioActionButton(
        title: String,
        systemImage: String,
        accent: Color?,
        action: @escaping () -> Void
    ) -> some View {
        let stroke = accent?.opacity(StudioOpacity.mediumStroke) ?? StudioTheme.border.opacity(0.8)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .studioText(.labelBold)
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(StudioTheme.subtleFill, in: Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Slice tab sampler card (drum-part sampler grammar)

/// The Slice tab squashes "where the slice is in the source" and the
/// sampler/playback settings into one card that reads like the drum-part
/// sampler (`SamplerDestinationWidget`): title row, compact range preview,
/// browse/audition, parameter dials, reverse/choke. The per-slice
/// values are the real engine-backed `SliceTriggerStepParameters` for the
/// selected step.
struct SliceSamplerCard: View {
    /// The one chrome accent of the surface (track identity colour), passed
    /// explicitly — no silent fallback.
    let accent: Color
    let markerIndex: Int
    let buckets: [Float]
    let marker: SliceMarker
    let sampleLengthFrames: Int64
    @Binding var mode: SliceTriggerStepMode
    @Binding var parameters: SliceTriggerStepParameters
    let onAudition: () -> Void
    let onBrowse: (Int) -> Void

    private var sliceTitle: String {
        markerIndex == 0 ? "Whole" : "S\(markerIndex)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            browseRow
            SliceSamplePlayerParametersView(
                accent: accent,
                waveformBuckets: previewBuckets,
                mode: $mode,
                parameters: $parameters
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangeDetail: String {
        let length = max(0, marker.endFrame - marker.startFrame)
        return "\(sliceTitle) · \(length) frames"
    }

    private var previewBuckets: [Float] {
        guard !buckets.isEmpty, sampleLengthFrames > 0 else {
            return buckets
        }
        let lower = Int((Double(marker.startFrame) / Double(sampleLengthFrames)) * Double(buckets.count))
        let upper = Int((Double(marker.endFrame) / Double(sampleLengthFrames)) * Double(buckets.count))
        let clampedLower = min(max(lower, 0), buckets.count - 1)
        let clampedUpper = min(max(upper, clampedLower + 1), buckets.count)
        return Array(buckets[clampedLower..<clampedUpper])
    }

    private var browseRow: some View {
        HStack(spacing: 10) {
            StudioCircleIconButton(
                systemName: "chevron.left",
                help: "Previous slice"
            ) {
                onBrowse(-1)
            }
            Text(sliceTitle)
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
            Text(rangeDetail)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
            Spacer(minLength: 8)
            StudioCircleIconButton(
                systemName: "play.fill",
                size: StudioMetrics.ControlSize.medium,
                help: "Audition this slice",
                action: onAudition
            )
            StudioCircleIconButton(
                systemName: "chevron.right",
                help: "Next slice"
            ) {
                onBrowse(1)
            }
        }
    }
}
