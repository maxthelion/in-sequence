import SwiftUI

struct WaveformView: View {
    let buckets: [Float]
    var fillColor: Color = StudioTheme.transportAccent
    var inactiveColor: Color = StudioTheme.border
    var stepCount: Int? = nil
    var barStepInterval: Int = 16
    var playheadFraction: CGFloat? = nil
    var showsTimelineRuler = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsTimelineRuler {
                timelineRuler
                    .frame(height: 14)
            }

            waveformCanvas
        }
    }

    private var waveformCanvas: some View {
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

    private var timelineRuler: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(timelineLabels) { label in
                    Text(label.title)
                        .studioText(label.isBar ? .microEmphasis : .micro)
                        .foregroundStyle(label.isBar ? StudioTheme.text : StudioTheme.mutedText)
                        .frame(width: label.isBar ? 18 : 28, alignment: label.step == 0 ? .leading : .center)
                        .position(x: labelX(label.step, width: geo.size.width), y: 7)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var timelineLabels: [TimelineLabel] {
        guard let stepCount, stepCount > 1 else { return [] }
        let barInterval = max(1, barStepInterval)
        let beatInterval = max(1, barInterval / 4)
        return stride(from: 0, to: stepCount, by: beatInterval).map { step in
            let bar = step / barInterval + 1
            let beat = (step % barInterval) / beatInterval + 1
            let isBar = beat == 1
            return TimelineLabel(
                step: step,
                title: isBar ? "\(bar)" : "\(bar).\(beat)",
                isBar: isBar
            )
        }
    }

    private func labelX(_ step: Int, width: CGFloat) -> CGFloat {
        guard let stepCount, stepCount > 0 else { return 0 }
        let rawX = CGFloat(step) / CGFloat(stepCount) * width
        return min(max(rawX, 8), max(8, width - 14))
    }

    private func drawGuides(context: GraphicsContext, size: CGSize) {
        guard let stepCount, stepCount > 1 else { return }
        let barInterval = max(1, barStepInterval)
        let beatInterval = max(1, barInterval / 4)
        for step in 0...stepCount {
            let ratio = CGFloat(step) / CGFloat(stepCount)
            let isBar = step % barInterval == 0
            let isBeat = step % beatInterval == 0
            let width: CGFloat = isBar ? 1.5 : (isBeat ? 1 : 0.5)
            let opacity: CGFloat = isBar ? 0.72 : (isBeat ? 0.38 : 0.14)
            let x = ratio * size.width
            let rect = CGRect(x: x, y: 0, width: width, height: size.height)
            context.fill(Path(rect), with: .color(StudioTheme.border.opacity(opacity))) // ux-canon-allow: Canvas guide strokes are structural meter lines
        }
    }

    private struct TimelineLabel: Identifiable {
        let step: Int
        let title: String
        let isBar: Bool

        var id: Int { step }
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
