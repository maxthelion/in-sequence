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
                let visibleBuckets = Self.fittedBuckets(buckets, width: size.width, maxBarWidth: 3, spacing: barSpacing)
                guard !visibleBuckets.isEmpty else { return }
                let slotWidth = size.width / CGFloat(visibleBuckets.count)
                let barWidth = min(3, max(1, slotWidth - barSpacing))
                let midY = size.height / 2

                drawGuides(context: context, size: size)

                for (i, v) in visibleBuckets.enumerated() {
                    let clamped = max(0, min(CGFloat(v), 1))
                    let halfHeight = clamped * size.height / 2
                    let x = CGFloat(i) * slotWidth + max(0, (slotWidth - barWidth) / 2)
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

    static func fittedBuckets(
        _ buckets: [Float],
        width: CGFloat,
        maxBarWidth: CGFloat = 3,
        spacing: CGFloat = 1
    ) -> [Float] {
        guard width > 0, !buckets.isEmpty else { return [] }
        let slotWidth = max(1, maxBarWidth + spacing)
        let capacity = max(1, Int(floor(width / slotWidth)))
        guard buckets.count > capacity else { return buckets }

        return (0..<capacity).map { index in
            let lower = Int(floor(Double(index) * Double(buckets.count) / Double(capacity)))
            let upper = Int(ceil(Double(index + 1) * Double(buckets.count) / Double(capacity)))
            let range = buckets[max(0, lower)..<min(buckets.count, max(lower + 1, upper))]
            return range.max() ?? 0
        }
    }
}
