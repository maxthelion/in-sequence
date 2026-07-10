import Foundation
import Observation

/// Session-local routing for selection-aware document editing commands.
///
/// Views register while they own the active editing surface. Clipboard payloads
/// outlive that registration and contain only the detached snapshot supplied by
/// the copying target.
@MainActor
@Observable
final class DocumentEditCommandController {
    struct Domain: Hashable, Sendable, ExpressibleByStringLiteral {
        let rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        init(stringLiteral value: StringLiteralType) {
            self.init(value)
        }
    }

    struct ClipboardPayload {
        let domain: Domain
        private let snapshot: Any

        init<Value>(domain: Domain, snapshot: Value) {
            self.domain = domain
            self.snapshot = snapshot
        }

        func value<Value>(as type: Value.Type = Value.self) -> Value? {
            snapshot as? Value
        }
    }

    struct Availability: Equatable {
        let canCopy: Bool
        let canPaste: Bool
        let canClear: Bool

        static let unavailable = Availability(
            canCopy: false,
            canPaste: false,
            canClear: false
        )
    }

    struct Target {
        let canCopy: () -> Bool
        let canClear: () -> Bool
        let isPasteCompatible: (ClipboardPayload) -> Bool
        let copy: () -> ClipboardPayload?
        let paste: (ClipboardPayload) -> Void
        let clearSelection: () -> Void

        init(
            canCopy: @escaping () -> Bool,
            canClear: @escaping () -> Bool,
            isPasteCompatible: @escaping (ClipboardPayload) -> Bool,
            copy: @escaping () -> ClipboardPayload?,
            paste: @escaping (ClipboardPayload) -> Void,
            clearSelection: @escaping () -> Void
        ) {
            self.canCopy = canCopy
            self.canClear = canClear
            self.isPasteCompatible = isPasteCompatible
            self.copy = copy
            self.paste = paste
            self.clearSelection = clearSelection
        }
    }

    struct OwnershipToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    private struct Registration {
        let token: OwnershipToken
        var target: Target
    }

    private var activeRegistration: Registration?
    private var availabilityRevision: UInt64 = 0
    private(set) var clipboardPayload: ClipboardPayload?

    var availability: Availability {
        _ = availabilityRevision
        guard let target = activeRegistration?.target else {
            return .unavailable
        }
        return Availability(
            canCopy: target.canCopy(),
            canPaste: clipboardPayload.map(target.isPasteCompatible) ?? false,
            canClear: target.canClear()
        )
    }

    /// Replaces the active target and returns the only token allowed to update
    /// or unregister that registration.
    @discardableResult
    func register(target: Target) -> OwnershipToken {
        let token = OwnershipToken(id: UUID())
        activeRegistration = Registration(token: token, target: target)
        return token
    }

    /// Refreshes closures for a still-active view. A replaced view cannot
    /// overwrite the current target with a stale update.
    @discardableResult
    func update(target: Target, ownership token: OwnershipToken) -> Bool {
        guard activeRegistration?.token == token else {
            return false
        }
        activeRegistration?.target = target
        return true
    }

    /// Removes a target only while its ownership token is current.
    @discardableResult
    func unregister(ownership token: OwnershipToken) -> Bool {
        guard activeRegistration?.token == token else {
            return false
        }
        activeRegistration = nil
        return true
    }

    /// Allows an active adapter to publish a selection change whose state is
    /// not otherwise observable by SwiftUI.
    func availabilityDidChange(ownership token: OwnershipToken) {
        guard activeRegistration?.token == token else { return }
        availabilityRevision &+= 1
    }

    @discardableResult
    func copy() -> Bool {
        guard let target = activeRegistration?.target,
              target.canCopy(),
              let payload = target.copy()
        else {
            return false
        }
        clipboardPayload = payload
        return true
    }

    @discardableResult
    func paste() -> Bool {
        guard let target = activeRegistration?.target,
              let payload = clipboardPayload,
              target.isPasteCompatible(payload)
        else {
            return false
        }
        target.paste(payload)
        availabilityRevision &+= 1
        return true
    }

    @discardableResult
    func clearSelection() -> Bool {
        guard let target = activeRegistration?.target, target.canClear() else {
            return false
        }
        target.clearSelection()
        availabilityRevision &+= 1
        return true
    }
}
