import AppKit
import AVFoundation
import CoreAudioKit
import Foundation

@MainActor
protocol AudioUnitWindowPresentable: AnyObject {
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void)
    func captureHostedState() throws -> Data?
}

@MainActor
protocol AUWindowHosting: AnyObject {
    func closeAll()
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
            if let existingPresenter = existing.presenter, existingPresenter === presenter {
                log("open reuse existing key=\(String(describing: key)) title=\(title)")
                existing.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            log("open replacing existing key=\(String(describing: key)) title=\(title)")
            windows.removeValue(forKey: key)
            existing.window.delegate = nil
            existing.window.close()
        }

        log("open request key=\(String(describing: key)) title=\(title)")
        presenter.requestHostedViewController { [weak self] controller in
            guard let self else {
                return
            }

            self.log("requestHostedViewController completed key=\(String(describing: key)) controller=\(controller.map { String(describing: type(of: $0)) } ?? "nil")")
            guard let contentController = controller else {
                self.log("open aborted key=\(String(describing: key)) title=\(title) controller=nil")
                return
            }
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
        writeBackState(for: key, entry: entry)
        windows.removeValue(forKey: key)
        entry.window.delegate = nil
        entry.window.close()
    }

    func close(for trackID: UUID) {
        close(for: .track(trackID))
    }

    func closeAll() {
        log("closeAll count=\(windows.count)")
        let entries = windows
        for (key, entry) in entries {
            writeBackState(for: key, entry: entry)
            entry.window.delegate = nil
            entry.window.close()
        }
        windows.removeAll(keepingCapacity: false)
    }

    func isOpen(for key: WindowKey) -> Bool {
        windows[key] != nil
    }

    func isOpen(for trackID: UUID) -> Bool {
        isOpen(for: .track(trackID))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let match = windows.first(where: { $0.value.window === sender }) else {
            return true
        }

        log("windowShouldClose hide key=\(String(describing: match.key))")
        writeBackState(for: match.key, entry: match.value)
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let match = windows.first(where: { $0.value.window === closingWindow })
        else {
            return
        }

        log("windowWillClose remove key=\(String(describing: match.key))")
        windows.removeValue(forKey: match.key)
    }

    private func writeBackState(for key: WindowKey, entry: WindowEntry) {
        if let presenter = entry.presenter {
            let state: Data?
            do {
                state = try presenter.captureHostedState()
            } catch {
                assertionFailure("AUWindowHost state capture failed: \(error)")
                NSLog("[AUWindowHost] state capture failed key=\(String(describing: key)) error=\(error)")
                state = nil
            }
            log("state writeback key=\(String(describing: key)) state=\((state ?? nil)?.count ?? 0) bytes")
            entry.stateWriteback(state ?? nil)
        } else {
            log("state writeback key=\(String(describing: key)) presenter gone")
            entry.stateWriteback(nil)
        }
    }
}

extension AUWindowHost: AUWindowHosting {}
