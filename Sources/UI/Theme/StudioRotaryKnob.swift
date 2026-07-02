import AppKit
import SwiftUI

/// The one rotary arc every knob in the app draws: a 270° sweep that starts
/// at 135° (≈7 o'clock), passes over the top of the dial, and ends at 45°
/// (≈5 o'clock) at full value. Same constants as the slicer step-edit dial
/// so all rotaries read identically.
struct StudioRotaryArc: Shape {
    var progress: Double

    /// 135° in SwiftUI's y-down coordinate space is the lower-left of the
    /// dial (≈7 o'clock); sweeping 270° from there passes over 12 o'clock
    /// and lands at ≈5 o'clock.
    static let startDegrees: Double = 135
    static let sweepDegrees: Double = 270

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clampedProgress = min(max(progress, 0), 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(Self.startDegrees),
            endAngle: .degrees(Self.startDegrees + Self.sweepDegrees * clampedProgress),
            clockwise: false
        )
        return path
    }
}

/// Standard rotary value control: drag vertically (or scroll) to change, arc
/// shows the normalized position from ~7 o'clock over the top to ~5 o'clock,
/// value reads in the center, label sits underneath. The hit target is always
/// at least `StudioMetrics.ControlSize.minimumHitTarget` across, however small
/// the drawn knob is.
struct StudioRotaryKnob: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var accent: Color = StudioTheme.cyan
    var size: CGFloat = 44
    var format: (Double) -> String = { "\(Int($0.rounded()))" }
    let onChange: (Double) -> Void
    /// Fired on every drag tick (in addition to `onChange` at release) so
    /// live controls can move the engine while the knob turns in place.
    var onLiveChange: ((Double) -> Void)?

    @State private var dragStartValue: Double?
    @State private var displayValue: Double
    @State private var scrollCommitWork: DispatchWorkItem?

    /// How long after the last scroll-wheel tick the value commits via
    /// `onChange` (wheel events have no reliable "ended" phase).
    private static let scrollCommitDelay: TimeInterval = 0.25

    init(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        accent: Color = StudioTheme.cyan,
        size: CGFloat = 44,
        format: @escaping (Double) -> String = { "\(Int($0.rounded()))" },
        onChange: @escaping (Double) -> Void,
        onLiveChange: ((Double) -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.accent = accent
        self.size = size
        self.format = format
        self.onChange = onChange
        self.onLiveChange = onLiveChange
        self._displayValue = State(initialValue: value)
    }

    private var normalized: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (displayValue - range.lowerBound) / span
    }

    /// The effective hit circle never drops below the platform minimum even
    /// when the drawn knob is smaller (mixer send knobs run down to 26pt).
    private var hitDiameter: CGFloat {
        max(size, StudioMetrics.ControlSize.minimumHitTarget)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(StudioTheme.border, lineWidth: 2)
                    .frame(width: size, height: size)

                StudioRotaryArc(progress: normalized)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size - 6, height: size - 6)

                // Bold-flat pass: values read in the accent colour, like the
                // reference's violet numerals.
                Text(format(displayValue))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            .background(
                StudioKnobScrollCatcher(onScrollTravel: handleScrollTravel)
                    .frame(width: hitDiameter, height: hitDiameter)
            )
            .contentShape(Circle().inset(by: (size - hitDiameter) / 2))
            .gesture(
                StudioDrag.verticalValueGesture(
                    value: Binding(
                        get: { displayValue },
                        set: { next in
                            displayValue = next
                            onLiveChange?(next)
                        }
                    ),
                    dragStart: $dragStartValue,
                    range: range,
                    onCommit: onChange
                )
            )

            Text(title.uppercased())
                .studioText(.micro)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .frame(width: size + 18)
        }
        .onChange(of: value) { _, newValue in
            if dragStartValue == nil, scrollCommitWork == nil {
                displayValue = newValue
            }
        }
        .onDisappear {
            // Commit a pending scroll edit instead of dropping it when the
            // knob unmounts mid-debounce.
            if let work = scrollCommitWork {
                work.cancel()
                scrollCommitWork = nil
                onChange(displayValue)
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(format(displayValue))
    }

    /// Scroll-wheel editing shares the drag feel: `travel` points of wheel
    /// movement act exactly like `travel` points of vertical drag.
    private func handleScrollTravel(_ travel: Double) {
        guard dragStartValue == nil else { return }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }
        let next = displayValue + (travel / StudioDrag.fullRangeTravel) * span
        let clamped = min(max(next, range.lowerBound), range.upperBound)
        if clamped != displayValue {
            displayValue = clamped
            onLiveChange?(clamped)
        }
        scheduleScrollCommit()
    }

    private func scheduleScrollCommit() {
        scrollCommitWork?.cancel()
        let work = DispatchWorkItem {
            scrollCommitWork = nil
            onChange(displayValue)
        }
        scrollCommitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollCommitDelay, execute: work)
    }
}

/// Invisible AppKit shim that feeds scroll-wheel events to a knob. SwiftUI
/// has no scroll-event gesture for arbitrary views at this deployment target,
/// so — like `StepGridMouseDownProbe` — it installs a local NSEvent monitor
/// and hit-tests the pointer against its own (circular) bounds. Unlike the
/// diagnostic probes it CONSUMES the event when the pointer is over the knob,
/// so turning a knob never also scrolls an enclosing ScrollView.
private struct StudioKnobScrollCatcher: NSViewRepresentable {
    let onScrollTravel: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollTravel: onScrollTravel)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.view = view
        context.coordinator.onScrollTravel = onScrollTravel
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onScrollTravel = onScrollTravel
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: Coordinator) {
        _ = nsView
        coordinator.removeMonitor()
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            _ = point
            return nil
        }
    }

    final class Coordinator {
        var onScrollTravel: (Double) -> Void
        weak var view: ProbeView?
        private var monitor: Any?

        init(onScrollTravel: @escaping (Double) -> Void) {
            self.onScrollTravel = onScrollTravel
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self,
                      let view,
                      view.window != nil,
                      event.window === view.window
                else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                let radius = min(view.bounds.width, view.bounds.height) / 2
                guard hypot(point.x - center.x, point.y - center.y) <= radius else {
                    return event
                }

                // Momentum tail after a trackpad flick is consumed (so the
                // page doesn't lurch) but doesn't keep turning the knob.
                if event.momentumPhase == [] {
                    let travel = StudioDrag.scrollTravel(
                        deltaY: event.scrollingDeltaY,
                        hasPreciseDeltas: event.hasPreciseScrollingDeltas
                    )
                    if travel != 0 {
                        onScrollTravel(travel)
                    }
                }

                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
