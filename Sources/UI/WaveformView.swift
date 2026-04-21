import SwiftUI

struct WaveformView: View {
    let buckets: [Float]
    var fillColor: Color = StudioTheme.success
    var inactiveColor: Color = StudioTheme.border

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !buckets.isEmpty else { return }
                let barSpacing: CGFloat = 1
                let totalSpacing = barSpacing * CGFloat(buckets.count - 1)
                let barWidth = max(1, (size.width - totalSpacing) / CGFloat(buckets.count))
                let midY = size.height / 2

                for (i, v) in buckets.enumerated() {
                    let clamped = max(0, min(CGFloat(v), 1))
                    let halfHeight = clamped * size.height / 2
                    let x = CGFloat(i) * (barWidth + barSpacing)
                    let rect = CGRect(
                        x: x,
                        y: midY - halfHeight,
                        width: barWidth,
                        height: max(1, halfHeight * 2)
                    )
                    let color = clamped > 0.02 ? fillColor : inactiveColor
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}
