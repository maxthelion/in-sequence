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
    case steps
    case velocity
    case chance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Steps"
        case .velocity: return "Velocity"
        case .chance: return "Chance"
        }
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
    let onTap: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 16)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(stepStates.enumerated()), id: \.offset) { localIndex, state in
                let absoluteIndex = indexOffset + localIndex
                Button {
                    onTap(absoluteIndex)
                } label: {
                    VStack(spacing: 7) {
                        Text("\(absoluteIndex + 1)")
                            .studioText(.eyebrow)
                            .foregroundStyle(state == .off ? StudioTheme.mutedText : StudioTheme.text)

                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                            .fill(fill(for: state))
                            .frame(height: 42)
                            .overlay {
                                VStack(spacing: 2) {
                                    Text(label(for: state))
                                        .studioText(.labelBold)
                                        .foregroundStyle(StudioTheme.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(modeLabel(for: state))
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(StudioTheme.text.opacity(0.82))
                                        .lineLimit(1)
                                }
                            }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 3)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(border(for: state, absoluteIndex: absoluteIndex), lineWidth: selectedStepIndex == absoluteIndex ? 2 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(playingStepIndex == absoluteIndex ? StudioTheme.success.opacity(0.95) : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(for state: State) -> String {
        switch state {
        case .off:
            return ""
        case let .on(sliceIndex, _):
            return sliceIndex == 0 ? "All" : "S\(sliceIndex)"
        }
    }

    private func modeLabel(for state: State) -> String {
        switch state {
        case .off:
            return ""
        case let .on(_, mode):
            return mode == .runFromHere ? "Run" : "One"
        }
    }

    private func fill(for state: State) -> Color {
        switch state {
        case .off:
            return Color.white.opacity(StudioOpacity.borderSubtle)
        case .on:
            return StudioTheme.cyan.opacity(0.82)
        }
    }

    private func border(for state: State, absoluteIndex: Int) -> Color {
        if selectedStepIndex == absoluteIndex {
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
            Rectangle()
                .fill(StudioTheme.violet.opacity(StudioOpacity.faintStroke))
                .frame(width: max(2, end - start))
                .offset(x: start)
        }
    }

    private func wholeHandle(frame: Int64, label: String, width: CGFloat) -> some View {
        let x = xPosition(for: frame, width: width)
        return VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(StudioTheme.text)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(StudioTheme.success.opacity(0.8), in: Capsule())
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
