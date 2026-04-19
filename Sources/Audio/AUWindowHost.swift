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

    private struct WindowKey: Hashable {
        let trackID: UUID
        let tag: VoiceTag
    }

    private struct WindowEntry {
        weak var presenter: AudioUnitWindowPresentable?
        let window: NSWindow
        let stateWriteback: (Data?) -> Void
    }

    private var windows: [WindowKey: WindowEntry] = [:]

    func open(
        for trackID: UUID,
        tag: VoiceTag = defaultVoiceTag,
        presenter: AudioUnitWindowPresentable,
        title: String,
        stateWriteback: @escaping (Data?) -> Void
    ) {
        let key = WindowKey(trackID: trackID, tag: tag)
        if let existing = windows[key] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        presenter.requestHostedViewController { [weak self] controller in
            guard let self else {
                return
            }

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
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close(for trackID: UUID, tag: VoiceTag = defaultVoiceTag) {
        let key = WindowKey(trackID: trackID, tag: tag)
        guard let entry = windows[key] else {
            return
        }
        entry.window.close()
    }

    func isOpen(for trackID: UUID, tag: VoiceTag = defaultVoiceTag) -> Bool {
        windows[WindowKey(trackID: trackID, tag: tag)] != nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let match = windows.first(where: { $0.value.window === closingWindow })
        else {
            return
        }

        if let presenter = match.value.presenter {
            let state = try? presenter.captureHostedState()
            match.value.stateWriteback(state ?? nil)
        } else {
            match.value.stateWriteback(nil)
        }

        windows.removeValue(forKey: match.key)
    }
}
