import AppKit
import SwiftUI

/// The one circular icon button used across the app: system glyph in a
/// bordered circle. Sizes come from `StudioMetrics.ControlSize`.
struct StudioCircleIconButton: View {
    let systemName: String
    var size: CGFloat = StudioMetrics.ControlSize.close
    var accent: Color? = nil
    var isEnabled: Bool = true
    var help: String = ""
    var keyboardShortcut: KeyboardShortcut? = nil
    let action: () -> Void

    private var glyphSize: CGFloat {
        (size * 0.42).rounded()
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(stroke, lineWidth: StudioMetrics.borderWidth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyboardShortcut)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemName : help)
    }

    /// Bold-flat pass: an accented button is a fully solid accent circle
    /// with a dark glyph inside; the plain state is outline-only on the
    /// ground — no in-between washes.
    private var foreground: Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.35)
        }
        return accent == nil ? StudioTheme.text : StudioTheme.background
    }

    private var fill: Color {
        guard isEnabled else {
            return Color.clear
        }
        return accent ?? Color.clear
    }

    private var stroke: Color {
        guard isEnabled else {
            return StudioTheme.border.opacity(0.45)
        }
        // ux-canon-allow: nil accent is the deliberate PLAIN utility button
        // (close/back/stepper affordances) — outline-only structure on the
        // ground, not stateful chrome. Accented call sites opt in explicitly;
        // do not use the plain form for anything that carries surface state.
        return accent ?? StudioTheme.border
    }
}

/// The compact 24pt square icon action shared by row/card action clusters
/// (phrase-row insert/duplicate/remove, scene-card duplicate/delete): 11pt
/// bold glyph on a subtleFill badge, muted `inheritedContent` tint when
/// disabled. Promoted from private per-surface copies — add new 24pt icon
/// actions through this control, not a fresh copy.
struct StudioIconActionButton: View {
    let systemImage: String
    var isDisabled: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemImage : help)
    }
}

/// Shared text command chrome for modal and workflow actions. Primary commands
/// use one solid surface accent; secondary commands remain outline-only, with
/// an optional accent for contextual utilities such as Normalize.
struct StudioCommandButton: View {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    var role: Role = .secondary
    var accent: Color? = nil
    var fillsWidth = false
    var isEnabled = true
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, StudioMetrics.Spacing.comfortable)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: StudioMetrics.ControlSize.large)
                .background(fill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(stroke, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(title)
    }

    private var resolvedAccent: Color {
        accent ?? StudioTheme.transportAccent
    }

    private var foreground: Color {
        guard isEnabled else { return StudioTheme.mutedText }
        switch role {
        case .primary:
            return StudioTheme.background
        case .secondary:
            return accent ?? StudioTheme.text
        }
    }

    private var fill: Color {
        guard isEnabled else { return StudioTheme.disabledSubtleFill }
        switch role {
        case .primary:
            return resolvedAccent
        case .secondary:
            return StudioTheme.subtleFill
        }
    }

    private var stroke: Color {
        guard isEnabled else { return StudioTheme.border }
        switch role {
        case .primary:
            return resolvedAccent
        case .secondary:
            return accent ?? StudioTheme.border
        }
    }
}

/// Vertically stacked increment/decrement buttons (the BPM stepper, layer
/// cycler, and friends). `symbols` defaults to plus/minus; pass chevrons for
/// cycling semantics.
struct StudioStepperButtons: View {
    var symbols: (up: String, down: String) = ("plus", "minus")
    var upHelp: String = "Increase"
    var downHelp: String = "Decrease"
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            stepButton(systemName: symbols.up, help: upHelp, action: onUp)
            stepButton(systemName: symbols.down, help: downHelp, action: onDown)
        }
    }

    private func stepButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 18, height: 13)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct StudioCustomVerticalScrollView<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> StudioCustomScrollContainer<Content> {
        StudioCustomScrollContainer(axis: .vertical, rootView: content)
    }

    func updateNSView(_ nsView: StudioCustomScrollContainer<Content>, context: Context) {
        nsView.rootView = content
    }
}

enum StudioScrollbarMetrics {
    static let overflowTolerance: CGFloat = 1

    static func isOverflowing(contentLength: CGFloat, viewportLength: CGFloat) -> Bool {
        contentLength > viewportLength + overflowTolerance
    }

    static func thumbLength(
        contentLength: CGFloat,
        viewportLength: CGFloat,
        trackLength: CGFloat,
        minimumLength: CGFloat
    ) -> CGFloat {
        guard isOverflowing(contentLength: contentLength, viewportLength: viewportLength) else {
            return max(0, trackLength)
        }
        let ratio = min(max(viewportLength / max(contentLength, 1), 0), 1)
        return min(max(minimumLength, trackLength * ratio), max(0, trackLength))
    }

