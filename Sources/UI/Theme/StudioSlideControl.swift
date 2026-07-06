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

    let value: Double
    var range: ClosedRange<Double> = -1...1
    var fillStyle: FillStyle = .fromCenter
    var accent: Color = StudioTheme.transportAccent
    var leadingLabel: String? = nil
    var trailingLabel: String? = nil
    var help: String = "Pan"
    let onChange: (Double) -> Void
    var onEnd: (() -> Void)? = nil

    private var normalized: CGFloat {
        CGFloat(StudioSlideControlModel.normalized(value, in: range))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
        .accessibilityValue(trailingLabel ?? "\(Int((normalized * 100).rounded()))")
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbX = normalized * width

            ZStack(alignment: .leading) {
                // Bold-flat pass: the trough is a solid inset cut with a
                // drawn outline, not a faint white wash.
                Capsule(style: .continuous)
                    .fill(StudioTheme.inset)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: 1)
                    )
                    .frame(height: 5)

                if fillStyle == .fromCenter {
                    Rectangle()
                        .fill(StudioTheme.selectedFill)
                        .frame(width: 2, height: 11)
                        .offset(x: width / 2 - 1)
                }

                fill(width: width)
                    .frame(height: 5)

                Circle()
                    .fill(StudioTheme.text)
                    .frame(width: 11, height: 11)
                    .offset(x: min(max(thumbX - 5.5, 0), max(width - 11, 0)))
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
        .frame(height: 18)
    }

    @ViewBuilder
    private func fill(width: CGFloat) -> some View {
        let thumbX = normalized * width
        switch fillStyle {
        case .fromCenter:
            let center = width / 2
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: abs(thumbX - center))
                .offset(x: min(thumbX, center))
        case .fromLeading:
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: thumbX)
        }
    }
}
