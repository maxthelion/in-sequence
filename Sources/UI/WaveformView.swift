import SwiftUI

struct WaveformView: View {
    let buckets: [Float]
    var fillColor: Color = StudioTheme.transportAccent
    var inactiveColor: Color = StudioTheme.border
    var stepCount: Int? = nil
    var barStepInterval: Int = 16
    var playheadFraction: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !buckets.isEmpty else { return }
                let barSpacing: CGFloat = 1
                let totalSpacing = barSpacing * CGFloat(buckets.count - 1)
                let fillWidth = max(1, (size.width - totalSpacing) / CGFloat(buckets.count))
                let barWidth = min(3, max(1, fillWidth))
                let occupiedWidth = CGFloat(buckets.count) * barWidth + totalSpacing
                let originX = max(0, (size.width - occupiedWidth) / 2)
                let midY = size.height / 2

                drawGuides(context: context, size: size)

                for (i, v) in buckets.enumerated() {
                    let clamped = max(0, min(CGFloat(v), 1))
                    let halfHeight = clamped * size.height / 2
                    let x = originX + CGFloat(i) * (barWidth + barSpacing)
                    let rect = CGRect(
                        x: x,
                        y: midY - halfHeight,
                        width: barWidth,
                        height: max(1, halfHeight * 2)
                    )
                    let color = clamped > 0.02 ? fillColor : inactiveColor
                    context.fill(Path(rect), with: .color(color))
                }

                if let playheadFraction {
                    let clamped = min(max(playheadFraction, 0), 1)
                    let x = clamped * size.width
                    let rect = CGRect(x: x, y: 0, width: 2, height: size.height)
                    context.fill(Path(rect), with: .color(fillColor))
                }
            }
        }
    }

    private func drawGuides(context: GraphicsContext, size: CGSize) {
        guard let stepCount, stepCount > 1 else { return }
        for step in 0...stepCount {
            let ratio = CGFloat(step) / CGFloat(stepCount)
            let isBar = step % max(1, barStepInterval) == 0
            let width: CGFloat = isBar ? 1.5 : 0.75
            let opacity: CGFloat = isBar ? 0.55 : 0.22
            let x = ratio * size.width
            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
            context.fill(Path(rect), with: .color(StudioTheme.border.opacity(opacity))) // ux-canon-allow: Canvas guide strokes are structural meter lines
        }
    }
}
