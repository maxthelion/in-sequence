import AppKit
import SwiftUI

extension View {
    /// Runs `select` when the user right-clicks inside this view, without
    /// consuming the event. SwiftUI's `contextMenu` still opens normally.
    func studioSelectOnRightClick(_ select: @escaping () -> Void) -> some View {
        background(StudioRightClickSelectionProbe(onRightClick: select))
    }
}

private struct StudioRightClickSelectionProbe: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        StudioRightClickSelectionRouter.shared.register(view, onRightClick: onRightClick)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        StudioRightClickSelectionRouter.shared.register(nsView, onRightClick: onRightClick)
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
        var onRightClick: () -> Void
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var order: [ObjectIdentifier] = []
    private var monitor: Any?

    func register(_ view: NSView, onRightClick: @escaping () -> Void) {
        let id = ObjectIdentifier(view)
        if entries[id] == nil {
            order.append(id)
        }
        entries[id] = Entry(view: view, onRightClick: onRightClick)
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.route(event)
            return event
        }
    }

    private func removeMonitorIfIdle() {
        guard entries.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func route(_ event: NSEvent) {
        pruneReleasedViews()
        guard let eventWindow = event.window else { return }

        for id in order.reversed() {
            guard let entry = entries[id],
                  let view = entry.view,
                  view.window === eventWindow,
                  !view.isHiddenOrHasHiddenAncestor,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else {
                continue
            }
            entry.onRightClick()
            return
        }
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
