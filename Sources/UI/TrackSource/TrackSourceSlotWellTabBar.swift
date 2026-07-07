import SwiftUI

enum TrackSourceHistoryDisplayState: Equatable {
    case liveCapture
    case unavailable(reason: String)

    var badgeTitle: String {
        switch self {
        case .liveCapture:
            return "Live"
        case .unavailable:
            return "N/A"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .liveCapture:
            return true
        case .unavailable:
            return false
        }
    }

    static func resolve(
        trackType: TrackType,
        sourceState: TrackSourceSourceDisplayState
    ) -> TrackSourceHistoryDisplayState {
        guard trackType != .slice else {
            return .unavailable(reason: "History is unavailable for slice tracks.")
        }

        switch sourceState {
        case .occupiedGenerator, .occupiedClip:
            return .liveCapture
        case .empty:
            return .unavailable(reason: "Assign a source to build live history.")
        }
    }
}

/// The melodic/poly track-detail section switcher: the D-pill grammar
/// (`StudioSectionPills`) floating above the `StudioTabWell`.
struct TrackSourceSectionPills: View {
    @Binding var selectedTab: TrackSourceEditorTab
    let accent: Color

    var body: some View {
        StudioSectionPills(
            pills: [
                StudioSectionPill(
                    section: TrackSourceEditorTab.stepsClip,
                    title: TrackSourceEditorTab.stepsClip.title,
                    accessibilityIdentifier: "track-detail-tab-steps-clip"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.history,
                    title: TrackSourceEditorTab.history.title,
                    accessibilityIdentifier: "track-detail-tab-history"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.sound,
                    title: TrackSourceEditorTab.sound.title,
                    accessibilityIdentifier: "track-detail-tab-sound"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.fx,
                    title: TrackSourceEditorTab.fx.title,
                    accessibilityIdentifier: "track-detail-tab-fx"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.macros,
                    title: TrackSourceEditorTab.macros.title,
                    accessibilityIdentifier: "track-detail-tab-macros"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.mixer,
                    title: TrackSourceEditorTab.mixer.title,
                    accessibilityIdentifier: "track-mixer-tab"
                ),
            ],
            selection: selectedTab,
            accent: accent,
            accessibilityIdentifier: "track-detail-tabs",
            onSelect: { selectedTab = $0 }
        )
    }
}
