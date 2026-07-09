import SwiftUI

struct SlicerWaveformView: View {
    let buckets: [Float]
    let sliceSet: SliceSet
    let sampleLengthFrames: Int64
    let selectedMarkerID: UUID?
    var accent: Color = StudioTheme.transportAccent
    let onBoundaryMove: ((UUID, Int64) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                WaveformView(
                    buckets: buckets,
                    fillColor: accent,
                    inactiveColor: StudioTheme.border.opacity(0.65),
                    stepCount: max(1, Int((sliceSet.bars ?? 1).rounded()) * 16),
                    barStepInterval: 16
                )

                ForEach(sliceSet.markers) { marker in
                    boundaryLine(marker: marker, width: geo.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geo.size.width))
        }
    }

    private func boundaryLine(marker: SliceMarker, width: CGFloat) -> some View {
        let x = xPosition(for: marker.startFrame, width: width)
        return Rectangle()
            .fill(accent)
            .frame(width: marker.startFrame == 0 ? 2 : 1)
            .offset(x: x)
            .opacity(marker.startFrame == 0 ? 0.5 : 0.9)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onEnded { value in
                guard let onBoundaryMove,
                      let marker = nearestMovableMarker(to: value.location.x, width: width)
                else {
                    return
                }
                let ratio = min(max(value.location.x / max(width, 1), 0), 1)
                let nextFrame = Int64((Double(sampleLengthFrames) * Double(ratio)).rounded())
                onBoundaryMove(marker.id, nextFrame)
            }
    }

    private func nearestMovableMarker(to x: CGFloat, width: CGFloat) -> SliceMarker? {
        let movable = sliceSet.markers.dropFirst()
        guard !movable.isEmpty else { return nil }
        return movable.min { lhs, rhs in
            abs(xPosition(for: lhs.startFrame, width: width) - x) < abs(xPosition(for: rhs.startFrame, width: width) - x)
        }
    }

    private func xPosition(for frame: Int64, width: CGFloat) -> CGFloat {
        guard sampleLengthFrames > 0 else { return 0 }
        let ratio = Double(frame) / Double(sampleLengthFrames)
        return CGFloat(min(max(ratio, 0), 1)) * width
    }
}
