import Foundation
import Observation

/// `@Observable` reference-type wrapper that holds the current compiled
/// `PlaybackSnapshot` for UI visualisation surfaces.
///
/// The session owns one publisher. `publishSnapshot()` compiles a new snapshot
/// and delivers the same value to both the engine (via `engineController.apply`)
/// and to this publisher. UI views bind to `snapshotPublisher.snapshot` so that
/// SwiftUI's observation system fires exactly once per publish cycle, not once
/// per store mutation.
///
/// This is a main-thread-only type. The engine's copy (held under `stateLock`)
/// is separate — the clock thread reads the engine copy; UI reads this one.
@Observable
@MainActor
final class SessionSnapshotPublisher {
    private(set) var snapshot: PlaybackSnapshot

    init(initial: PlaybackSnapshot) {
        self.snapshot = initial
    }

    /// Replace the held snapshot with the next compiled value.
    ///
    /// Called by `SequencerDocumentSession.publishSnapshot()` after the engine
    /// receives its copy. Both consumers receive the same compiled value.
    func replace(_ next: PlaybackSnapshot) {
        snapshot = next
    }
}
