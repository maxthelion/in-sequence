import AppKit
import SwiftUI

#if DEBUG
struct WorkspaceHitTestDiagnostics: NSViewRepresentable {
    let label: String
    let section: WorkspaceSection

    func makeCoordinator() -> Coordinator {
        Coordinator(label: label, section: section)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.label = label
        context.coordinator.section = section
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.label = label
        context.coordinator.section = section
        context.coordinator.view = nsView
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
        var label: String
        var section: WorkspaceSection
        weak var view: ProbeView?
        private var monitor: Any?

        init(label: String, section: WorkspaceSection) {
            self.label = label
            self.section = section
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window
                else {
                    return event
                }

                let localPoint = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(localPoint) else {
                    return event
                }

                let hitView = event.window?.contentView?.hitTest(event.locationInWindow)
                NSLog(
                    "[WorkspaceHitTest] t=%.6f label=%@ section=%@ window=(%.1f,%.1f) local=(%.1f,%.1f) hit=%@ chain=%@",
                    ProcessInfo.processInfo.systemUptime,
                    label,
                    section.rawValue,
                    event.locationInWindow.x,
                    event.locationInWindow.y,
                    localPoint.x,
                    localPoint.y,
                    hitView.map { String(describing: type(of: $0)) } ?? "nil",
                    Self.viewChain(from: hitView)
                )

                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private static func viewChain(from view: NSView?) -> String {
            var names: [String] = []
            var current = view
            while let view = current, names.count < 10 {
                names.append(String(describing: type(of: view)))
                current = view.superview
            }
            return names.joined(separator: " <- ")
        }
    }
}
#endif
