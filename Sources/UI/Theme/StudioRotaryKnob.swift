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
    var accent: Color = StudioTheme.transportAccent
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
        accent: Color = StudioTheme.transportAccent,
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
    /// Spec decision: 44pt absolute floor. In dense rows the inflated circles
    /// of neighbouring knobs can overlap; clicks resolve deterministically to
    /// the topmost sibling (SwiftUI hit-testing), and scroll-wheel input is
    /// arbitrated to the NEAREST knob center by `StudioKnobScrollRouter`, so
    /// the overlap never silently edits a farther knob.
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
/// so each mounted knob registers its (circular) hit region with the single
/// shared `StudioKnobScrollRouter`, which owns the ONE app-wide local NSEvent
/// monitor. Unlike the diagnostic probes (`StepGridMouseDownProbe`) the router
/// CONSUMES the event when the pointer is over a knob, so turning a knob never
/// also scrolls an enclosing ScrollView.
private struct StudioKnobScrollCatcher: NSViewRepresentable {
    let onScrollTravel: (Double) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        StudioKnobScrollRouter.shared.register(view, onScrollTravel: onScrollTravel)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        // Re-register so the router holds the freshest callback for this view.
        StudioKnobScrollRouter.shared.register(nsView, onScrollTravel: onScrollTravel)
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        StudioKnobScrollRouter.shared.unregister(nsView)
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

/// The single shared scroll-wheel router behind every `StudioRotaryKnob`:
/// one local NSEvent monitor total (installed while any knob is mounted, torn
/// down when the last unmounts), with all mounted knobs registered as hit
/// regions. Compared with the earlier per-knob monitors this fixes three
/// defects at once:
///
/// - **Visibility/clipping**: a knob whose hit circle is hidden
///   (`isHiddenOrHasHiddenAncestor`) or scrolled outside its enclosing
///   NSScrollView viewport (`visibleRect` no longer contains the pointer)
///   does not own wheel input, so scrolling over whatever is visibly there
///   can never silently edit an off-screen knob.
/// - **Overlap arbitration**: dense rows (mixer send clusters) draw knobs
///   whose ≥44pt inflated hit circles overlap; the router resolves a scroll
///   in the overlap to the knob whose center is NEAREST the pointer, instead
///   of whichever monitor happened to be installed first.
/// - **Scale**: one hit-test pass per scroll event regardless of how many
///   knobs are visible, instead of chaining one monitor per knob.
///
/// Known limit (shared with the previous shape): a knob covered by a
/// same-window SwiftUI overlay draws into the same NSHostingView, so AppKit
/// offers no occlusion query for it; sheets/popovers are separate windows and
/// are excluded by the window identity check.
private final class StudioKnobScrollRouter {
    static let shared = StudioKnobScrollRouter()

    private struct Registration {
        weak var view: NSView?
        let onScrollTravel: (Double) -> Void
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]
    private var monitor: Any?

    func register(_ view: NSView, onScrollTravel: @escaping (Double) -> Void) {
        registrations[ObjectIdentifier(view)] = Registration(view: view, onScrollTravel: onScrollTravel)
        installMonitorIfNeeded()
    }

    func unregister(_ view: NSView) {
        registrations.removeValue(forKey: ObjectIdentifier(view))
        if registrations.isEmpty {
            removeMonitor()
        }
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.route(event)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Returns nil (consuming the event) when a visible knob owns the pointer,
    /// or the event unchanged so it scrolls the page as normal.
    private func route(_ event: NSEvent) -> NSEvent? {
        guard let eventWindow = event.window else { return event }

        var best: (onScrollTravel: (Double) -> Void, distance: CGFloat)?
        for (key, registration) in registrations {
            guard let view = registration.view else {
                // A dismantle can be skipped when a whole hierarchy is torn
                // down at once; prune dead entries opportunistically.
                registrations.removeValue(forKey: key)
                continue
            }
            guard let window = view.window, window === eventWindow else { continue }
            guard !view.isHiddenOrHasHiddenAncestor else { continue }

            let point = view.convert(event.locationInWindow, from: nil)
            // A knob scrolled outside its ScrollView viewport keeps its window
            // geometry but loses its visibleRect — it must not eat the wheel
            // input of whatever is visibly at that position.
            guard view.visibleRect.contains(point) else { continue }

            let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let radius = min(view.bounds.width, view.bounds.height) / 2
            let distance = hypot(point.x - center.x, point.y - center.y)
            guard distance <= radius else { continue }

            if best == nil || distance < best!.distance {
                best = (registration.onScrollTravel, distance)
            }
        }

        guard let best else { return event }

        // Momentum tail after a trackpad flick is consumed (so the page
        // doesn't lurch) but doesn't keep turning the knob.
        if event.momentumPhase == [] {
            let travel = StudioDrag.scrollTravel(
                deltaY: event.scrollingDeltaY,
                hasPreciseDeltas: event.hasPreciseScrollingDeltas
            )
            if travel != 0 {
                best.onScrollTravel(travel)
            }
        }

        return nil
    }
}