    static func thumbOffset(
        contentLength: CGFloat,
        viewportLength: CGFloat,
        contentOffset: CGFloat,
        trackLength: CGFloat,
        thumbLength: CGFloat
    ) -> CGFloat {
        let maximumContentOffset = max(1, contentLength - viewportLength)
        let availableTrack = max(0, trackLength - thumbLength)
        let fraction = min(max(contentOffset / maximumContentOffset, 0), 1)
        return availableTrack * fraction
    }
}

enum StudioScrollChromeDiscovery {
    /// Returns the candidate whose viewport most closely matches the attached
    /// SwiftUI view. A List's private scroll view is often a sibling of the
    /// background representable, so ancestry alone can select the outer
    /// workspace scroll view instead.
    static func nearestMatchingCandidate(
        targetRect: NSRect,
        candidateRects: [NSRect]
    ) -> Int? {
        guard targetRect.width > 0, targetRect.height > 0 else { return nil }

        return candidateRects.enumerated()
            .filter { _, candidateRect in
                guard candidateRect.width > 0, candidateRect.height > 0 else { return false }
                let intersection = candidateRect.intersection(targetRect)
                let widthDelta = abs(candidateRect.width - targetRect.width)
                let heightDelta = abs(candidateRect.height - targetRect.height)
                return !intersection.isNull
                    && intersection.width >= min(targetRect.width, candidateRect.width) * 0.8
                    && intersection.height >= min(targetRect.height, candidateRect.height) * 0.8
                    && widthDelta <= max(32, targetRect.width * 0.2)
                    && heightDelta <= max(32, targetRect.height * 0.2)
            }
            .min { lhs, rhs in
                geometryDistance(targetRect, lhs.element) < geometryDistance(targetRect, rhs.element)
            }?.offset
    }

    private static func geometryDistance(_ targetRect: NSRect, _ candidateRect: NSRect) -> CGFloat {
        abs(targetRect.minX - candidateRect.minX)
            + abs(targetRect.maxX - candidateRect.maxX)
            + abs(targetRect.minY - candidateRect.minY)
            + abs(targetRect.maxY - candidateRect.maxY)
    }
}

struct StudioCustomHorizontalScrollView<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> StudioCustomScrollContainer<Content> {
        StudioCustomScrollContainer(axis: .horizontal, rootView: content)
    }

    func updateNSView(_ nsView: StudioCustomScrollContainer<Content>, context: Context) {
        nsView.rootView = content
    }
}

final class StudioCustomScrollContainer<Content: View>: NSView {
    private let axis: StudioCustomScrollAxis
    private let scrollView = NSScrollView()
    private let hostingView: NSHostingView<Content>
    private let scrollbarView: StudioScrollbarChromeView
    private var boundsObserver: NSObjectProtocol?

    var rootView: Content {
        get { hostingView.rootView }
        set {
            hostingView.rootView = newValue
            needsLayout = true
        }
    }

    init(axis: StudioCustomScrollAxis, rootView: Content) {
        self.axis = axis
        self.hostingView = NSHostingView(rootView: rootView)
        self.scrollbarView = StudioScrollbarChromeView(axis: axis)
        super.init(frame: .zero)

        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = hostingView

        addSubview(scrollView)
        addSubview(scrollbarView)

        scrollbarView.scrollToFraction = { [weak self] fraction in
            self?.scroll(to: fraction)
        }

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollbar()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func layout() {
        super.layout()

        scrollView.frame = bounds
        let viewport = scrollView.contentView.bounds.size

        switch axis {
        case .vertical:
            let fittingWidth = max(1, viewport.width - 14)
            hostingView.frame.size = NSSize(width: fittingWidth, height: CGFloat.greatestFiniteMagnitude)
            let fittingHeight = hostingView.fittingSize.height
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: fittingWidth,
                height: max(viewport.height, fittingHeight)
            )
            scrollbarView.frame = NSRect(
                x: bounds.maxX - 8,
                y: 0,
                width: 8,
                height: bounds.height
            )
        case .horizontal:
            hostingView.frame.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: max(1, viewport.height - 14))
            let fittingWidth = hostingView.fittingSize.width
            hostingView.frame = NSRect(
                x: 0,
                y: 0,
                width: max(1, fittingWidth),
                height: max(1, viewport.height - 14)
            )
            scrollbarView.frame = NSRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: 8
            )
        }

        updateScrollbar()
    }

    private func updateScrollbar() {
        let viewport = scrollView.contentView.bounds.size
        let content = hostingView.frame.size
        let origin = scrollView.contentView.bounds.origin
        scrollbarView.update(
            contentLength: axis == .vertical ? content.height : content.width,
            viewportLength: axis == .vertical ? viewport.height : viewport.width,
            offset: axis == .vertical ? origin.y : origin.x
        )
    }

    private func scroll(to fraction: CGFloat) {
        let viewport = scrollView.contentView.bounds.size
        let content = hostingView.frame.size
        let maxOffset = max(0, (axis == .vertical ? content.height - viewport.height : content.width - viewport.width))
        let clampedFraction = min(max(fraction, 0), 1)
        let offset = maxOffset * clampedFraction
        let point: NSPoint
        switch axis {
        case .vertical:
            point = NSPoint(x: 0, y: offset)
        case .horizontal:
            point = NSPoint(x: offset, y: 0)
        }
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateScrollbar()
    }
}

