import AppKit
import AVFoundation
import CoreAudioKit
import Foundation

@MainActor
protocol AudioUnitWindowPresentable: AnyObject {
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void)
    func captureHostedState() throws -> Data?
}

extension AVAudioUnit: AudioUnitWindowPresentable {
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void) {
        auAudioUnit.requestViewController(completionHandler: { controller in
            completion(controller)
        })
    }

    func captureHostedState() throws -> Data? {
        try FullStateCoder.encode(auAudioUnit.fullState)
    }
}

@MainActor
final class AUWindowHost: NSObject, NSWindowDelegate {
    static let shared = AUWindowHost()

    enum WindowKey: Hashable {
        case track(UUID)
        case group(TrackGroupID)
    }

    private struct WindowEntry {
        weak var presenter: AudioUnitWindowPresentable?
        let window: NSWindow
        let stateWriteback: (Data?) -> Void
    }

    private var windows: [WindowKey: WindowEntry] = [:]

    private func log(_ message: String) {
        NSLog("[AUWindowHost] \(message)")
    }

    func open(
        for key: WindowKey,
        presenter: AudioUnitWindowPresentable,
        title: String,
        stateWriteback: @escaping (Data?) -> Void
    ) {
        if let existing = windows[key] {
            log("open reuse existing key=\(String(describing: key)) title=\(title)")
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        log("open request key=\(String(describing: key)) title=\(title)")
        presenter.requestHostedViewController { [weak self] controller in
            guard let self else {
                return
            }

            self.log("requestHostedViewController completed key=\(String(describing: key)) controller=\(controller.map { String(describing: type(of: $0)) } ?? "nil")")
            let contentController = controller ?? NSViewController()
            let window = NSWindow(contentViewController: contentController)
            let preferred = contentController.preferredContentSize
            let size = preferred == .zero ? NSSize(width: 720, height: 480) : preferred
            window.setContentSize(size)
            window.title = title
            window.delegate = self
            window.isReleasedWhenClosed = false
            windows[key] = WindowEntry(
                presenter: presenter,
                window: window,
                stateWriteback: stateWriteback
            )
            self.log("window opened key=\(String(describing: key)) size=\(Int(size.width))x\(Int(size.height))")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func open(
        for trackID: UUID,
        presenter: AudioUnitWindowPresentable,
        title: String,
        stateWriteback: @escaping (Data?) -> Void
    ) {
        open(for: .track(trackID), presenter: presenter, title: title, stateWriteback: stateWriteback)
    }

    func close(for key: WindowKey) {
        guard let entry = windows[key] else {
            return
        }
        log("close key=\(String(describing: key))")
        entry.window.close()
    }

    func close(for trackID: UUID) {
        close(for: .track(trackID))
    }

    func isOpen(for key: WindowKey) -> Bool {
        windows[key] != nil
    }

    func isOpen(for trackID: UUID) -> Bool {
        isOpen(for: .track(trackID))
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let match = windows.first(where: { $0.value.window === closingWindow })
        else {
            return
        }

        if let presenter = match.value.presenter {
            let state: Data?
            do {
                state = try presenter.captureHostedState()
            } catch {
                assertionFailure("AUWindowHost state capture failed: \(error)")
                NSLog("[AUWindowHost] state capture failed key=\(String(describing: match.key)) error=\(error)")
                state = nil
            }
            log("windowWillClose writeback key=\(String(describing: match.key)) state=\((state ?? nil)?.count ?? 0) bytes")
            match.value.stateWriteback(state ?? nil)
        } else {
            log("windowWillClose writeback key=\(String(describing: match.key)) presenter gone")
            match.value.stateWriteback(nil)
        }

        windows.removeValue(forKey: match.key)
    }
}
