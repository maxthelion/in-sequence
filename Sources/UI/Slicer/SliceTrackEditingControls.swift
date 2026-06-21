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
        case .gate: return "Gate"
        case .chance: return "Chance"
        }
    }

    /// Layers whose per-step value is fully wired into the engine clip model
    /// (slice index, velocity, chance). The remaining layers are part of the
    /// step grammar but are not yet backed by a per-step engine parameter, so
    /// they render the strip read-only with a NOTE.
    var isEngineBacked: Bool {
        switch self {
        case .steps, .velocity, .chance:
            return true
        case .direction, .noteRepeat, .gate:
            return false
        }
    }
}

struct SliceLayerTabRow: View {
    let selectedLayer: SliceTrackClipLayer
    let accent: Color
    let onSelectLayer: (SliceTrackClipLayer) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SliceTrackClipLayer.allCases) { layer in
                layerButton(layer)
            }
        }
    }

    @ViewBuilder
    private func layerButton(_ layer: SliceTrackClipLayer) -> some View {
        let isSelected = (selectedLayer == layer)
        let textColor: Color = isSelected ? StudioTheme.background : StudioTheme.text
        let fillColor: Color = isSelected ? accent : Color.white.opacity(StudioOpacity.subtleFill)
        let strokeColor: Color = isSelected ? Color.clear : StudioTheme.border.opacity(0.8)
        Button {
            onSelectLayer(layer)
        } label: {
            Text(layer.title)
                .studioText(.labelBold)
                .foregroundStyle(textColor)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(fillColor, in: Capsule())
                .overlay(
                    Capsule().stroke(strokeColor, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(StudioTheme.amber)

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
    var body: some View {
        HStack(spacing: 8) {
            Text("STEP EDIT")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.amber)

            Text("No editable layers")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44, alignment: .leading)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
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

                StepLayerRotaryArc(progress: control.normalizedValue)
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
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(isActiveLayer ? StudioTheme.amber.opacity(0.95) : StudioTheme.border.opacity(0.8), lineWidth: isActiveLayer ? 2 : StudioMetrics.borderWidth)
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

private struct StepLayerRotaryArc: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(135),
            endAngle: .degrees(135 + (270 * clampedProgress)),
            clockwise: false
        )
        return path
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
                    .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(border(for: state, absoluteIndex: absoluteIndex), lineWidth: selectedStepIndex == absoluteIndex ? 2 : StudioMetrics.borderWidth)
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

    private func border(for state: State, absoluteIndex: Int) -> Color {
        if selectedStepIndexes.contains(absoluteIndex) || selectedStepIndex == absoluteIndex {
            return StudioTheme.amber
        }
        switch state {
        case .off:
            return Color.white.opacity(StudioOpacity.borderSubtle)
        case .on:
            return StudioTheme.cyan.opacity(0.4)
        }
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
    let zoom: Double
    let scroll: Double
    let onSelectMarker: (UUID) -> Void
    let onMoveWholeStart: (Int64) -> Void
    let onMoveWholeEnd: (Int64) -> Void
    let onMoveSliceBoundary: (UUID, Int64) -> Void

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(1, geo.size.width - 20)
            let contentHeight = max(1, geo.size.height - 20)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    WaveformView(buckets: visibleBuckets, fillColor: StudioTheme.cyan, inactiveColor: StudioTheme.border.opacity(0.65))
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
            .gesture(dragGesture(width: contentWidth))
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
            .fill(marker.id == selectedMarkerID ? StudioTheme.amber : StudioTheme.violet)
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
            // Colour identifies, it never floods (ux-canon rule 12): the
            // selected region is a neutral wash; identity stays in the solid
            // amber/violet boundary lines.
            Rectangle()
                .fill(Color.white.opacity(StudioOpacity.borderSubtle))
                .frame(width: max(2, end - start))
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
                .background(StudioTheme.success, in: Capsule())
            Rectangle()
                .fill(StudioTheme.success)
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

// MARK: - Lower tab bar (Source · Slice · FX · Macros · Mixer)

enum SliceTrackLowerTab: String, CaseIterable, Identifiable {
    case source
    case slice
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .slice: return "Slice"
        case .fx: return "FX"
        case .macros: return "Macros"
        case .mixer: return "Mixer"
        }
    }
}

struct SliceLowerTabBar: View {
    let selectedTab: SliceTrackLowerTab
    let accent: Color
    let onSelect: (SliceTrackLowerTab) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SliceTrackLowerTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: SliceTrackLowerTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            onSelect(tab)
        } label: {
            Text(tab.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? accent : Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isSelected ? Color.clear : StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("slice-lower-tab-\(tab.rawValue)")
        .accessibilityLabel("\(tab.title) tab")
    }
}

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
    let detectionLabel: String
    let accent: Color
    let onChooseSample: () -> Void
    let onRemoveSample: () -> Void
    let onOpenSliceModal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Source")
                .studioText(.bodyBold)
                .foregroundStyle(StudioTheme.text)

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

    // One well, studio styling: sample name + remove on the first row,
    // the slice action(s) beneath, no white system buttons.
    private var unslicedState: some View {
        well {
            VStack(alignment: .leading, spacing: 12) {
                sampleNameRow
                HStack(spacing: 10) {
                    studioActionButton(
                        title: "Slice Sample",
                        systemImage: "scissors",
                        accent: StudioTheme.violet,
                        action: onOpenSliceModal
                    )
                    Text("Unsliced")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.amber)
                    Spacer()
                }
            }
        }
    }

    private var slicedState: some View {
        well {
            VStack(alignment: .leading, spacing: 12) {
                sampleNameRow
                HStack(spacing: 8) {
                    Text("\(sliceCount) slice\(sliceCount == 1 ? "" : "s")")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.success)
                    Text(detectionLabel)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer()
                }
                HStack(spacing: 10) {
                    studioActionButton(
                        title: "Edit Slices",
                        systemImage: "slider.horizontal.3",
                        accent: StudioTheme.violet,
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
        }
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

    // Studio-styled action button matching the app's capsule/outline grammar
    // (cf. lengthButton): neutral fill, accent lives in the outline.
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
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
            .overlay(Capsule().stroke(stroke, lineWidth: StudioMetrics.borderWidth))
        }
        .buttonStyle(.plain)
    }

    private func well<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.standard)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
            )
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
    let sampleName: String
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
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            browseRow
            divider
            SliceSamplePlayerParametersView(
                markerIndex: markerIndex,
                sampleName: sampleName,
                sliceDetail: rangeDetail,
                waveformBuckets: previewBuckets,
                mode: $mode,
                parameters: $parameters
            )
        }
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.violet.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sampleName) \(sliceTitle)")
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Text(rangeDetail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StudioCircleIconButton(
                systemName: "play.fill",
                size: StudioMetrics.ControlSize.medium,
                help: "Audition this slice",
                action: onAudition
            )
        }
        .padding(StudioMetrics.Spacing.standard)
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
        HStack(spacing: 8) {
            StudioCircleIconButton(
                systemName: "chevron.left",
                help: "Previous slice"
            ) {
                onBrowse(-1)
            }
            Spacer()
            Text("Browse slice")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer()
            StudioCircleIconButton(
                systemName: "chevron.right",
                help: "Next slice"
            ) {
                onBrowse(1)
            }
        }
        .padding(.horizontal, StudioMetrics.Spacing.comfortable)
        .padding(.vertical, StudioMetrics.Spacing.snug)
    }

    private var divider: some View {
        Divider().overlay(StudioTheme.border.opacity(0.7))
    }
}