enum StudioCustomScrollAxis {
    case vertical
    case horizontal
}

final class StudioScrollbarChromeView: NSView {
    var scrollToFraction: ((CGFloat) -> Void)?

    private let axis: StudioCustomScrollAxis
    private var contentLength: CGFloat = 0
    private var viewportLength: CGFloat = 0
    private var offset: CGFloat = 0
    private var isDragging = false

    override var isFlipped: Bool { true }

    init(axis: StudioCustomScrollAxis) {
        self.axis = axis
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(contentLength: CGFloat, viewportLength: CGFloat, offset: CGFloat) {
        self.contentLength = contentLength
        self.viewportLength = viewportLength
        self.offset = offset
        isHidden = !StudioScrollbarMetrics.isOverflowing(
            contentLength: contentLength,
            viewportLength: viewportLength
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isHidden, let context = NSGraphicsContext.current?.cgContext else { return }

        let rail = axis == .vertical
            ? bounds.insetBy(dx: 2, dy: 4)
            : bounds.insetBy(dx: 4, dy: 2)
        let railPath = CGPath(
            roundedRect: rail,
            cornerWidth: 2,
            cornerHeight: 2,
            transform: nil
        )
        context.setFillColor(NSColor(StudioTheme.border.opacity(0.28)).cgColor)
        context.addPath(railPath)
        context.fillPath()

        let thumb = thumbRect(in: rail)
        let thumbPath = CGPath(
            roundedRect: thumb,
            cornerWidth: 2,
            cornerHeight: 2,
            transform: nil
        )
        context.setFillColor(NSColor(StudioTheme.transportAccent.opacity(isDragging ? 0.95 : 0.74)).cgColor)
        context.addPath(thumbPath)
        context.fillPath()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateScrollPosition(with: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateScrollPosition(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    private func updateScrollPosition(with event: NSEvent) {
        let rail = axis == .vertical
            ? bounds.insetBy(dx: 2, dy: 4)
            : bounds.insetBy(dx: 4, dy: 2)
        let local = convert(event.locationInWindow, from: nil)
        let thumbLength = axis == .vertical ? thumbRect(in: rail).height : thumbRect(in: rail).width
        let available = max(1, (axis == .vertical ? rail.height : rail.width) - thumbLength)
        let coordinate = axis == .vertical ? local.y - rail.minY : local.x - rail.minX
        let fraction = (coordinate - thumbLength / 2) / available
        scrollToFraction?(fraction)
    }

    private func thumbRect(in rail: NSRect) -> NSRect {
        switch axis {
        case .vertical:
            let height = StudioScrollbarMetrics.thumbLength(
                contentLength: contentLength,
                viewportLength: viewportLength,
                trackLength: rail.height,
                minimumLength: 34
            )
            let y = rail.minY + StudioScrollbarMetrics.thumbOffset(
                contentLength: contentLength,
                viewportLength: viewportLength,
                contentOffset: offset,
                trackLength: rail.height,
                thumbLength: height
            )
            return NSRect(x: rail.minX, y: y, width: rail.width, height: height)
        case .horizontal:
            let width = StudioScrollbarMetrics.thumbLength(
                contentLength: contentLength,
                viewportLength: viewportLength,
                trackLength: rail.width,
                minimumLength: 44
            )
            let x = rail.minX + StudioScrollbarMetrics.thumbOffset(
                contentLength: contentLength,
                viewportLength: viewportLength,
                contentOffset: offset,
                trackLength: rail.width,
                thumbLength: width
            )
            return NSRect(x: x, y: rail.minY, width: width, height: rail.height)
        }
    }
}

/// Installs the shared vertical scrollbar chrome on a SwiftUI control that
/// owns its own AppKit scroll view (notably `List`). The native scrollbar is
/// hidden, but the original scrolling, focus, accessibility, and `onMove`
/// implementation remain intact.
struct StudioAttachedVerticalScrollChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> StudioScrollChromeAttachmentView {
        StudioScrollChromeAttachmentView()
    }

    func updateNSView(_ nsView: StudioScrollChromeAttachmentView, context: Context) {
        nsView.attachWhenReady()
    }

    static func dismantleNSView(_ nsView: StudioScrollChromeAttachmentView, coordinator: ()) {
        nsView.detach()
    }
}

final class StudioScrollChromeAttachmentView: NSView {
    private weak var scrollView: NSScrollView?
    private let chrome = StudioScrollbarChromeView(axis: .vertical)
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        postsFrameChangedNotifications = true
        DispatchQueue.main.async { [weak self] in
            self?.attachWhenReady()
        }
    }

    func attachWhenReady() {
        guard let window else { return }
        // SwiftUI may install a List background as a sibling of its private
        // NSScrollView. Always compare every visible candidate so an outer
        // workspace scroll view cannot win merely because it is an ancestor.
        let candidate = matchingScrollView(in: window)
        if let candidate, candidate !== scrollView {
            attach(to: candidate)
        }
        updateChrome()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        chrome.removeFromSuperview()
        scrollView = nil
    }

    private func attach(to scrollView: NSScrollView) {
        detach()
        self.scrollView = scrollView
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true

        scrollView.addSubview(chrome, positioned: .above, relativeTo: nil)
        chrome.scrollToFraction = { [weak self] fraction in
            self?.scroll(to: fraction)
        }

        observe(NSView.boundsDidChangeNotification, object: scrollView.contentView)
        observe(NSView.frameDidChangeNotification, object: scrollView)
        if let documentView = scrollView.documentView {
            observe(NSView.frameDidChangeNotification, object: documentView)
        }
        observeAttachmentFrameChanges()
        updateChrome()
    }

    private func matchingScrollView(in window: NSWindow) -> NSScrollView? {
        guard let contentView = window.contentView else { return nil }
        let targetRect = convert(bounds, to: nil)
        let candidates = scrollViews(in: contentView).filter { $0.window === window }
        let candidateRects = candidates.map { $0.convert($0.bounds, to: nil) }
        guard let index = StudioScrollChromeDiscovery.nearestMatchingCandidate(
            targetRect: targetRect,
            candidateRects: candidateRects
        ) else { return nil }
        return candidates[index]
    }

    private func scrollViews(in root: NSView) -> [NSScrollView] {
        var matches: [NSScrollView] = []
        if let scrollView = root as? NSScrollView {
            matches.append(scrollView)
        }
        return root.subviews.reduce(into: matches) { result, subview in
            result.append(contentsOf: scrollViews(in: subview))
        }
    }

    private func observe(_ name: Notification.Name, object: AnyObject) {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                self?.updateChrome()
            }
        )
    }

    private func observeAttachmentFrameChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                self?.attachWhenReady()
            }
        )
    }

    private func updateChrome() {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        chrome.frame = NSRect(
            x: scrollView.bounds.maxX - 8,
            y: scrollView.bounds.minY,
            width: 8,
            height: scrollView.bounds.height
        )
        chrome.update(
            contentLength: documentView.frame.height,
            viewportLength: scrollView.contentView.bounds.height,
            offset: scrollView.contentView.bounds.minY
        )
    }

    private func scroll(to fraction: CGFloat) {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let viewportLength = scrollView.contentView.bounds.height
        let maximumOffset = max(0, documentView.frame.height - viewportLength)
        let offset = maximumOffset * min(max(fraction, 0), 1)
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateChrome()
    }
}

