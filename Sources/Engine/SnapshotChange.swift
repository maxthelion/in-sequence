import Foundation

/// Summarises which playback-snapshot domains changed during a live-store mutation.
///
/// This is intentionally a value-type summary rather than a recursive enum so that
/// batched mutations can union their invalidation sets without duplicate work.
struct SnapshotChange: Equatable, Sendable {
    var selectedTrackChanged: Bool = false
    var selectedPhraseChanged: Bool = false
    var clipIDs: Set<UUID> = []
    var phraseIDs: Set<UUID> = []
    var trackIDs: Set<UUID> = []
    var patternBankTrackIDs: Set<UUID> = []
    var generatorIDs: Set<UUID> = []
    var layersChanged: Bool = false
    var fullRebuild: Bool = false

    static let none = SnapshotChange()

    static func clip(_ id: UUID) -> SnapshotChange {
        var change = SnapshotChange()
        change.clipIDs.insert(id)
        return change
    }

    static func phrase(_ id: UUID) -> SnapshotChange {
        var change = SnapshotChange()
        change.phraseIDs.insert(id)
        return change
    }

    static func track(_ id: UUID) -> SnapshotChange {
        var change = SnapshotChange()
        change.trackIDs.insert(id)
        return change
    }

    static func patternBank(_ trackID: UUID) -> SnapshotChange {
        var change = SnapshotChange()
        change.patternBankTrackIDs.insert(trackID)
        return change
    }

    static func generator(_ id: UUID) -> SnapshotChange {
        var change = SnapshotChange()
        change.generatorIDs.insert(id)
        return change
    }

    static let selectedTrack = SnapshotChange(selectedTrackChanged: true)
    static let selectedPhrase = SnapshotChange(selectedPhraseChanged: true)
    static let layers = SnapshotChange(layersChanged: true)
    static let full = SnapshotChange(fullRebuild: true)

    mutating func formUnion(_ other: SnapshotChange) {
        selectedTrackChanged = selectedTrackChanged || other.selectedTrackChanged
        selectedPhraseChanged = selectedPhraseChanged || other.selectedPhraseChanged
        clipIDs.formUnion(other.clipIDs)
        phraseIDs.formUnion(other.phraseIDs)
        trackIDs.formUnion(other.trackIDs)
        patternBankTrackIDs.formUnion(other.patternBankTrackIDs)
        generatorIDs.formUnion(other.generatorIDs)
        layersChanged = layersChanged || other.layersChanged
        fullRebuild = fullRebuild || other.fullRebuild
    }

    func union(_ other: SnapshotChange) -> SnapshotChange {
        var merged = self
        merged.formUnion(other)
        return merged
    }

    var requiresPlaybackSnapshotInstall: Bool {
        if fullRebuild || selectedPhraseChanged || layersChanged {
            return true
        }

        return !clipIDs.isEmpty ||
            !phraseIDs.isEmpty ||
            !trackIDs.isEmpty ||
            !patternBankTrackIDs.isEmpty ||
            !generatorIDs.isEmpty
    }
}
