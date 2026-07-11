import SwiftUI

struct PhraseCurvePreview: View {
    let points: [Double]
    let range: ClosedRange<Double>
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let sampled = (0..<64).map { index in
                    PhraseCurveSampler.sample(points: points, at: index, stepCount: 64, range: range)
                }

                for (index, value) in sampled.enumerated() {
                    let x = geometry.size.width * CGFloat(Double(index) / Double(max(1, sampled.count - 1)))
                    let yRatio = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
                    let y = geometry.size.height * CGFloat(1 - yRatio)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(accent, lineWidth: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
    }
}

struct PhraseAutomationPointEditor: View {
    let points: [Double]
    let range: ClosedRange<Double>
    let accent: Color
    let onChange: ([Double]) -> Void

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(
                x: 16,
                y: 12,
                width: max(1, geometry.size.width - 32),
                height: max(1, geometry.size.height - 42)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .fill(StudioTheme.subtleFill)

                Path { path in
                    for division in 0...4 {
                        let y = plot.minY + (plot.height * CGFloat(division) / 4)
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                }
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)

                Path { path in
                    for index in points.indices {
                        let position = pointPosition(index: index, plot: plot)
                        if index == points.startIndex {
                            path.move(to: position)
                        } else {
                            path.addLine(to: position)
                        }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.indices), id: \.self) { index in
                    Circle()
                        .fill(accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(StudioTheme.text, lineWidth: 2))
                        .position(pointPosition(index: index, plot: plot))
                        .contentShape(Circle().inset(by: -8))
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("automation-points"))
                                .onChanged { gesture in
                                    var next = points
                                    let fraction = 1 - min(max((gesture.location.y - plot.minY) / plot.height, 0), 1)
                                    next[index] = range.lowerBound + (Double(fraction) * (range.upperBound - range.lowerBound))
                                    onChange(next)
                                }
                        )
                        .accessibilityLabel(index == 0 ? "Start point" : index == points.count - 1 ? "End point" : "Point \(index + 1)")
                        .accessibilityValue(accessibilityValue(at: index))
                        .accessibilityAdjustableAction { direction in
                            let increment = max(0.0001, range.upperBound - range.lowerBound) * 0.05
                            var next = points
                            switch direction {
                            case .increment:
                                next[index] = min(points[index] + increment, range.upperBound)
                            case .decrement:
                                next[index] = max(points[index] - increment, range.lowerBound)
                            @unknown default:
                                return
                            }
                            onChange(next)
                        }
                }

                Text("START")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                    .position(x: plot.minX + 22, y: plot.maxY + 16)

                Text("END")
                    .studioText(.eyebrow)
                    .foregroundStyle(StudioTheme.mutedText)
                    .position(x: plot.maxX - 16, y: plot.maxY + 16)
            }
            .coordinateSpace(name: "automation-points")
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
    }

    private func pointPosition(index: Int, plot: CGRect) -> CGPoint {
        let xFraction = points.count > 1 ? CGFloat(index) / CGFloat(points.count - 1) : 0
        let value = min(max(points[index], range.lowerBound), range.upperBound)
        let yFraction = CGFloat((value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound))
        return CGPoint(
            x: plot.minX + (plot.width * xFraction),
            y: plot.maxY - (plot.height * yFraction)
        )
    }

    private func accessibilityValue(at index: Int) -> String {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        let fraction = (points[index] - range.lowerBound) / span
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent"
    }
}