enum StudioDrag {
    /// Shared vertical-drag sensitivity for value editing (knobs and cells):
    /// pixels of travel for a full-range sweep.
    static let fullRangeTravel: Double = 200

    /// Points of travel one line of a non-precise (classic mouse wheel)
    /// scroll delta is worth. Precise devices (trackpads) already report
    /// point deltas; wheels report lines, which would otherwise crawl.
    static let wheelLinePoints: Double = 8

    /// Normalizes a scroll-wheel delta to drag-equivalent points so wheel
    /// and drag share the single `fullRangeTravel` feel constant.
    static func scrollTravel(deltaY: Double, hasPreciseDeltas: Bool) -> Double {
        hasPreciseDeltas ? deltaY : deltaY * wheelLinePoints
    }

    /// The one vertical drag-to-value gesture all knobs share: dragging the
    /// full `fullRangeTravel` height sweeps the full range; the value clamps
    /// to the range; release commits via `onCommit`.
    static func verticalValueGesture(
        value: Binding<Double>,
        dragStart: Binding<Double?>,
        range: ClosedRange<Double>,
        onCommit: @escaping (Double) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart.wrappedValue == nil {
                    dragStart.wrappedValue = value.wrappedValue
                }
                let delta = -drag.translation.height / fullRangeTravel
                let span = range.upperBound - range.lowerBound
                let next = (dragStart.wrappedValue ?? value.wrappedValue) + delta * span
                value.wrappedValue = min(max(next, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in
                dragStart.wrappedValue = nil
                onCommit(value.wrappedValue)
            }
    }
}
