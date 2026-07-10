import SwiftUI

/// Pure math for the horizontal slide control so position/value mapping and
/// the pan label vocabulary are testable without rendering.
enum StudioSlideControlModel {
    static func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / span
    }

    static func value(forLocationX x: CGFloat, width: CGFloat, range: ClosedRange<Double>) -> Double {
        guard width > 0 else { return range.lowerBound }
        let position = min(max(Double(x / width), 0), 1)
        return range.lowerBound + position * (range.upperBound - range.lowerBound)
    }

    static func adjustedValue(
        _ value: Double,
        incrementing: Bool,
        step: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let delta = incrementing ? abs(step) : -abs(step)
        return min(max(value + delta, range.lowerBound), range.upperBound)
    }

    /// Compact pan vocabulary: L100…L1 / C / R1…R100.
    static func panLabel(for value: Double) -> String {
        if value < -0.005 {
            return "L\(Int((abs(value) * 100).rounded()))"
        }
        if value > 0.005 {
            return "R\(Int((value * 100).rounded()))"
        }
        return "C"
    }
}

/// The app-styled side-to-side control: pan rows under mixer faders and the
/// master A/B blend. Tokenized chrome (no stock slider thumb), fill from
/// center (pan) or leading edge (blend), full-width drag surface.
struct StudioSlideControl: View {
    enum FillStyle {
        case fromCenter
        case fromLeading
    }

    enum Chrome {
        /// Slim mixer-pan chrome retained for dense strip controls.
        case compact
        /// Rounded-rectangle trough and handle for larger modal/workspace controls.
        case roundedRectangle
    }

    let value: Double
    var range: ClosedRange<Double> = -1...1
    var fillStyle: FillStyle = .fromCenter
    var chrome: Chrome = .compact
    var accent: Color = StudioTheme.transportAccent
    var leadingLabel: String? = nil
    var trailingLabel: String? = nil
    var help: String = "Pan"
    var isEnabled = true
    var accessibilityStep: Double? = nil
    let onChange: (Double) -> Void
    var onEnd: (() -> Void)? = nil

    private var normalized: CGFloat {
        CGFloat(StudioSlideControlModel.normalized(value, in: range))
    }

    private var trackHeight: CGFloat {
        chrome == .compact ? 5 : 10
    }

    private var trackCornerRadius: CGFloat {
        chrome == .compact ? trackHeight / 2 : StudioMetrics.CornerRadius.mini
    }

    private var thumbSize: CGSize {
        chrome == .compact ? CGSize(width: 11, height: 11) : CGSize(width: 12, height: 22)
    }

    private var thumbCornerRadius: CGFloat {
        chrome == .compact ? thumbSize.width / 2 : StudioMetrics.CornerRadius.mini
    }

    private var controlAccent: Color {
        isEnabled ? accent : StudioTheme.border
    }

    var body: some View {
        HStack(spacing: 7) {
            if let leadingLabel {
                Text(leadingLabel)
                    .studioText(.micro)
                    .tracking(0.6)
                    .foregroundStyle(StudioTheme.mutedText)
                    .frame(width: 24, alignment: .leading)
            }

            track

            if let trailingLabel {
                // Bold-flat pass: the value reads in the accent colour.
                Text(trailingLabel)
                    .studioText(.micro)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .help(help)
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
        .accessibilityValue(trailingLabel ?? "\(Int((normalized * 100).rounded()))")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let step = accessibilityStep ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                onChange(StudioSlideControlModel.adjustedValue(value, incrementing: true, step: step, range: range))
            case .decrement:
                onChange(StudioSlideControlModel.adjustedValue(value, incrementing: false, step: step, range: range))
            @unknown default:
                break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbX = normalized * width
            let thumbWidth = thumbSize.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackCornerRadius, style: .continuous)
                    .fill(StudioTheme.inset)
                    .overlay(
                        RoundedRectangle(cornerRadius: trackCornerRadius, style: .continuous)
                            .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: 1)
                    )
                    .frame(height: trackHeight)

                if fillStyle == .fromCenter {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(StudioTheme.selectedFill)
                        .frame(width: 2, height: chrome == .compact ? 11 : 16)
                        .offset(x: width / 2 - 1)
                }

                fill(width: width)
                    .frame(height: trackHeight)

                RoundedRectangle(cornerRadius: thumbCornerRadius, style: .continuous)
                    .fill(chrome == .compact ? StudioTheme.text : controlAccent)
                    .frame(width: thumbWidth, height: thumbSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: thumbCornerRadius, style: .continuous)
                            .stroke(chrome == .compact ? Color.clear : StudioTheme.background, lineWidth: 2)
                    )
                    .offset(x: min(max(thumbX - thumbWidth / 2, 0), max(width - thumbWidth, 0)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        onChange(StudioSlideControlModel.value(forLocationX: drag.location.x, width: width, range: range))
                    }
                    .onEnded { _ in
                        onEnd?()
                    }
            )
        }
        .frame(height: chrome == .compact ? 18 : 28)
    }

    @ViewBuilder
    private func fill(width: CGFloat) -> some View {
        let thumbX = normalized * width
        switch fillStyle {
        case .fromCenter:
            let center = width / 2
            RoundedRectangle(cornerRadius: trackCornerRadius, style: .continuous)
                .fill(controlAccent)
                .frame(width: abs(thumbX - center))
                .offset(x: min(thumbX, center))
        case .fromLeading:
            RoundedRectangle(cornerRadius: trackCornerRadius, style: .continuous)
                .fill(controlAccent)
                .frame(width: thumbX)
        }
    }
}
