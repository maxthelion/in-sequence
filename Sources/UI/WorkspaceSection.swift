import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable {
    case phrase
    case tracks
    case track
    case mixer
    case scenes
    case library

    var title: String {
        switch self {
        case .phrase:
            return "Phrase"
        case .tracks:
            return "Tracks"
        case .track:
            return "Track"
        case .mixer:
            return "Mixer"
        case .scenes:
            return "Scenes"
        case .library:
            return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .phrase:
            return "square.split.2x2"
        case .tracks:
            return "square.grid.3x3"
        case .track:
            return "waveform.path"
        case .mixer:
            return "slider.vertical.3"
        case .scenes:
            return "square.stack.3d.up"
        case .library:
            return "books.vertical"
        }
    }
}

/// The ONE global workspace mode (perform/setup split, slice 1): Setup
/// configures (what a thing IS); Perform plays (what you hear next bar).
/// Owned by `SequencerDocumentSession` as session-only UI state — like the
/// selected page, it defaults per session (`.setup`) and is never persisted
/// in the document. Every page derives its presentation from this single
/// value; there are no per-page mode toggles.
enum WorkspaceMode: String, CaseIterable, Identifiable {
    case setup
    case perform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup:
            return "Setup"
        case .perform:
            return "Perform"
        }
    }
}

// MARK: - Capture-harness vocabulary mapping
//
// The visual-command protocol predates the global mode: scenario scripts
// drive `tracksMode=edit|perform` and `scenesMode=browseEdit|perform` and
// assert the same keys in `.status` files (qa-surface-coverage.sh rows).
// Those legacy commands now map onto the one global mode, and the legacy
// status keys are derived back from it, so existing capture rows keep
// passing unchanged. New scenarios should use `workspaceMode=setup|perform`.
extension WorkspaceMode {
    init(tracksMode: TracksWorkspaceMode) {
        self = tracksMode == .perform ? .perform : .setup
    }

    init(scenesMode: ScenesWorkspaceMode) {
        self = scenesMode == .perform ? .perform : .setup
    }

    /// Legacy tracks-page vocabulary (`edit`/`perform`) derived from the
    /// global mode for `.status` emission.
    var tracksModeValue: TracksWorkspaceMode {
        self == .perform ? .perform : .edit
    }

    /// Legacy scenes-page vocabulary (`browseEdit`/`perform`) derived from
    /// the global mode for `.status` emission.
    var scenesModeValue: ScenesWorkspaceMode {
        self == .perform ? .perform : .browseEdit
    }
}
