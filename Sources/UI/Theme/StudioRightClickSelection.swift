import AppKit
import SwiftUI

enum StudioSelectionGesture: Equatable, Sendable {
    case singleSelection
    case additiveToggle

    func selection<Item: Hashable>(
        targeting item: Item,
        in currentSelection: Set<Item>
    ) -> Set<Item> {
        selection(targeting: Set([item]), in: currentSelection)
    }

    func selection<Item: Hashable>(
        targeting targets: Set<Item>,
        in currentSelection: Set<Item>
    ) -> Set<Item> {
        guard !targets.isEmpty else { return currentSelection }

        switch self {
        case .singleSelection:
            return currentSelection == targets ? [] : targets
        case .additiveToggle:
            if targets.isSubset(of: currentSelection) {
                return currentSelection.subtracting(targets)
            }
            return currentSelection.union(targets)
        }
    }
}

extension View {
    /// Runs `select` when the user right-clicks inside this view, without
    /// consuming the event. SwiftUI's `contextMenu` still opens normally.
    func studioSelectOnRightClick(_ select: @escaping () -> Void) -> some View {
        background(StudioRightClickSelectionProbe(onRightClick: { _ in select() }))
    }

    /// Routes secondary click and Shift-primary click through the shared
    /// selection contract. Secondary clicks continue through the responder
    /// chain so any context menu can still open.
    func studioSelectionGesture(_ select: @escaping (StudioSelectionGesture) -> Void) -> some View {
        background(
            StudioRightClickSelectionProbe(
                onRightClick: { isAdditive in
                    select(isAdditive ? .additiveToggle : .singleSelection)
                },
                onShiftLeftClick: {
                    select(.additiveToggle)
                }
            )
        )
    }

    @ViewBuilder
    func studioSelectionGesture(_ select: ((StudioSelectionGesture) -> Void)?) -> some View {
        if let select {
            studioSelectionGesture(select)
        } else {
            self
        }
    }
}

private struct StudioRightClickSelectionProbe: NSViewRepresentable {
    let onRightClick: (Bool) -> Void
    var onShiftLeftClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        StudioRightClickSelectionRouter.shared.register(
            view,
            onRightClick: onRightClick,
            onShiftLeftClick: onShiftLeftClick
        )
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        StudioRightClickSelectionRouter.shared.register(
            nsView,
            onRightClick: onRightClick,
            onShiftLeftClick: onShiftLeftClick
        )
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        StudioRightClickSelectionRouter.shared.unregister(nsView)
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private final class StudioRightClickSelectionRouter {
    static let shared = StudioRightClickSelectionRouter()

    private struct Entry {
        weak var view: NSView?
        var onRightClick: (Bool) -> Void
        var onShiftLeftClick: (() -> Void)?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var order: [ObjectIdentifier] = []
    private var monitor: Any?
    private var isRoutingShiftLeftClick = false

    func register(
        _ view: NSView,
        onRightClick: @escaping (Bool) -> Void,
        onShiftLeftClick: (() -> Void)?
    ) {
        let id = ObjectIdentifier(view)
        if entries[id] == nil {
            order.append(id)
        }
        entries[id] = Entry(
            view: view,
            onRightClick: onRightClick,
            onShiftLeftClick: onShiftLeftClick
        )
        installMonitorIfNeeded()
    }

    func unregister(_ view: NSView) {
        let id = ObjectIdentifier(view)
        entries.removeValue(forKey: id)
        order.removeAll { $0 == id }
        removeMonitorIfIdle()
    }

    private func installMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.route(event)
        }
    }

    private func removeMonitorIfIdle() {
        guard entries.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func route(_ event: NSEvent) -> NSEvent? {
        pruneReleasedViews()

        switch event.type {
        case .rightMouseDown:
            matchingEntry(for: event)?.onRightClick(event.modifierFlags.contains(.shift))
            return event
        case .leftMouseDown:
            guard event.modifierFlags.contains(.shift),
                  let onShiftLeftClick = matchingEntry(for: event, shiftLeftOnly: true)?.onShiftLeftClick
            else {
                return event
            }
            isRoutingShiftLeftClick = true
            onShiftLeftClick()
            return nil
        case .leftMouseDragged:
            return isRoutingShiftLeftClick ? nil : event
        case .leftMouseUp:
            guard isRoutingShiftLeftClick else { return event }
            isRoutingShiftLeftClick = false
            return nil
        default:
            return event
        }
    }

    private func matchingEntry(for event: NSEvent, shiftLeftOnly: Bool = false) -> Entry? {
        guard let eventWindow = event.window else { return nil }

        for id in order.reversed() {
            guard let entry = entries[id],
                  let view = entry.view,
                  (!shiftLeftOnly || entry.onShiftLeftClick != nil),
                  view.window === eventWindow,
                  !view.isHiddenOrHasHiddenAncestor,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else {
                continue
            }
            return entry
        }
        return nil
    }

    private func pruneReleasedViews() {
        let releasedIDs = entries.compactMap { id, entry in
            entry.view == nil ? id : nil
        }
        guard !releasedIDs.isEmpty else { return }
        for id in releasedIDs {
            entries.removeValue(forKey: id)
        }
        let releasedSet = Set(releasedIDs)
        order.removeAll { releasedSet.contains($0) }
        removeMonitorIfIdle()
    }
}
