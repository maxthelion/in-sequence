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
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
